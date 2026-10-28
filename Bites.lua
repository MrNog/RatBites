local ADDON, ns = ...

-- Numbers for what you and your pet do and what is done to you, each with its spell icon. A number
-- floats (on the unit's nameplate or a fixed spot) in the chosen animation and fades, or goes into one
-- of the boxes (Boxes.lua) as a line.

local FADE_AT = 0.65      -- share of a number's time before its fade starts
local SIZE = 20           -- a normal hit's font size at scale 1, and every icon's size
ns.SIZE = SIZE
local MAX_TEXTS = 40
local ATTACK_ICON = [[Interface\Icons\INV_Sword_04]]

ns.FONTS = {
	{ "friz", "Friz Quadrata", STANDARD_TEXT_FONT },
	{ "arial", "Arial Narrow", [[Fonts\ARIALN.TTF]] },
	{ "morpheus", "Morpheus", [[Fonts\MORPHEUS.TTF]] },
	{ "skurri", "Skurri", [[Fonts\SKURRI.TTF]] },
}

-- Crit colours are saturated and drawn with a thick outline (thick = true), so a crit stands out
-- from the softer normal numbers at a glance.
local COLOR = {
	normal = { 0.72, 0.72, 0.72 },
	big = { 1, 0.82, 0 },
	crit = { 1, 0.4, 0, thick = true },
	miss = { 0.9, 0.9, 0.9 },
	heal = { 0.4, 0.88, 0.45 },
	healCrit = { 0.25, 1, 0.72, thick = true },
	overheal = { 0.45, 0.62, 0.45 },
	shield = { 0.55, 0.82, 1 },
	buff = { 1, 0.9, 0.55 },
	taken = { 0.88, 0.32, 0.27 },
	takenCrit = { 1, 0.22, 0.45, thick = true },
}
ns.COLOR = COLOR

-- The game's four fonts, then every font other addons registered with LibSharedMedia (ElvUI's,
-- SharedMedia packs), keyed "lsm:<name>". Read when the settings window is built, after they loaded.
function ns.FontList()
	local list = {}
	for _, f in ipairs(ns.FONTS) do list[#list + 1] = { f[1], f[2] } end
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM then
		for _, name in ipairs(LSM:List("font")) do
			local path = LSM:Fetch("font", name)
			local builtIn = false
			for _, f in ipairs(ns.FONTS) do
				if f[3]:lower() == (path or ""):lower() then builtIn = true end
			end
			if not builtIn then list[#list + 1] = { "lsm:" .. name, name } end
		end
	end
	return list
end

-- Every floating number and box line gets a new serial when it is (re)used, so a later shield can
-- tell the number its heal made from a pooled one now showing something else.
local serial = 0
function ns.NextSerial()
	serial = serial + 1
	return serial
end

function ns.FontPath()
	local key = ns.db.font
	local name = key:match("^lsm:(.+)")
	if name then
		local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
		local path = LSM and LSM:Fetch("font", name, true)
		if path then return path end
	end
	for _, f in ipairs(ns.FONTS) do
		if f[1] == key then return f[3] end
	end
	return STANDARD_TEXT_FONT
end

-- Hidden effect spells whose own icon is missing or blank borrow the icon of the spell players know:
-- Beacon of Light passes each heal on through 53652 / 53654, shown with the beacon itself (53563).
local ICON_FROM = { [53652] = 53563, [53654] = 53563 }

local icons = {}
local function SpellIcon(id)
	if not id then return nil end
	if icons[id] == nil then
		local icon = select(3, GetSpellInfo(ICON_FROM[id] or id))
		if not icon or icon == "" then icon = select(3, GetSpellInfo(id)) end
		icons[id] = (icon and icon ~= "") and icon or false
	end
	return icons[id] or nil
end

local function Abbrev(v)
	local mode = ns.db.numbers
	if mode == "short" then
		if v >= 1e6 then return (format("%.1fm", v / 1e6):gsub("%.0m", "m")) end
		if v >= 1e4 then return (format("%.1fk", v / 1e3):gsub("%.0k", "k")) end
	elseif mode == "full" then
		local s, n = tostring(v), 1
		while n > 0 do s, n = s:gsub("^(%d+)(%d%d%d)", "%1,%2") end
		return s
	end
	return tostring(v)
end
ns.Abbrev = Abbrev

-- A hit well above your recent ones is a big hit: compared with the last 8 normal hits of the last
-- 30 sec, once there are at least 3.
local samples = {}
local function IsBig(amount)
	local now = GetTime()
	for i = #samples, 1, -1 do
		if now - samples[i].t > 30 then table.remove(samples, i) end
	end
	local sum = 0
	for _, s in ipairs(samples) do sum = sum + s.v end
	local big = #samples >= 3 and amount >= sum / #samples * 1.2
	table.insert(samples, { t = now, v = amount })
	if #samples > 8 then table.remove(samples, 1) end
	return big
end

--------------------------------------------------------------------------------
-- the floating texts
--------------------------------------------------------------------------------

local root = CreateFrame("Frame", nil, UIParent)
root:SetAllPoints(UIParent)
root:SetFrameStrata("LOW")

local pool, active, queued = {}, {}, {}
local arc = 1

-- how far a number drifts sideways while it rises: at least [1], plus up to [2] more at random
local SPREAD = { none = { 0, 0 }, tight = { 8, 8 }, normal = { 15, 15 }, wide = { 35, 30 } }

-- Numbers that land on the same spot together (a heal and its proc, a multi-hit) would start on top
-- of each other, so each one within STACK_TIME of the last starts a line higher, up to STACK_MAX.
local STACK_TIME, STACK_MAX = 0.5, 6  -- 6: Holy Light and its glyph's five splashes
local stacks = {}  -- plate or spot -> { at = time of the last number, n = its line }

local function StackLine(key, size)
	local now = GetTime()
	local s = stacks[key]
	if s and now - s.at < STACK_TIME then
		s.n = (s.n + 1) % STACK_MAX
	else
		s = { n = 0 }
		stacks[key] = s
	end
	s.at = now
	return s.n * (size + 4)
end

-- Each number moves by WoW's own animation system, so the engine moves it smoothly between frames:
-- its spot is set once, then animations slide it. Sideways moves at a steady pace while the rise
-- eases out, which together make the arc; the fade is an animation too.
-- The client turns down a font size that is too big (the text then keeps its old, small font), so a
-- number bigger than FONT_MAX (a big crit) is drawn at FONT_MAX and its frame scaled up the rest;
-- the frame's offsets are scaled with it, so they are divided back.
-- A popping crit lands like a bomb: it appears BOMB times bigger and shrinks smoothly back over
-- BOMB_TIME, sized by hand for that moment (its spot kept), and only then does its path start.
local START_GAP = 12  -- how far above the plate a number starts
local FONT_MAX = 32
local BOMB, BOMB_TIME = 2.5, 0.25

local function Finished(group)
	local t = group.owner
	for i = #active, 1, -1 do
		if active[i] == t then
			table.remove(active, i)
			break
		end
	end
	t:Hide()
	t.plate = nil
	table.insert(pool, t)
end

local function Acquire()
	local t = table.remove(pool)
	if t then return t end
	t = CreateFrame("Frame", nil, root)
	t:SetWidth(1); t:SetHeight(1)
	t.text = t:CreateFontString(nil, "OVERLAY")
	t.text:SetPoint("CENTER")
	t.text:SetShadowColor(0, 0, 0, 1)
	t.text:SetShadowOffset(1, -1)
	t.edge = t:CreateTexture(nil, "ARTWORK")
	t.edge:SetTexture(ns.FLAT)
	t.edge:SetVertexColor(0, 0, 0)
	t.icon = t:CreateTexture(nil, "OVERLAY")
	t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	t.icon:SetPoint("RIGHT", t.text, "LEFT", -4, 0)
	t.edge:SetPoint("TOPLEFT", t.icon, "TOPLEFT", -1, 1)
	t.edge:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", 1, -1)
	-- order 1 is the whole path for most animations; Fountain goes up in order 1, down in order 2
	local g = t:CreateAnimationGroup()
	g.owner = t
	g:SetScript("OnFinished", Finished)
	t.group = g
	t.x1 = g:CreateAnimation("Translation"); t.x1:SetOrder(1)
	t.y1 = g:CreateAnimation("Translation"); t.y1:SetOrder(1)
	t.x2 = g:CreateAnimation("Translation"); t.x2:SetOrder(2)
	t.y2 = g:CreateAnimation("Translation"); t.y2:SetOrder(2)
	t.fade = g:CreateAnimation("Alpha")
	t.fade:SetChange(-1)
	return t
end

local function Leg(a, x, y, duration, smoothing, delay)
	a:SetOffset(x, y)
	a:SetDuration(math.max(0.01, duration))
	a:SetSmoothing(smoothing)
	a:SetStartDelay(delay or 0)
end

-- the frame at scale k with its spot kept (a frame's point offsets are in its own scaled units)
local function Place(t, k)
	t:SetScale(k)
	t:ClearAllPoints()
	t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", t.px / k, t.py / k)
end

local function Bombing(group, elapsed)
	local t = group.owner
	t.bombed = t.bombed + elapsed
	local f = 1 - t.bombed / BOMB_TIME
	if f <= 0 then
		Place(t, t.frameScale)
		group:SetScript("OnUpdate", nil)
		return
	end
	Place(t, t.frameScale * (1 + (BOMB - 1) * f * f))
end

-- Sets the number's path (h is the Height setting, dx its sideways drift), in its frame's units,
-- after a popping crit's bomb:
--   arc: drifts sideways while the rise eases out   rise: straight up   stay: holds, only fades
--   fountain: up, then back down past its start   fall: starts h above and drifts down to it
local function Plan(t, pop)
	local k = t.frameScale
	local d, h, dx = t.duration, t.rise / k, t.dx / k
	local wait = pop and BOMB_TIME or 0
	local fadeAt, fadeLen = d * FADE_AT, d * (1 - FADE_AT)
	if t.anim == "fountain" then
		local up = d * 0.45
		Leg(t.x1, dx * 0.45, 0, up, "NONE", wait)
		Leg(t.y1, 0, h, up, "OUT", wait)
		Leg(t.x2, dx * 0.55, 0, d - up, "NONE")
		Leg(t.y2, 0, -h * 1.2, d - up, "IN")
		t.fade:SetOrder(2)
		t.fade:SetStartDelay(math.max(0, fadeAt - up))
	else
		local x, y, smoothing = dx, h, "OUT"
		if t.anim == "rise" then x = 0 end
		if t.anim == "stay" then x, y = 0, 0 end
		if t.anim == "fall" then x, y, smoothing = 0, -h, "IN_OUT" end
		Leg(t.x1, x, 0, d, "NONE", wait)
		Leg(t.y1, 0, y, d, smoothing, wait)
		Leg(t.x2, 0, 0, 0.01, "NONE")
		Leg(t.y2, 0, 0, 0.01, "NONE")
		t.fade:SetOrder(1)
		t.fade:SetStartDelay(wait + fadeAt)
	end
	t.fade:SetDuration(fadeLen)
end

-- plate: the nameplate the number starts over (nil: the spot x, y in UIParent units); column: a
-- fixed spot's straight column, which always rises
local function Show(plate, name, x, y, label, color, size, icon, pop, column)
	if #active >= MAX_TEXTS then
		local oldest = active[1]
		oldest.group:Stop()
		Finished(oldest.group)
	end
	local t = Acquire()
	local db = ns.db
	t.group:Stop()
	t:SetAlpha(1)
	-- a crit draws above every other number, so it shows through a pile of heals
	t:SetFrameLevel(root:GetFrameLevel() + (color.thick and 20 or 1))
	-- the size it should show at (Text size included), drawn at up to FONT_MAX and scaled the rest;
	-- every icon has one size (a normal hit's), so crits grow only their text
	local want = size * db.scale
	local fontPx = math.min(FONT_MAX, math.floor(want + 0.5))
	t.frameScale = want / fontPx
	t:SetScale(t.frameScale)
	-- a new font string takes no text before it has a font
	-- A scaled-up number scales its outline and shadow too: past the font limit the thick outline
	-- turns into a fat black edge, so it takes the thin one, and the shadow keeps one screen pixel.
	local thick = color.thick and t.frameScale < 1.2
	t.text:SetFont(ns.FontPath(), fontPx, thick and "THICKOUTLINE" or "OUTLINE")
	t.text:SetShadowOffset(1 / t.frameScale, -1 / t.frameScale)
	t.text:SetText(label)
	t.text:SetTextColor(color[1], color[2], color[3])
	-- every icon has one size (a normal hit's), crits too: only their text grows. The black edge
	-- around it stays one screen pixel however much the frame is scaled.
	local iconSize = SIZE * db.scale * db.iconScale / t.frameScale
	t.icon:SetWidth(iconSize); t.icon:SetHeight(iconSize)
	local edge = 1 / t.frameScale
	t.edge:ClearAllPoints()
	t.edge:SetPoint("TOPLEFT", t.icon, "TOPLEFT", -edge, edge)
	t.edge:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", edge, -edge)
	if icon and db.icons then
		t.icon:SetTexture(icon)
		t.icon:Show(); t.edge:Show()
	else
		t.icon:Hide(); t.edge:Hide()
	end
	t.plate, t.name, t.x, t.y = plate, name, x, y
	-- A number on a plate starts over the plate's top, read once here: from then on the animation
	-- moves it, since a plate shifts a pixel or two every frame as you or the camera move.
	if plate then
		local cx, top = plate:GetCenter(), plate:GetTop()
		if cx and top then
			local s = plate:GetEffectiveScale() / UIParent:GetEffectiveScale()
			t.x, t.y = cx * s, top * s
		end
	end
	t.label, t.shield, t.serial = label, nil, ns.NextSerial()
	ns.lastShown = t
	t.anim = column and "rise" or db.animation
	t.rise, t.duration = db.height, db.duration
	t.line = StackLine(plate or format("%d:%d", x, y), size)
	if column then
		t.dx = 0
	else
		arc = -arc
		local sp = SPREAD[db.spread] or SPREAD.normal
		t.dx = arc * (sp[1] + math.random() * sp[2])
	end
	local startY = t.y + (column and 0 or START_GAP) + t.line * db.scale
	-- a crit starts a normal line above the rest, so at its size it doesn't cover hits landing with it
	if color.thick then startY = startY + (SIZE + 6) * db.scale end
	if t.anim == "fall" then startY = startY + t.rise end
	t.px, t.py = math.floor(t.x + 0.5), math.floor(startY + 0.5)
	if pop then
		t.bombed = 0
		Place(t, t.frameScale * BOMB)
		t.group:SetScript("OnUpdate", Bombing)
	else
		Place(t, t.frameScale)
		t.group:SetScript("OnUpdate", nil)
	end
	Plan(t, pop)
	t:Show()
	table.insert(active, t)
	t.group:Play()
end

root:SetScript("OnUpdate", function()
	local now = GetTime()
	for i = #queued, 1, -1 do
		local q = queued[i]
		if now >= q.at then
			table.remove(queued, i)
			q.fn()
		end
	end
end)

-- what floats "over me" rises from just above the screen's centre, where the camera keeps your
-- character
local function MeSpot()
	return UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 + 40
end

--------------------------------------------------------------------------------
-- the combat log
--------------------------------------------------------------------------------

local band = bit.band
local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE
local PET = bit.bor(COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_TYPE_GUARDIAN)

local function Who(guid, flags)
	if guid == ns.playerGUID then return "player" end
	if band(flags, MINE) ~= 0 and band(flags, PET) ~= 0 then return "pet" end
end

-- Absorb shields you put on someone, matched by name, which covers every rank. The 3.3.5a combat log
-- gives no absorb amount; ShieldSize works it out where the game's rules allow, otherwise the shield
-- shows as the word "Shield" with its icon.
ns.SHIELDS = {}
for _, id in ipairs({ 17, 47753, 58597, 64413 }) do  -- Power Word: Shield, Divine Aegis, Sacred Shield, Val'anyr
	local name = GetSpellInfo(id)
	if name then ns.SHIELDS[name] = true end
end
local HEALING = { heal = true, overheal = true, shield = true, buff = true }

-- buffs you put on someone that show as a word with their icon when they land: name -> word
local MARKS = {}
do
	local name = GetSpellInfo(53563)  -- Beacon of Light
	if name then MARKS[name] = "Beacon" end
end

-- Val'anyr's shield (Protection of Ancient Kings) has a generic shield icon that reads like another
-- class's shield, so it shows the mace itself (item 46017, Val'anyr, Hammer of Ancient Kings).
local ITEM_ICONS = { [64413] = 46017 }

-- Shield sizes from the game's rules: Val'anyr shields for 15% of the heal that made it, Divine Aegis
-- for 30% of the critical heal, both read from your last heal on that player a moment before (the
-- shield lands with it). Sacred Shield absorbs 500 plus 75% of your spell power. Power Word: Shield
-- hangs on talents and glyphs the log can't see, so it stays a word.
local HEAL_SHARE = { [64413] = 0.15, [47753] = 0.30 }
local SACRED_SHIELD = 58597
local lastHeal = {}  -- GUID -> { amount, crit, at } of your last heal on them

local function ShieldSize(id, guid)
	local share = HEAL_SHARE[id]
	if share then
		local h = lastHeal[guid]
		if h and GetTime() - h.at < 0.5 and h.amount then return math.floor(h.amount * share + 0.5) end
		return nil
	end
	if id == SACRED_SHIELD and GetSpellBonusHealing then
		return math.floor(500 + 0.75 * GetSpellBonusHealing() + 0.5)
	end
end
local function ShieldIcon(id)
	local item = ITEM_ICONS[id]
	if item then
		local icon = (GetItemIcon and GetItemIcon(item)) or select(10, GetItemInfo(item))
		if icon then return icon end
	end
	return SpellIcon(id)
end

-- kind ("swing", "spell", "dot", "heal", "overheal", "shield" or "miss"), amount, crit, icon, miss type
local function Read(event, ...)
	if event == "SWING_DAMAGE" then
		local amount, _, _, _, _, _, crit = ...
		return "swing", amount, crit, ATTACK_ICON
	elseif event == "RANGE_DAMAGE" then
		local id, _, _, amount, _, _, _, _, _, crit = ...
		return "swing", amount, crit, SpellIcon(id)
	elseif event == "SPELL_DAMAGE" or event == "DAMAGE_SHIELD" or event == "DAMAGE_SPLIT" then
		local id, _, _, amount, _, _, _, _, _, crit = ...
		return "spell", amount, crit, SpellIcon(id)
	elseif event == "SPELL_PERIODIC_DAMAGE" then
		local id, _, _, amount, _, _, _, _, _, crit = ...
		return "dot", amount, crit, SpellIcon(id)
	elseif event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
		local id, _, _, amount, over, _, crit = ...
		local healed = amount - (over or 0)
		-- a heal on someone already full still shows, dimmed, with what it would have healed
		if healed <= 0 then return "overheal", amount, crit, SpellIcon(id) end
		return "heal", healed, crit, SpellIcon(id)
	elseif event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
		local id, spellName, _, auraType = ...
		if auraType == "BUFF" and ns.SHIELDS[spellName] then return "shield", nil, nil, ShieldIcon(id) end
		-- a buff worth seeing land (Beacon of Light), as its short word, once when it goes on
		if auraType == "BUFF" and event == "SPELL_AURA_APPLIED" and MARKS[spellName] then
			return "buff", nil, nil, SpellIcon(id), MARKS[spellName]
		end
	elseif event == "SWING_MISSED" then
		local missType = ...
		return "miss", nil, nil, ATTACK_ICON, missType
	elseif event == "SPELL_MISSED" or event == "RANGE_MISSED" or event == "SPELL_PERIODIC_MISSED" then
		local id, _, _, missType = ...
		return "miss", nil, nil, SpellIcon(id), missType
	end
end

-- the text, colour, font size and pop of one of your numbers
local function Style(who, kind, amount, crit, miss)
	local db = ns.db
	local label, color, size, pop = nil, COLOR.normal, SIZE, false
	if kind == "miss" then
		-- DODGE, PARRY, IMMUNE ... are the game's own words for each miss
		label, color, size = _G[miss] or miss, COLOR.miss, SIZE * 0.8
	elseif kind == "shield" then
		label, color, size = amount and "+" .. Abbrev(amount) or "Shield", COLOR.shield, SIZE * 0.85
	elseif kind == "buff" then
		label, color, size = miss, COLOR.buff, SIZE * 0.85
	else
		label = Abbrev(amount)
		if kind == "heal" or kind == "overheal" then
			label, color = "+" .. label, kind == "heal" and COLOR.heal or COLOR.overheal
		elseif db.classColorFor == "normal" and ns.classColor then
			color = ns.classColor
		end
		if kind == "dot" then size = SIZE * 0.9 end
		if crit then
			if kind ~= "overheal" and db.classColorFor == "crit" and ns.classCrit then
				color = ns.classCrit
			elseif kind == "heal" then
				color = COLOR.healCrit
			elseif kind ~= "overheal" then
				color = COLOR.crit
			end
			if db.critStyle == "big" then size = size * db.critSize end
			if db.critStyle == "pop" then size, pop = size * db.critSize, true end
		elseif (kind == "swing" or kind == "spell") and db.bigGold and IsBig(amount) then
			color, size = COLOR.big, SIZE * 1.15
		end
	end
	if who == "pet" then size = size * 0.8 end
	return label, color, size, pop
end

--------------------------------------------------------------------------------
-- where a number goes: the Where grid. Each row (dmg = your damage, heal = your heals on others,
-- healMe / dmgMe = heals and damage landing on you) ticks any of: plate (over the unit's nameplate),
-- me (over your character), mine (My box), recv (Received box). Nothing ticked hides that kind.
--------------------------------------------------------------------------------

local function Route(row, plate, name, label, color, size, icon, pop, amount, sign)
	local db = ns.db
	local r = db.route[row]
	local onMe = row == "healMe" or row == "dmgMe"
	-- your own character has no nameplate: for what lands on you, "over the nameplate" is over you
	if r.plate and plate then
		Show(plate, name, 0, 0, label, color, size, icon, pop)
	elseif r.plate and not onMe and not r.mine and db.noPlateToBox then
		-- wanted over a nameplate that isn't on screen (pets, totems, far away): My box instead
		ns.BoxAdd("mine", label, color, size, icon, amount, sign)
	end
	if r.me or (onMe and r.plate) then
		local x, y = MeSpot()
		Show(nil, nil, x, y, label, color, size, icon, pop, true)
	end
	if r.mine then ns.BoxAdd("mine", label, color, size, icon, amount, sign) end
	if r.recv then ns.BoxAdd("received", label, color, size, icon, amount, sign) end
end

local function Ticked(r) return r.plate or r.me or r.mine or r.recv end

-- the What filters: kinds of hits, misses, pets, overheal and shields can each be turned off
local function Wanted(who, kind, amount, crit)
	local show = ns.db.show
	if who == "pet" and not show.pet then return false end
	if kind == "overheal" then return show.overheal end
	if kind == "shield" then return show.shield end
	if kind == "heal" or kind == "buff" then return true end
	if not show[kind] then return false end
	if amount and not show[crit and "crit" or "normal"] then return false end
	return true
end

local function Outgoing(who, guid, name, kind, amount, crit, icon, miss)
	if amount and amount <= 0 then return end
	if not Wanted(who, kind, amount, crit) then return end
	local heal = HEALING[kind]
	local row = heal and "heal" or "dmg"
	local r = ns.db.route[row]
	if not Ticked(r) then return end
	local plate
	if r.plate then
		plate = ns.PlateFor(guid, name)
		ns.lastDest, ns.lastDestPlate = name, plate
	end
	local label, color, size, pop = Style(who, kind, amount, crit, miss)
	Route(row, plate, name, label, color, size, icon, pop, amount, heal and "+" or "")
end

local function Received(kind, amount, crit, icon, word)
	if kind == "miss" then return end
	if (kind == "overheal" or kind == "shield") and not Wanted("player", kind) then return end
	local heal = HEALING[kind]
	local row = heal and "healMe" or "dmgMe"
	if not Ticked(ns.db.route[row]) then return end
	local label, color
	if kind == "shield" then
		label, color = amount and "+" .. Abbrev(amount) or "Shield", COLOR.shield
	elseif kind == "buff" then
		label, color = word, COLOR.buff
	elseif not amount or amount <= 0 then
		return
	elseif kind == "overheal" then
		label, color = "+" .. Abbrev(amount), COLOR.overheal
	elseif kind == "heal" then
		label, color = "+" .. Abbrev(amount), crit and COLOR.healCrit or COLOR.heal
	else
		label, color = "-" .. Abbrev(amount), crit and COLOR.takenCrit or COLOR.taken
	end
	local size = crit and SIZE * 1.2 or SIZE * 0.9
	Route(row, nil, nil, label, color, size, icon, crit and ns.db.critStyle == "pop", amount, heal and "+" or "-")
end

-- /bites last: the last combat-log lines RatBites read (yours, or landing on you), what it made of
-- each and where it went, to find out why a number didn't show
local trace, TRACE_MAX = {}, 12

local function Trace(event, sourceGUID, destGUID, destName, kind, amount, id, spellName)
	local db = ns.db
	local onMe = destGUID == ns.playerGUID
	local row = kind and (onMe and (HEALING[kind] and "healMe" or "dmgMe") or (HEALING[kind] and "heal" or "dmg"))
	local r = row and db.route[row]
	local places = {}
	if r then
		for _, key in ipairs({ "plate", "me", "mine", "recv" }) do
			if r[key] then places[#places + 1] = key end
		end
	end
	local spell = type(spellName) == "string" and spellName or "melee"
	local line = format("%s %s -> %s: %s %s%s", date("%H:%M:%S"), event, onMe and "you" or tostring(destName),
		tostring(spell), kind and (kind .. " " .. tostring(amount or "")) or "not shown",
		r and (" [" .. (#places > 0 and table.concat(places, " ") or "nowhere") .. "]") or "")
	table.insert(trace, line)
	if #trace > TRACE_MAX then table.remove(trace, 1) end
end

function ns.PrintTrace()
	if #trace == 0 then ns.Print("nothing read yet") return end
	for _, line in ipairs(trace) do ns.Print(line) end
end

ns.On("COMBAT_LOG_EVENT_UNFILTERED", function(_, event, sourceGUID, _, sourceFlags, destGUID, destName, _, ...)
	local db = ns.db
	if not db or not db.enabled or not ns.playerGUID then return end
	local who = Who(sourceGUID, sourceFlags)
	local toMe = destGUID == ns.playerGUID
	if not who and not toMe then return end
	if who and (event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL") then
		local _, _, _, healed, _, _, healCrit = ...
		local h = lastHeal[destGUID] or {}
		h.amount, h.crit, h.at = healed, healCrit, GetTime()
		lastHeal[destGUID] = h
	end
	local kind, amount, crit, icon, miss = Read(event, ...)
	Trace(event, sourceGUID, destGUID, destName, kind, amount, ...)
	if not kind then return end
	-- your own auto-attacks show the weapon doing them: main hand for swings, the ranged slot for
	-- Auto Shot, wands and throws (an empty slot keeps the plain sword)
	if who == "player" then
		if event == "SWING_DAMAGE" or event == "SWING_MISSED" then
			icon = GetInventoryItemTexture("player", 16) or icon
		elseif event == "RANGE_DAMAGE" or event == "RANGE_MISSED" then
			icon = GetInventoryItemTexture("player", 18) or icon
		end
	end
	-- The Spells tab: every spell of yours RatBites shows is remembered there (by name, so all its
	-- ranks are one), and one you untick there doesn't show. Swings go by the game's word for melee.
	if who then
		local spell = event:find("^SWING") and MELEE or select(2, ...)
		if type(spell) == "string" then
			-- a miss or an immune is no number: it doesn't list a spell
			if kind ~= "miss" and type(db.seen[spell]) ~= "string" then db.seen[spell] = icon or true end
			if db.hideSpells[spell] then return end
		end
	end
	if kind == "shield" then
		amount = ShieldSize((...), destGUID)
		-- a refresh only shows when it has a size to tell: Val'anyr refreshes on every heal
		if event == "SPELL_AURA_REFRESH" and not amount then return end
		-- a shield made by your heal (Val'anyr, Divine Aegis): joined to that heal's number, or on
		-- its own line, as the What tab says
		if amount and HEAL_SHARE[(...)] then
			if not db.show.shield then return end
			local h = lastHeal[destGUID]
			local el = h and h.el
			if db.joinShields and el and el.serial == h.serial and el:IsShown() then
				ns.JoinShield(el, amount)
				return
			end
		end
	end
	ns.lastShown = nil
	-- output is what you do to others; receiving is everything that lands on you, your own
	-- self-heals and shields included
	if toMe then
		Received(kind, amount, crit, icon, miss)
	else
		Outgoing(who, destGUID, destName, kind, amount, crit, icon, miss)
	end
	-- remember where your heal's number went, for the shield that follows it
	if who and (kind == "heal" or kind == "overheal") and lastHeal[destGUID] then
		local el = ns.lastShown
		lastHeal[destGUID].el, lastHeal[destGUID].serial = el, el and el.serial
	end
end)

ns.On("PLAYER_LOGIN", function()
	local c = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
	if c then
		-- a dark class colour (Death Knight red, Shaman blue) is lifted toward white until it reads
		-- on a dark fight, keeping its hue
		local r, g, b = c.r, c.g, c.b
		local light = 0.3 * r + 0.59 * g + 0.11 * b
		if light < 0.55 then
			local lift = (0.55 - light) / (1 - light)
			r, g, b = r + (1 - r) * lift, g + (1 - g) * lift, b + (1 - b) * lift
		end
		ns.classColor = { r, g, b }
		ns.classCrit = { r, g, b, thick = true }
	end
end)

--------------------------------------------------------------------------------
-- the Test button: a round of samples every 2 sec until it is turned off, to watch a change land
--------------------------------------------------------------------------------

local loop = CreateFrame("Frame")
loop:Hide()
local wait = 0
loop:SetScript("OnUpdate", function(_, elapsed)
	wait = wait - elapsed
	if wait <= 0 then
		wait = 2
		ns.Test()
	end
end)

function ns.TestLooping() return loop:IsShown() end

function ns.SetTestLoop(on)
	wait = 0
	if on then loop:Show() else loop:Hide() end
end

--------------------------------------------------------------------------------
-- /bites test: one of each kind where your settings send it
--------------------------------------------------------------------------------

function ns.Test()
	local book = {}
	for i = 1, 40 do
		local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
		if not tex then break end
		book[#book + 1] = tex
	end
	local function pick() return book[math.random(math.max(#book, 1))] or ATTACK_ICON end
	local db = ns.db
	local guid, name = UnitGUID("target"), UnitName("target")
	local plate = guid and ns.PlateFor(guid, name)
	local critSize = SIZE * (db.critStyle == "plain" and 1 or db.critSize)
	-- label, colour, size, pop, Where row
	local hits = {
		{ "1234", COLOR.normal, SIZE, false, "dmg" },
		{ Abbrev(2331), COLOR.big, SIZE * 1.15, false, "dmg" },
		{ Abbrev(12431), COLOR.crit, critSize, db.critStyle == "pop", "dmg" },
		{ DODGE, COLOR.miss, SIZE * 0.8, false, "dmg" },
		{ "+" .. Abbrev(812), COLOR.heal, SIZE, false, "heal" },
		{ "Shield", COLOR.shield, SIZE * 0.85, false, "heal" },
		{ "-" .. Abbrev(640), COLOR.taken, SIZE * 0.9, false, "dmgMe" },
		{ "+" .. Abbrev(1923), COLOR.heal, SIZE * 0.9, false, "healMe" },
	}
	for i, h in ipairs(hits) do
		table.insert(queued, { at = GetTime() + (i - 1) * 0.25, fn = function()
			Route(h[5], plate, name, h[1], h[2], h[3], pick(), h[4])
		end })
	end
end

--------------------------------------------------------------------------------
-- /bites colors: every kind of number in its colour, size and outline as your settings draw it
--------------------------------------------------------------------------------

local legend

-- label, colour, sample, size against a normal hit; built on each opening, so it follows the settings
local function LegendEntries()
	local db = ns.db
	local critSize = db.critStyle == "plain" and 1 or db.critSize
	local normal = db.classColorFor == "normal" and ns.classColor or COLOR.normal
	local crit = db.classColorFor == "crit" and ns.classCrit or COLOR.crit
	local healCrit = db.classColorFor == "crit" and ns.classCrit or COLOR.healCrit
	return {
		{ "Normal hit", normal, "1234", 1 },
		{ "Big hit", db.bigGold and COLOR.big or normal, "2331", 1.15 },
		{ "Critical hit", crit, "4.8k", critSize },
		{ "Damage over time", normal, "412", 0.8 },
		{ "Pet", normal, "310", 0.8 },
		{ "Miss", COLOR.miss, DODGE, 0.8 },
		{ "Heal", COLOR.heal, "+1923", 1 },
		{ "Heal crit", healCrit, "+4.1k", critSize },
		{ "Overheal", COLOR.overheal, "+1.2k", 1 },
		{ "Shield", COLOR.shield, "+177", 0.85 },
		{ "Damage taken", COLOR.taken, "-640", 0.9 },
		{ "Damage taken crit", COLOR.takenCrit, "-2.1k", 1.2 },
	}
end

local LEGEND_W, LEGEND_ROW, LEGEND_TOP = 340, 34, -44

local function BuildLegend()
	local f = CreateFrame("Frame", "RatBitesColors", UIParent)
	f:SetWidth(LEGEND_W)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:SetPoint("CENTER", 380, 0)
	ns.SkinWindow(f)
	tinsert(UISpecialFrames, "RatBitesColors")
	local head, title = ns.TitleBar(f, 30)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() f:StartMoving() end)
	head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	title:SetText("RatBites colors")
	f.rows = {}
	local count = #LegendEntries()
	for i = 1, count do
		local row = CreateFrame("Frame", nil, f)
		row:SetPoint("TOPLEFT", 22, LEGEND_TOP - (i - 1) * LEGEND_ROW)
		row:SetWidth(LEGEND_W - 44)
		row:SetHeight(LEGEND_ROW)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetPoint("LEFT", 0, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.number = row:CreateFontString(nil, "OVERLAY")
		row.number:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.number:SetShadowColor(0, 0, 0, 1)
		row.number:SetShadowOffset(1, -1)
		row.name = row:CreateFontString(nil, "OVERLAY")
		row.name:SetFont(STANDARD_TEXT_FONT, 13)
		row.name:SetTextColor(ns.rgb(ns.C.textDim))
		row.name:SetPoint("RIGHT", 0, 0)
		f.rows[i] = row
	end
	f:SetHeight(-LEGEND_TOP + count * LEGEND_ROW + 16)
	return f
end

local function PaintLegend()
	local db = ns.db
	local icon = GetInventoryItemTexture("player", 16) or ATTACK_ICON
	local iconSize = SIZE * db.iconScale
	for i, e in ipairs(LegendEntries()) do
		local row = legend.rows[i]
		local color = e[2]
		row.icon:SetTexture(icon)
		row.icon:SetWidth(iconSize); row.icon:SetHeight(iconSize)
		if db.icons then row.icon:Show() else row.icon:Hide() end
		row.number:SetFont(ns.FontPath(), math.min(FONT_MAX, SIZE * e[4]), color.thick and "THICKOUTLINE" or "OUTLINE")
		row.number:SetTextColor(color[1], color[2], color[3])
		row.number:SetText(e[3])
		row.name:SetText(e[1])
	end
end

function ns.ToggleLegend()
	legend = legend or BuildLegend()
	if legend:IsShown() then
		legend:Hide()
	else
		PaintLegend()
		legend:Show()
	end
end

-- repaint an open legend after a setting changes
function ns.RefreshLegend()
	if legend and legend:IsShown() then PaintLegend() end
end
