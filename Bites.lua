local ADDON, ns = ...

-- Floating numbers for what you and your pet do: damage on the enemy's nameplate, heals on the
-- friend's, each with its spell icon. Every number rises in a short arc and fades. What others do to
-- you (Incoming) rises straight up from a fixed spot left of the screen's centre.

local DURATION = 1.45
local FADE_AT = 0.65      -- share of DURATION before the fade starts
local POP_TIME = 0.15     -- a popping crit shrinks to its size over this long
local SIZE = 20           -- a normal hit's font size at scale 1
local MAX_TEXTS = 40
local ATTACK_ICON = [[Interface\Icons\INV_Sword_04]]

ns.FONTS = {
	{ "friz", "Friz Quadrata", STANDARD_TEXT_FONT },
	{ "arial", "Arial Narrow", [[Fonts\ARIALN.TTF]] },
	{ "morpheus", "Morpheus", [[Fonts\MORPHEUS.TTF]] },
	{ "skurri", "Skurri", [[Fonts\SKURRI.TTF]] },
}

local COLOR = {
	normal = { 0.72, 0.72, 0.72 },
	big = { 1, 0.82, 0 },
	crit = { 1, 0.45, 0.10 },
	miss = { 0.9, 0.9, 0.9 },
	heal = { 0.25, 1, 0.35 },
	overheal = { 0.45, 0.62, 0.45 },
	shield = { 0.55, 0.82, 1 },
	taken = { 1, 0.22, 0.18 },
}

local function FontPath()
	for _, f in ipairs(ns.FONTS) do
		if f[1] == ns.db.font then return f[3] end
	end
	return STANDARD_TEXT_FONT
end

local icons = {}
local function SpellIcon(id)
	if not id then return nil end
	if icons[id] == nil then icons[id] = select(3, GetSpellInfo(id)) or false end
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
	return t
end

local function Release(i)
	local t = table.remove(active, i)
	t:Hide()
	t.anchor = nil
	table.insert(pool, t)
end

-- the text still has what it rides: the plate shows the same name, the unit frame the same player
local function Holds(t)
	if t.onPlate then return ns.PlateShows(t.anchor, t.ident) end
	return ns.FrameShows(t.anchor, t.ident)
end

-- Offsets are in the text's own units, so a spot in UIParent units is divided by the text's scale.
-- On a plate or unit frame the spot is kept up to date, so one that goes away mid-flight leaves the
-- text where it was. Numbers start above a plate and on a unit frame's centre.
local function Move(t, elapsed)
	local p = elapsed / DURATION
	local scale = ns.db.scale
	if t.pop and elapsed < POP_TIME then scale = scale * (1 + 0.5 * (1 - elapsed / POP_TIME)) end
	t:SetScale(scale)
	local dx = t.dx * p
	local dy = (t.straight and 0 or 20) + t.line + t.rise * p - 20 * p * p
	t:ClearAllPoints()
	if t.anchor and Holds(t) then
		t:SetPoint("CENTER", t.anchor, t.onPlate and "TOP" or "CENTER", dx, dy)
		local x, y = t.anchor:GetCenter()
		if t.onPlate then y = t.anchor:GetTop() end
		if x and y then
			local s = t.anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
			t.x, t.y = x * s, y * s
		end
	else
		t.anchor = nil
		t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", t.x / scale + dx, t.y / scale + dy)
	end
	t:SetAlpha(p > FADE_AT and 1 - (p - FADE_AT) / (1 - FADE_AT) or 1)
end

