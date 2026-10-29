local ADDON, ns = ...

-- Numbers for what you and your pet do and what is done to you, each with its spell icon. A number
-- floats (on the unit's nameplate or a fixed spot) in the chosen animation and fades, or goes into one
-- of the boxes (Boxes.lua) as a line.

local FADE_AT = 0.65      -- share of a number's time before its fade starts
local SIZE = 20           -- a normal hit's font size at scale 1, and every icon's size
ns.SIZE = SIZE
local RISE = 60          -- how far a floating number travels
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
	crit = { 1, 0.4, 0, thick = true },
	miss = { 0.9, 0.9, 0.9 },
	heal = { 0.4, 0.88, 0.45 },
	healCrit = { 0.25, 1, 0.72, thick = true },
	overheal = { 0.45, 0.62, 0.45 },
	shield = { 0.55, 0.82, 1 },
	buff = { 1, 0.9, 0.55 },
	taken = { 0.88, 0.32, 0.27 },
	takenCrit = { 1, 0.22, 0.45, thick = true },
	-- mana, rage, energy and runic power you gain, by the game's power type number
	power = {
		[0] = { 0.4, 0.62, 1 },
		[1] = { 1, 0.35, 0.3 },
		[3] = { 1, 0.9, 0.35 },
		[6] = { 0.35, 0.85, 1 },
	},
}
ns.COLOR = COLOR