-- where: { plate = f, name = n } or { frame = f, guid = g } to ride, or nil for the spot x, y in
-- UIParent units; straight: rise without the arc; rise: how far it climbs (default 70)
local function Show(where, x, y, label, color, size, icon, pop, straight, rise)
	if #active >= MAX_TEXTS then Release(1) end
	local t = Acquire()
	t.text:SetFont(FontPath(), size, "OUTLINE")
	t.text:SetText(label)
	t.text:SetTextColor(color[1], color[2], color[3])
	if icon and ns.db.icons then
		t.icon:SetTexture(icon)
		t.icon:SetWidth(size); t.icon:SetHeight(size)
		t.icon:Show(); t.edge:Show()
	else
		t.icon:Hide(); t.edge:Hide()
	end
	t.anchor, t.onPlate, t.ident = nil, nil, nil
	if where then
		t.anchor = where.plate or where.frame
		t.onPlate = where.plate ~= nil
		t.ident = where.name or where.guid
	end
	t.x, t.y = x, y
	t.pop, t.straight, t.rise = pop, straight, rise or 70
	t.line = StackLine(t.anchor or format("%d:%d", x, y), size)
	if straight then
		t.dx = 0
	else
		arc = -arc
		local s = SPREAD[ns.db.spread] or SPREAD.normal
		t.dx = arc * (s[1] + math.random() * s[2])
	end
	t.start = GetTime()
	t:Show()
	table.insert(active, t)
	Move(t, 0)
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
	for i = #active, 1, -1 do
		local t = active[i]
		local elapsed = now - t.start
		if elapsed >= DURATION then Release(i) else Move(t, elapsed) end
	end
end)

-- where numbers go without a plate: above the screen's centre, your heals right of it and Incoming
-- left of it
local function ScreenSpot()
	return UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 + 140
end
local function HealSpot()
	return UIParent:GetWidth() / 2 + 160, UIParent:GetHeight() / 2 - 40
end
local function IncomingSpot()
	return UIParent:GetWidth() / 2 - 160, UIParent:GetHeight() / 2 - 40
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

-- Absorb shields you put on someone. The 3.3.5a combat log gives no absorb amount, so they show as a
-- word with the spell's icon, once when the shield goes on (Val'anyr refreshes it on every heal).
-- Matched by name, which covers every rank.
ns.SHIELDS = {}
for _, id in ipairs({ 17, 47753, 58597, 64413 }) do  -- Power Word: Shield, Divine Aegis, Sacred Shield, Val'anyr
	local name = GetSpellInfo(id)
	if name then ns.SHIELDS[name] = true end
end
local HEALING = { heal = true, overheal = true, shield = true }

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
	elseif event == "SPELL_AURA_APPLIED" then
		local id, spellName, _, auraType = ...
		if auraType == "BUFF" and ns.SHIELDS[spellName] then return "shield", nil, nil, SpellIcon(id) end
	elseif event == "SWING_MISSED" then
		local missType = ...
		return "miss", nil, nil, ATTACK_ICON, missType
	elseif event == "SPELL_MISSED" or event == "RANGE_MISSED" or event == "SPELL_PERIODIC_MISSED" then
		local id, _, _, missType = ...
		return "miss", nil, nil, SpellIcon(id), missType
	end
end

local function Outgoing(who, guid, name, kind, amount, crit, icon, miss)
	local db, show = ns.db, ns.db.show
	if who == "pet" and not show.pet then return end
	if not show[HEALING[kind] and "heal" or kind] then return end
	if amount then
		if amount <= 0 or not show[crit and "crit" or "normal"] then return end
	end
	local heal = HEALING[kind]
	local where, x, y, straight, rise
	if heal then
		-- heals go where healers look: the raid frame, the friend's plate, or their own column
		if db.healsOn == "frames" then
			local f = ns.FrameFor(guid)
			if f then where, rise, straight = { frame = f, guid = guid }, 28, true end
		elseif db.healsOn == "plates" then
			local plate = ns.PlateFor(guid, name)
			if plate then where = { plate = plate, name = name } end
		end
		if not where then
			x, y = HealSpot()
			straight = true
		end
	else
		local isTarget = UnitExists("target") and UnitGUID("target") == guid
		if db.anchor == "target" and not isTarget then return end
		if db.anchor ~= "screen" then
			local plate = ns.PlateFor(guid, name)
			ns.lastDest, ns.lastDestPlate = name, plate
			if plate then
				where = { plate = plate, name = name }
			elseif not isTarget then
				-- no plate to ride: only your target's numbers fall back to the screen
				return
			end
		end
		x, y = ScreenSpot()
	end
	x, y = x or 0, y or 0

	local label, color, size, pop = nil, COLOR.normal, SIZE, false
	if kind == "miss" then
		-- DODGE, PARRY, IMMUNE ... are the game's own words for each miss
		label, color, size = _G[miss] or miss, COLOR.miss, SIZE * 0.8
	elseif kind == "shield" then
		label, color, size = "Shield", COLOR.shield, SIZE * 0.85
	else
		label = Abbrev(amount)
		if kind == "heal" or kind == "overheal" then
			label, color = "+" .. label, kind == "heal" and COLOR.heal or COLOR.overheal
		elseif db.classColor and ns.classColor then
			color = ns.classColor
		end
		if kind == "dot" then size = SIZE * 0.8 end
		if crit then
			if kind ~= "heal" and kind ~= "overheal" then color = COLOR.crit end
			if db.critStyle == "big" then size = size * 1.5 end
			if db.critStyle == "pop" then size, pop = size * 1.3, true end
		elseif (kind == "swing" or kind == "spell") and db.bigGold and IsBig(amount) then
			color, size = COLOR.big, SIZE * 1.15
		end
	end
	if who == "pet" then size = size * 0.8 end
	-- a raid frame is small: its numbers too
	if where and where.frame then size = size * 0.65 end
	Show(where, x, y, label, color, size, icon, pop, straight, rise)
end

local function Incoming(kind, amount, crit, icon)
	local inc = ns.db.incoming
	if kind == "miss" or kind == "overheal" or kind == "shield" or not amount or amount <= 0 then return end
	if kind == "heal" then
		if not inc.heals then return end
	elseif not inc.damage then
		return
	end
	local x, y = IncomingSpot()
	local heal = kind == "heal"
	local size = crit and SIZE * 1.2 or SIZE * 0.9
	Show(nil, x, y, (heal and "+" or "-") .. Abbrev(amount), heal and COLOR.heal or COLOR.taken,
		size, icon, crit and ns.db.critStyle == "pop", true)
end

ns.On("COMBAT_LOG_EVENT_UNFILTERED", function(_, event, sourceGUID, _, sourceFlags, destGUID, destName, _, ...)
	local db = ns.db
	if not db or not db.enabled or not ns.playerGUID then return end
	local who = Who(sourceGUID, sourceFlags)
	local toMe = destGUID == ns.playerGUID
	if not who and not toMe then return end
	local kind, amount, crit, icon, miss = Read(event, ...)
	if not kind then return end
	-- your heals on yourself are your heals: they go on your own raid frame like anyone else's
	local ownHeal = who and HEALING[kind]
	if toMe and not ownHeal then
		Incoming(kind, amount, crit, icon)
	else
		Outgoing(who, destGUID, destName, kind, amount, crit, icon, miss)
	end
end)

ns.On("PLAYER_LOGIN", function()
	local c = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
	if c then ns.classColor = { c.r, c.g, c.b } end
end)

--------------------------------------------------------------------------------
-- /bites test: one of each kind on your target's plate, or above the screen's centre
--------------------------------------------------------------------------------

function ns.Test()
	local book = {}
	for i = 1, 40 do
		local tex = GetSpellTexture(i, BOOKTYPE_SPELL)
		if not tex then break end
		book[#book + 1] = tex
	end
	local function pick() return book[math.random(math.max(#book, 1))] or ATTACK_ICON end
	local guid, name = UnitGUID("target"), UnitName("target")
	local plate = guid and ns.PlateFor(guid, name)
	local where = plate and { plate = plate, name = name }
	local x, y = ScreenSpot()
	local db = ns.db
	local hits = {
		{ COLOR.normal, SIZE, "1234", false },
		{ COLOR.big, SIZE * 1.15, Abbrev(2331), false },
		{ COLOR.crit, SIZE * (db.critStyle == "big" and 1.5 or db.critStyle == "pop" and 1.3 or 1), Abbrev(12431), db.critStyle == "pop" },
		{ COLOR.miss, SIZE * 0.8, DODGE, false },
		{ COLOR.heal, SIZE, "+" .. Abbrev(812), false },
	}
	for i, h in ipairs(hits) do
		table.insert(queued, { at = GetTime() + (i - 1) * 0.25, fn = function()
			Show(where, x, y, h[3], h[1], h[2], pick(), h[4], false)
		end })
	end
	if db.incoming.damage or db.incoming.heals then
		local ix, iy = IncomingSpot()
		table.insert(queued, { at = GetTime() + 0.4, fn = function()
			Show(nil, ix, iy, "-" .. Abbrev(640), COLOR.taken, SIZE * 0.9, ATTACK_ICON, false, true)
		end })
	end
end