-- The fonts big crits have images for (CritGlyphs.lua), so every number in a font matches its
-- crits, keyed "lsm:<name>": the ones SharedMedia has loaded. Without SharedMedia, the game's four
-- (crits then drawn in Blender Pro). Read when the settings window is built, after they loaded.
function ns.FontList()
	local list = {}
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM then
		for _, name in ipairs(LSM:List("font")) do
			if ns.CRIT_GLYPHS[name] then list[#list + 1] = { "lsm:" .. name, name } end
		end
	end
	if #list == 0 then
		for _, f in ipairs(ns.FONTS) do list[#list + 1] = { f[1], f[2] } end
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

-- The spell, talent or glyph a number belongs to, whose Spells-page ticks rule it: itself when it's one
-- you have (a spell you can cast: the game only finds those by name; a talent with points; a glyph in
-- a socket), else the first of its causes in Effects-Data you have (Blood Corruption -> Seal of
-- Corruption, Replenishment -> Judgements of the Wise). nil = none of yours: an item's or a buff's.
local owners, talents, glyphs = {}, nil, nil

-- the talents with points in the spec you're in, and the glyphs in its sockets, by name
local function Mine()
	if not talents then
		talents = {}
		for tab = 1, GetNumTalentTabs() do
			for i = 1, GetNumTalents(tab) do
				local name, _, _, _, rank = GetTalentInfo(tab, i)
				if name and (rank or 0) > 0 then talents[name] = true end
			end
		end
		glyphs = {}
		for i = 1, GetNumGlyphSockets() do
			local enabled, _, spell = GetGlyphSocketInfo(i)
			local name = enabled and spell and GetSpellInfo(spell)
			if name then glyphs[name] = true end
		end
	end
	return talents, glyphs
end

function ns.Have(name)
	local t, g = Mine()
	return t[name] and "talent" or GetSpellTexture(name) and "spell" or g[name] and "glyph" or nil
end

local function FindOwner(name)
	if ns.Have(name) then return name end
	local _, class = UnitClass("player")
	local causes = RatBitesEffects and RatBitesEffects[class] and RatBitesEffects[class][name]
	for _, cause in ipairs(causes or {}) do
		if ns.Have(cause) then return cause end
	end
end

function ns.SpellOwner(name)
	if owners[name] == nil then owners[name] = FindOwner(name) or false end
	return owners[name] or nil
end

-- a spell learned, a talent point, a glyph or the other spec: look again
local function Forget() wipe(owners); talents, glyphs = nil, nil end
for _, event in ipairs({ "SPELLS_CHANGED", "CHARACTER_POINTS_CHANGED", "GLYPH_ADDED", "GLYPH_REMOVED",
	"GLYPH_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
	ns.On(event, Forget)
end

-- a tooltip's whole text in lower case, read off a hidden tooltip
local scan
local function TipText(setter, ...)
	scan = scan or CreateFrame("GameTooltip", "RatBitesScanTip", UIParent, "GameTooltipTemplate")
	scan:SetOwner(UIParent, "ANCHOR_NONE")
	scan[setter](scan, ...)
	local parts = {}
	for i = 1, scan:NumLines() do
		local line = _G["RatBitesScanTipTextLeft" .. i]
		local text = line and line:GetText()
		if text then parts[#parts + 1] = text end
	end
	scan:Hide()
	return table.concat(parts, "\n"):lower()
end

-- a number made by something you're wearing: an item or its enchant whose tooltip names it, or the
-- item's own spell (a trinket's Use, a weapon's proc). A raid or boss buff is none of these.
function ns.FromGear(name)
	local low = name:lower()
	for slot = 1, 18 do
		local link = GetInventoryItemLink("player", slot)
		if link and (GetItemSpell(link) == name or TipText("SetInventoryItem", "player", slot):find(low, 1, true)) then
			return true
		end
	end
end

-- A spell in your spellbook shows its spellbook icon, as on the Spells page: a strike made of hidden
-- hits (Mutilate's two hand hits) has the plain dual-wield icon on its own ids.
local icons = {}
local function SpellIcon(id)
	if not id then return nil end
	if icons[id] == nil then
		local name, _, icon = GetSpellInfo(ICON_FROM[id] or id)
		local book = name and GetSpellTexture(name)
		if book and book ~= "" then icon = book end
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

--------------------------------------------------------------------------------
-- the floating texts
--------------------------------------------------------------------------------

local root = CreateFrame("Frame", nil, UIParent)
root:SetAllPoints(UIParent)
root:SetFrameStrata("LOW")

local pool, active, queued = {}, {}, {}
local arc = 1

-- how far a number drifts sideways while it rises: at least [1], plus up to [2] more at random
local DRIFT, DRIFT_MORE = 15, 15  -- an arc's sideways drift: at least DRIFT, up to DRIFT_MORE further

-- Numbers that land on the same spot together (a heal and its proc, a multi-hit) would start on top
-- of each other, so each one within STACK_TIME of the last starts a line higher, up to STACK_MAX.
local STACK_TIME, STACK_MAX = 0.5, 6  -- 6: Holy Light and its glyph's five splashes
local stacks = {}  -- plate or spot -> { at = time of the last number, n = its line }

local function StackLine(key, size)
	local now = GetTime()
	local s = stacks[key]
	if s and now - s.at < STACK_TIME then
		s.n = (s.n + 1) % STACK_MAX
	elseif s then
		s.n = 0
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
-- The client turns down a font size that is too big (the text then keeps its old, small font) and
-- won't draw text bigger by scaling its frame either, so a number bigger than the biggest size it
-- takes (a big crit) gets that size and is stretched the rest with SetTextHeight, as Blizzard's own
-- combat text grows its crits. That biggest size depends on the font and the client, so it is
-- tried out once per font: the bigger it is, the less a crit is stretched and the sharper it stays.
-- A popping crit lands like a bomb: it appears BOMB times bigger and shrinks smoothly back over
-- BOMB_TIME, sized by hand for that moment, and only then does its path start.
local START_GAP = 12  -- how far above the plate a number starts
local FONT_MAX = 32   -- a size every client takes
local FONT_TRY = 200  -- the biggest size tried

local fontMax = {}  -- font path -> the biggest size the client takes for it
local function FontMax(path)
	if fontMax[path] then return fontMax[path] end
	local probe = root.probe
	if not probe then
		probe = root:CreateFontString(nil, "OVERLAY")
		probe:Hide()
		root.probe = probe
	end
	-- a size the client turns down leaves the font string on its old size
	local function Takes(size)
		probe:SetFont(path, FONT_MAX, "OUTLINE")
		probe:SetFont(path, size, "OUTLINE")
		local _, got = probe:GetFont()
		return got and math.abs(got - size) < 1
	end
	local low, high = FONT_MAX, FONT_TRY
	if Takes(high) then
		low = high
	else
		while high - low > 1 do
			local mid = math.floor((low + high) / 2)
			if Takes(mid) then low = mid else high = mid end
		end
	end
	fontMax[path] = low
	return low
end

-- /bites font: the biggest size the client takes for the font in use, and a crit's size now
function ns.ReportFont()
	local db = ns.db
	local crit = SIZE * db.critSize * db.scale
	print(format("|cffffd200RatBites|r font takes up to %d, a crit wants %d (stretched %.1fx)",
		FontMax(ns.FontPath()), crit, math.max(1, crit / FontMax(ns.FontPath()))))
end
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
	t.glyphs = {}
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
	t.fade:SetOrder(1)
	return t
end

local function Leg(a, x, y, duration, smoothing, delay)
	a:SetOffset(x, y)
	a:SetDuration(math.max(0.01, duration))
	a:SetSmoothing(smoothing)
	a:SetStartDelay(delay or 0)
end

-- The number's font at its size: drawn at that size when the client takes it (sharp), stretched
-- past the biggest size it takes. The thick outline is for normal-sized crits only: on a big number
-- it is a heavy black edge, so a crit past THICK_MAX takes the thin one.
local THICK_MAX = 32
local SHARP_MAX = 32  -- the biggest text the client draws sharp; past it, text is enlarged
local function SetSize(t)
	t.text:SetFont(ns.FontPath(), t.fontPx, t.thick and t.want <= THICK_MAX and "THICKOUTLINE" or "OUTLINE")
	if t.want > t.fontPx then t.text:SetTextHeight(t.want) end
end

-- Big crits are drawn as images: each character is a piece of
-- Media\Crit\<font>.blp, drawn large with its black outline, white tinted to the crit's colour, so
-- it is sharp at any size. Made for every font in the Font list; a font without them uses Blender Pro's.
local CRIT_TRACK = 4  -- extra room between characters, in pixels of the drawn cell
local function CritImages()
	local name = ns.db.font:match("^lsm:(.+)")
	return name and ns.CRIT_GLYPHS[name] and name or "Blender Pro"
end

-- A font's images, unpacked from its string the first time a crit needs them: file, size and a
-- table per character. Only the font in use is kept unpacked.
local unpacked, unpackedName
local function CritSet(name)
	if unpackedName == name then return unpacked end
	local packed = ns.CRIT_GLYPHS[name]
	if not packed then return nil end
	local file, size, chars = packed:match("^([^|]+)|(%d+)|(.*)$")
	local set = { file = file, size = tonumber(size) }
	for entry in chars:gmatch("[^;]+") do
		local g = {}
		for v in entry:sub(3):gmatch("%S+") do g[#g + 1] = tonumber(v) end
		set[entry:sub(1, 1)] = g
	end
	unpacked, unpackedName = set, name
	return set
end

-- The characters are textures of the number's own frame, like its icon: an animation moves and
-- fades a frame's own textures, not frames inside it.

-- the characters laid out at size want (the pop redraws them as it shrinks): the icon and number
-- centred together on the frame, or by the Align setting starting just after the icon's column
-- (left) or ending at the same spot (right)
local function PlaceDigits(t, want)
	local set, k = t.glyphSet, want / t.glyphSet.size
	local cell, pen = ns.CRIT_CELL * k, 0
	-- the whole number's width first, so it can be centred
	local n = #t.glyphLabel
	for i = 1, n - 1 do pen = pen + set[t.glyphLabel:sub(i, i)][7] + CRIT_TRACK end
	local last = set[t.glyphLabel:sub(n, n)]
	local first = set[t.glyphLabel:sub(1, 1)]
	local left = first[6] * k
	local width = (pen + last[6] + last[5]) * k - left
	local x0
	if t.align == "left" then
		x0 = -t.alignAt + (t.icon:IsShown() and t.icon:GetWidth() + 4 or 0)
	elseif t.align == "right" then
		x0 = t.alignAt - width
	else
		x0 = -width / 2 + (t.icon:IsShown() and (t.icon:GetWidth() + 4) / 2 or 0)
	end
	pen = 0
	for i = 1, n do
		local g = set[t.glyphLabel:sub(i, i)]
		local tex = t.glyphs[i]
		tex:SetWidth(g[5] * k); tex:SetHeight(cell)
		tex:ClearAllPoints()
		tex:SetPoint("LEFT", t, "CENTER", (pen + g[6]) * k - left + x0, 0)
		pen = pen + g[7] + CRIT_TRACK
	end
end

-- the label as images at size want; false when it has a character there is no image of
local function DrawDigits(t, label, want, color)
	local set = CritSet(CritImages())
	if not set then return false end
	label = label:lower()
	for i = 1, #label do
		if not set[label:sub(i, i)] then return false end
	end
	t.glyphSet, t.glyphLabel = set, label
	for i = 1, #label do
		local g = set[label:sub(i, i)]
		local tex = t.glyphs[i]
		if not tex then
			tex = t:CreateTexture(nil, "OVERLAY")
			t.glyphs[i] = tex
		end
		tex:SetTexture([[Interface\AddOns\RatBites\Media\Crit\]] .. set.file)
		tex:SetTexCoord(g[1], g[2], g[3], g[4])
		tex:SetVertexColor(color[1], color[2], color[3])
		tex:Show()
	end
	for i = #label + 1, #t.glyphs do t.glyphs[i]:Hide() end
	PlaceDigits(t, want)
	return true
end

local function HideDigits(t)
	for i = 1, #t.glyphs do t.glyphs[i]:Hide() end
end

local function Bombing(group, elapsed)
	local t = group.owner
	t.bombed = t.bombed + elapsed
	local f = 1 - t.bombed / BOMB_TIME
	if f <= 0 then
		-- landed: drawn again at its own size, so it is sharp rather than resampled
		if t.useDigits then PlaceDigits(t, t.want) else SetSize(t) end
		group:SetScript("OnUpdate", nil)
		return
	end
	local grow = 1 + (BOMB - 1) * f * f
	if t.useDigits then PlaceDigits(t, t.want * grow) else t.text:SetTextHeight(t.want * grow) end
end

-- Sets the number's path (h is the Height setting, dx its sideways drift), after a popping crit's
-- bomb:
--   arc: drifts sideways while the rise eases out   rise: straight up   stay: holds, only fades
local function Plan(t, pop)
	local d, h, dx = t.duration, t.rise, t.dx
	local wait = pop and BOMB_TIME or 0
	local fadeAt, fadeLen = d * FADE_AT, d * (1 - FADE_AT)
	local x, y = dx, h
	if t.anim == "rise" then x = 0 end
	if t.anim == "stay" then x, y = 0, 0 end
	Leg(t.x1, x, 0, d, "NONE", wait)
	Leg(t.y1, 0, y, d, "OUT", wait)
	Leg(t.x2, 0, 0, 0.01, "NONE")
	Leg(t.y2, 0, 0, 0.01, "NONE")
	t.fade:SetStartDelay(wait + fadeAt)
	t.fade:SetDuration(fadeLen)
end

-- plate: the nameplate the number starts over (nil: the spot x, y in UIParent units); column: a
-- fixed spot's straight column (no sideways drift); anim: how it moves, the Motion setting for heals
-- or for damage
local function Show(plate, name, x, y, label, color, size, icon, pop, column, anim)
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
	-- the size it should show at (Text size included): its font as big as the client takes it,
	-- stretched the rest
	-- a crit bigger than the client draws text sharp is drawn from character images instead, sharp
	-- at any size; text only when it has a character there is no image of
	local want = size * db.scale
	local fontPx = math.min(FontMax(ns.FontPath()), math.floor(want + 0.5))
	t.want, t.fontPx, t.thick = want, fontPx, color.thick
	-- a new font string takes no text before it has a font
	SetSize(t)
	t.text:SetText(label)
	t.text:SetTextColor(color[1], color[2], color[3])
	t.useDigits = color.thick and want > SHARP_MAX and DrawDigits(t, label, want, color)
	-- Align: centre puts the number on the spot; left starts every icon at the same spot left of it,
	-- so the icons of a stack stand in one column and the numbers start after them; right ends every
	-- number at the same spot right of it. (A joined shield may have moved the text beside a crit's
	-- images: it is placed again here.)
	local iconOn = icon and db.icons
	local at = SIZE * db.scale
	t.align, t.alignAt = db.align, at
	t.text:ClearAllPoints()
	t.icon:ClearAllPoints()
	if t.useDigits then
		t.text:Hide()
		t.text:SetPoint("CENTER")
		if t.align == "left" then
			t.icon:SetPoint("LEFT", t, "CENTER", -at, 0)
		else
			t.icon:SetPoint("RIGHT", t.glyphs[1], "LEFT", -4, 0)
		end
	else
		HideDigits(t)
		t.text:Show()
		if t.align == "left" then
			if iconOn then
				t.icon:SetPoint("LEFT", t, "CENTER", -at, 0)
				t.text:SetPoint("LEFT", t.icon, "RIGHT", 4, 0)
			else
				t.text:SetPoint("LEFT", t, "CENTER", -at, 0)
			end
		else
			if t.align == "right" then
				t.text:SetPoint("RIGHT", t, "CENTER", at, 0)
			else
				t.text:SetPoint("CENTER")
			end
			t.icon:SetPoint("RIGHT", t.text, "LEFT", -4, 0)
		end
	end
	-- an icon has a normal hit's size; a crit's grows with its number, to half its height
	local iconSize = SIZE * db.scale
	if color.thick then iconSize = math.max(iconSize, want * 0.5) end
	t.icon:SetWidth(iconSize); t.icon:SetHeight(iconSize)
	if icon and db.icons then
		t.icon:SetTexture(icon)
		t.icon:Show(); t.edge:Show()
	else
		t.icon:Hide(); t.edge:Hide()
	end
	if t.useDigits then PlaceDigits(t, want) end
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
	t.anim = anim or db.animation
	t.rise, t.duration = RISE, db.duration
	-- lines stack a normal hit's height apart: a crit's own size would push it lines and lines up
	t.line = StackLine(plate or format("%d:%d", x, y), color.thick and SIZE or size)
	if column then
		t.dx = 0
	else
		arc = -arc
		t.dx = arc * (DRIFT + math.random() * DRIFT_MORE)
	end
	local startY = t.y + (column and 0 or START_GAP) + t.line * db.scale
	-- a crit starts a normal line above the rest, so at its size it doesn't cover hits landing with it
	if color.thick then startY = startY + (SIZE + 6) * db.scale end
	t:ClearAllPoints()
	t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", math.floor(t.x + 0.5), math.floor(startY + 0.5))
	if pop then
		t.bombed = 0
		-- the bomb is drawn at its biggest size and shrunk: shrinking keeps text sharp, growing blurs it
		local big = want * BOMB
		if t.useDigits then
			PlaceDigits(t, big)
		else
			t.text:SetFont(ns.FontPath(), math.min(FontMax(ns.FontPath()), math.floor(big + 0.5)), "OUTLINE")
			t.text:SetTextHeight(big)
		end
		t.group:SetScript("OnUpdate", Bombing)
	else
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
-- what puts a spell on the Spells page: your damage, heals and shields, and the mana, energy or rage
-- your talents give you (Focused Attacks, Relentless Strikes), so each can be shown or hidden
local SEEN_KINDS = { swing = true, spell = true, dot = true, heal = true, overheal = true, shield = true, power = true }
local lastHeal = {}  -- GUID -> { amount, crit, at } of your last heal on them
-- only the heals of the fight matter: a raid night would otherwise keep one for everyone you healed
ns.On("PLAYER_REGEN_ENABLED", function() wipe(lastHeal) end)

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
	elseif event == "SPELL_ENERGIZE" or event == "SPELL_PERIODIC_ENERGIZE" then
		-- mana, rage, energy or runic power gained; the power type rides where a miss's word does
		local id, _, _, amount, powerType = ...
		return "power", amount, nil, SpellIcon(id), powerType
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
			if kind == "heal" then
				color = COLOR.healCrit
			elseif kind ~= "overheal" then
				color = COLOR.crit
			end
			-- damage crits grow and pop; a heal crit keeps a heal's size, standing out by its colour
			if kind ~= "heal" and kind ~= "overheal" then
				if db.critStyle == "big" then size = size * db.critSize end
				if db.critStyle == "pop" then size, pop = size * db.critSize, true end
			end
		end
	end
	if who == "pet" then size = size * 0.8 end
	return label, color, size, pop
end

--------------------------------------------------------------------------------
-- where a number goes: the Where grids. Your damage and heals on others (rows dmg, heal) tick any of
-- plate (over the unit's nameplate), me (over your character) and mine (Output box); heals and damage
-- landing on you (healMe, dmgMe) tick me and recv (Input box). Nothing ticked hides that kind.
--------------------------------------------------------------------------------

-- a colour drawn the way crits are (thick outline, sharp digit images when big), one per colour
local thickOf = {}
local function Thick(color)
	if color.thick then return color end
	thickOf[color] = thickOf[color] or { color[1], color[2], color[3], thick = true }
	return thickOf[color]
end

local POP_HIT = 0.6  -- in a Pop box, a hit that isn't a crit against a crit's size

-- one number into a box: as a line of its list (Scroll), or floating up out of the box's bottom
-- edge with that box's animation, crits popping full size as on plates. Pop: every hit lands like
-- a crit and rises, crits still the biggest.
local function ToBox(key, label, color, size, icon, pop, amount, sign)
	local style = ns.db.boxes[key].style
	if style == "scroll" then
		ns.BoxAdd(key, label, color, size, icon, amount, sign)
		return
	end
	if style == "pop" and amount then
		if not color.thick then size = math.max(size, SIZE * ns.db.critSize * POP_HIT) end
		color, pop, style = Thick(color), true, "rise"
	end
	local x, y = ns.BoxSpot(key)
	local scaled = size * ns.db.boxes[key].scale
	if x then Show(nil, nil, x, y, label, color, scaled, icon, pop, style ~= "arc", style) end
end

-- the Spells page's two ticks for the spell being shown, set for each combat-log line: skipFloat keeps
-- it off plates and over you, skipBox out of the boxes
local skipFloat, skipBox = false, false

-- true when the number showed somewhere (the crit sound only plays for one you can see)
local function Route(row, plate, name, label, color, size, icon, pop, amount, sign)
	local db = ns.db
	local r = db.route[row]
	local anim = (row == "heal" or row == "healMe" or row == "powerMe") and db.healAnimation or db.animation
	local shown = false
	if r.plate and plate and not skipFloat then
		Show(plate, name, 0, 0, label, color, size, icon, pop, false, anim)
		shown = true
	elseif r.plate and not skipFloat and not skipBox and not r.mine and db.noPlateToBox then
		-- wanted over a nameplate that isn't on screen (pets, totems, far away): My box instead
		ToBox("mine", label, color, size, icon, pop, amount, sign)
		shown = true
	end
	if r.me and not skipFloat then
		local x, y = MeSpot()
		Show(nil, nil, x, y, label, color, size, icon, pop, true, anim)
		shown = true
	end
	if skipBox then return shown end
	if r.mine then ToBox("mine", label, color, size, icon, pop, amount, sign); shown = true end
	if r.recv then ToBox("received", label, color, size, icon, pop, amount, sign); shown = true end
	return shown
end

local function Ticked(r) return r.plate or r.me or r.mine or r.recv end

-- the What filters: kinds of hits, misses, pets, overheal and shields can each be turned off
local function Wanted(who, kind, amount, crit)
	local show = ns.db.show
	if kind == "overheal" then return show.overheal end
	if kind == "shield" then return show.shield end
	if kind == "heal" or kind == "buff" then return true end
	local hits = show.hits[who == "pet" and "pet" or kind]
	if kind == "miss" then
		return show.miss and (who ~= "pet" or hits.normal or hits.crit) or false
	end
	return hits and hits[crit and "crit" or "normal"] or false
end

-- the spell of the combat-log line being handled ("melee" for swings): a crit sound plays once per
-- spell, however many targets it crits
local critSpell

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
	-- the sound only for a crit you can see (past Which hits and the Where ticks) of a spell with
	-- both its Spells page ticks on: a spell kept off plates or out of the boxes stays quiet
	if Route(row, plate, name, label, color, size, icon, pop, amount, heal and "+" or "")
		and who == "player" and crit and amount and not skipFloat and not skipBox then
		ns.CritSound(kind, critSpell)
	end
end

local function Received(kind, amount, crit, icon, word, who)
	if kind == "miss" then return end
	if (kind == "overheal" or kind == "shield") and not Wanted("player", kind) then return end
	local heal = HEALING[kind]
	local row = kind == "power" and "powerMe" or heal and "healMe" or "dmgMe"
	if not Ticked(ns.db.route[row]) then return end
	local label, color
	if kind == "power" then
		if not amount or amount <= 0 then return end
		Route(row, nil, nil, "+" .. Abbrev(amount), COLOR.power[word] or COLOR.power[0], SIZE * 0.9, icon, false,
			amount, "+")
		return
	elseif kind == "shield" then
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
	-- a crit heal on you keeps a heal's size; a crit hit on you is bigger and pops
	local big = crit and not heal
	local size = big and SIZE * 1.2 or SIZE * 0.9
	-- your own heal crit on you, when it showed and its spell has both Spells page ticks on
	if Route(row, nil, nil, label, color, size, icon, big and ns.db.critStyle == "pop", amount, heal and "+" or "-")
		and who == "player" and crit and heal and not skipFloat and not skipBox then
		ns.CritSound(kind, critSpell)
	end
end

-- /bites last: the last combat-log lines RatBites read (yours, or landing on you), what it made of
-- each and where it went, to find out why a number didn't show. A raid sends hundreds of lines a
-- second, so each is kept as its plain values in a ring of reused tables and only turned into text
-- when /bites last asks.
local trace, TRACE_MAX, traceAt = {}, 12, 0

local function Trace(event, destGUID, destName, kind, amount, id, spellName)
	traceAt = traceAt % TRACE_MAX + 1
	local e = trace[traceAt]
	if not e then
		e = {}
		trace[traceAt] = e
	end
	e.time, e.event, e.onMe, e.dest, e.kind, e.amount = time(), event, destGUID == ns.playerGUID, destName, kind, amount
	e.spell = type(spellName) == "string" and spellName or "melee"
end

local function TraceLine(e)
	local row = e.kind and (e.onMe and (e.kind == "power" and "powerMe" or HEALING[e.kind] and "healMe" or "dmgMe")
		or (HEALING[e.kind] and "heal" or "dmg"))
	local r = row and ns.db.route[row]
	local places = {}
	if r then
		for _, key in ipairs({ "plate", "me", "mine", "recv" }) do
			if r[key] then places[#places + 1] = key end
		end
	end
	-- a setting that stops it before it gets anywhere
	local show = ns.db.show
	local stop = (e.kind == "overheal" and not show.overheal and "Overheal is unticked")
		or (e.kind == "shield" and not show.shield and "Shields are off")
		or (ns.db.noPlates[ns.SpellOwner(e.spell) or e.spell] and ns.db.noBoxes[ns.SpellOwner(e.spell) or e.spell]
			and "unticked in Spells")
	return format("%s %s -> %s: %s %s%s", date("%H:%M:%S", e.time), e.event, e.onMe and "you" or tostring(e.dest),
		e.spell, e.kind and (e.kind .. " " .. tostring(e.amount or "")) or "not shown",
		stop and (" [hidden: " .. stop .. "]")
		or r and (" [" .. (#places > 0 and table.concat(places, " ") or "nowhere") .. "]") or "")
end

function ns.PrintTrace()
	if #trace == 0 then ns.Print("nothing read yet") return end
	-- oldest first: the ring starts after the latest one
	for i = 1, #trace do
		ns.Print(TraceLine(trace[(traceAt + i - 1) % #trace + 1]))
	end
end

ns.On("COMBAT_LOG_EVENT_UNFILTERED", function(_, event, sourceGUID, _, sourceFlags, destGUID, destName, _, ...)
	local db = ns.db
	if not db or not ns.app.enabled or not ns.playerGUID then return end
	local who = Who(sourceGUID, sourceFlags)
	skipFloat, skipBox = false, false
	local toMe = destGUID == ns.playerGUID
	if not who and not toMe then return end
	if who and (event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL") then
		local _, _, _, healed, _, _, healCrit = ...
		local h = lastHeal[destGUID] or {}
		h.amount, h.crit, h.at = healed, healCrit, GetTime()
		lastHeal[destGUID] = h
	end
	local kind, amount, crit, icon, miss = Read(event, ...)
	Trace(event, destGUID, destName, kind, amount, ...)
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
	-- a spell unticked in the Spells tab doesn't show (by name, so all its ranks are one); swings go
	-- by the game's word for melee
	if who then
		local spell = event:find("^SWING") and MELEE or select(2, ...)
		skipFloat, skipBox = false, false
		if type(spell) == "string" then
			local key = ns.SpellOwner(spell) or spell
			skipFloat, skipBox = db.noPlates[key] or false, db.noBoxes[key] or false
			if skipFloat and skipBox then return end
		end
		-- every spell of yours or your pet's that makes a number is kept, so procs and effects outside
		-- the spellbook (Judgement heals, glyph splashes, Beacon copies) can be unticked too
		local new
		if amount and SEEN_KINDS[kind] and type(spell) == "string" and not ns.char.seen[spell] then
			ns.char.seen[spell] = icon or true
			new = true
		end
		-- its spell id, for the game's own tooltip on the Spells page, and what kind of number it makes
		local id = not event:find("^SWING") and (...)
		if ns.char.seen[spell] and type(id) == "number" then
			ns.char.ids = ns.char.ids or {}
			ns.char.ids[spell] = id
		end
		-- the spec it was seen in, so the Spells page lists only the spec you're in
		if ns.char.seen[spell] then
			ns.char.specs = ns.char.specs or {}
			local specs = ns.char.specs[spell] or {}
			specs[GetActiveTalentGroup() or 1] = true
			ns.char.specs[spell] = specs
		end
		if ns.char.seen[spell] and kind ~= "overheal" then
			ns.char.kinds = ns.char.kinds or {}
			ns.char.kinds[spell] = kind == "power" and "power" .. (miss or 0) or kind
		end
		if kind == "power" and type(spell) == "string" then
			ns.char.resources = ns.char.resources or {}
			new = new or not ns.char.resources[spell]
			ns.char.resources[spell] = true
		end
		-- an open settings window lists it at once
		if new and RatBitesOptions and RatBitesOptions:IsShown() then ns.RefreshOptions() end
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
	critSpell = event:find("^SWING") and "melee" or select(2, ...)
	ns.lastShown = nil
	-- output is what you do to others; receiving is everything that lands on you, your own
	-- self-heals and shields included
	if toMe then
		Received(kind, amount, crit, icon, miss, who)
	else
		Outgoing(who, destGUID, destName, kind, amount, crit, icon, miss)
	end
	-- remember where your heal's number went, for the shield that follows it
	if who and (kind == "heal" or kind == "overheal") and lastHeal[destGUID] then
		local el = ns.lastShown
		lastHeal[destGUID].el, lastHeal[destGUID].serial = el, el and el.serial
	end
end)

-- a class's colour for numbers: a dark one (Death Knight red, Shaman blue) is lifted toward white
-- until it reads on a dark fight, keeping its hue
function ns.ClassColor(class)
	local c = RAID_CLASS_COLORS[class]
	if not c then return nil end
	local r, g, b = c.r, c.g, c.b
	local light = 0.3 * r + 0.59 * g + 0.11 * b
	if light < 0.55 then
		local lift = (0.55 - light) / (1 - light)
		r, g, b = r + (1 - r) * lift, g + (1 - g) * lift, b + (1 - b) * lift
	end
	return { r, g, b }
end

ns.On("PLAYER_LOGIN", function()
	ns.classColor = ns.ClassColor(select(2, UnitClass("player")))
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
	local critSize = SIZE * db.critSize
	-- "Test as" (ns.preview): that class's colour on the normal hit and its role's crit sound;
	-- else you as you are now
	local pv = ns.preview
	local normal = pv and ns.ClassColor(pv.class) or db.classColorFor == "normal" and ns.classColor or COLOR.normal
	local role = pv and pv.role or ns.CritRole("spell")
	local crit = role == "heal" and { "+" .. Abbrev(4120), COLOR.healCrit, SIZE, false, "heal", role }
		or { Abbrev(12431), COLOR.crit, critSize, db.critStyle == "pop", "dmg", role }
	-- label, colour, size, pop, Where row, crit sound role
	local hits = {
		{ "1234", normal, SIZE, false, "dmg" },
		crit,
		{ DODGE, COLOR.miss, SIZE * 0.8, false, "dmg" },
		{ "+" .. Abbrev(812), COLOR.heal, SIZE, false, "heal" },
		{ "Shield", COLOR.shield, SIZE * 0.85, false, "heal" },
		{ "-" .. Abbrev(640), COLOR.taken, SIZE * 0.9, false, "dmgMe" },
		{ "+" .. Abbrev(1923), COLOR.heal, SIZE * 0.9, false, "healMe" },
	}
	for i, h in ipairs(hits) do
		table.insert(queued, { at = GetTime() + (i - 1) * 0.25, fn = function()
			if h[6] then ns.PlayRole(h[6]) end
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
	local critSize = db.critSize
	local normal = db.classColorFor == "normal" and ns.classColor or COLOR.normal
	local crit, healCrit = COLOR.crit, COLOR.healCrit
	return {
		{ "Normal hit", normal, "1234", 1 },
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
		{ "Mana gained", COLOR.power[0], "+1.2k", 0.9 },
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
	for i, e in ipairs(LegendEntries()) do
		local row = legend.rows[i]
		local color = e[2]
		row.icon:SetTexture(icon)
		row.icon:SetWidth(SIZE); row.icon:SetHeight(SIZE)
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
