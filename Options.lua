local ADDON, ns = ...

-- RatBites' settings window: two columns of one-line rows, the setting's name on the left and its
-- control on the right edge.

local C, rgb
local panel
local refreshers = {}

local COL_W = 340      -- width of one column
local COL_GAP = 36
local MARGIN = 26
local ROW_H = 30
local colX = MARGIN    -- the column the helpers below are drawing into
local stripe = false   -- every other row in a section gets a faint band

local function Changed()
	for _, fn in ipairs(refreshers) do fn() end
	ns.ApplyBlizzardText()
end

-- plain text, no drop shadow (the shadow made small text look bold)
local function Text(parent, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, size)
	fs:SetShadowOffset(0, 0)
	fs:SetTextColor(rgb(color or C.text))
	return fs
end

local function Section(parent, y, text)
	local fs = Text(parent, 11, C.accentText)
	fs:SetPoint("TOPLEFT", colX, y)
	fs:SetText(text:upper())
	local rule = ns.Rule(parent)
	rule:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	rule:SetWidth(math.max(1, COL_W - fs:GetStringWidth() - 8))
	stripe = false
	return y - 20
end

-- one setting's row: its name on the left; the control goes on the right
local function Row(parent, y, label)
	local row = CreateFrame("Button", nil, parent)
	row:SetPoint("TOPLEFT", colX - 6, y)
	row:SetWidth(COL_W + 12)
	row:SetHeight(ROW_H)
	if stripe then
		local band = row:CreateTexture(nil, "BACKGROUND")
		band:SetTexture(ns.FLAT)
		band:SetVertexColor(1, 1, 1, 0.03)
		band:SetAllPoints(row)
	end
	stripe = not stripe
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetTexture(ns.FLAT)
	hover:SetVertexColor(1, 1, 1, 0.05)
	hover:SetAllPoints(row)
	local fs = Text(row, 13)
	fs:SetPoint("LEFT", 6, 0)
	fs:SetText(label)
	return row
end

-- checkbox: retail's dark box with a bronze edge and a yellow tick; the whole row toggles it
local function Check(parent, y, label, get, set)
	local row = Row(parent, y, label)
	local box, tick = ns.CheckBox(row, 20)
	box:SetPoint("RIGHT", -4, 0)
	row:SetScript("OnClick", function() set(not get()); Changed() end)
	refreshers[#refreshers + 1] = function()
		if get() then tick:Show() else tick:Hide() end
	end
	return y - ROW_H
end

-- a dropdown on the right of its row, showing the current choice
local function Choice(parent, y, label, values, get, set)
	local row = Row(parent, y, label)
	local drop = ns.Dropdown(row, 150, values, get, function(key) set(key); Changed() end)
	drop:SetPoint("RIGHT", -4, 0)
	refreshers[#refreshers + 1] = function() drop:Refresh() end
	return y - ROW_H
end

-- The font draws "-" below the middle of its line, so the signs are gold bars centred in the button.
local function SignButton(parent, plus)
	local b = ns.RedButton(parent, "", 24, 22)
	local bars = { { 8, 2 } }
	if plus then bars[2] = { 2, 8 } end
	for _, size in ipairs(bars) do
		local bar = b:CreateTexture(nil, "OVERLAY")
		bar:SetTexture(ns.FLAT)
		bar:SetVertexColor(1, 0.82, 0)
		bar:SetWidth(size[1]); bar:SetHeight(size[2])
		bar:SetPoint("CENTER", 0, 0)
	end
	return b
end

-- [-] value [+] on the right of its row
local function Stepper(parent, y, label, lo, hi, step, fmt, get, set)
	local row = Row(parent, y, label)
	local plus = SignButton(row, true)
	plus:SetPoint("RIGHT", -4, 0)
	local value = Text(row, 13, C.accentText)
	value:SetWidth(44)
	value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
	local minus = SignButton(row, false)
	minus:SetPoint("RIGHT", value, "LEFT", -4, 0)
	local function bump(d)
		local v = math.floor((get() + d) / step + 0.5) * step
		if v < lo - step / 2 or v > hi + step / 2 then return end
		set(v); Changed()
	end
	minus:SetScript("OnClick", function() bump(-step) end)
	plus:SetScript("OnClick", function() bump(step) end)
	refreshers[#refreshers + 1] = function() value:SetText(fmt(get())) end
	return y - ROW_H
end

function ns.CreateOptions()
	C, rgb = ns.C, ns.rgb
	local db = ns.db
	panel = CreateFrame("Frame", "RatBitesOptions", UIParent)
	panel:Hide()
	panel:SetWidth(MARGIN * 2 + COL_W * 2 + COL_GAP)
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:SetPoint("CENTER")
	ns.SkinWindow(panel)
	tinsert(UISpecialFrames, "RatBitesOptions")

	local head, title = ns.TitleBar(panel, 30)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() panel:StartMoving() end)
	head:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
	title:SetText("RatBites")
	ns.Medallion(panel)

	local fonts = {}
	for _, f in ipairs(ns.FONTS) do fonts[#fonts + 1] = { f[1], f[2] } end

	-- left column: where the numbers show and how they look
	colX = MARGIN
	local y = -58
	y = Section(panel, y, "General")
	y = Check(panel, y, "Enabled",
		function() return db.enabled end, function(v) db.enabled = v end)
	y = Choice(panel, y, "Damage on",
		{ { "plates", "Nameplates" }, { "target", "Target only" }, { "screen", "Center screen" } },
		function() return db.anchor end, function(v) db.anchor = v end)
	y = Choice(panel, y, "Heals on",
		{ { "frames", "Raid frames" }, { "plates", "Nameplates" }, { "column", "Column" } },
		function() return db.healsOn end, function(v) db.healsOn = v end)
	y = Stepper(panel, y, "Size", 0.5, 2, 0.1, function(v) return format("%d%%", v * 100 + 0.5) end,
		function() return db.scale end, function(v) db.scale = v end)
	y = Choice(panel, y, "Font", fonts,
		function() return db.font end, function(v) db.font = v end)

	y = Section(panel, y - 10, "Look")
	y = Check(panel, y, "Spell icons",
		function() return db.icons end, function(v) db.icons = v end)
	y = Check(panel, y, "Class-colored damage",
		function() return db.classColor end, function(v) db.classColor = v end)
	y = Check(panel, y, "Big hits in gold",
		function() return db.bigGold end, function(v) db.bigGold = v end)
	y = Choice(panel, y, "Crit style",
		{ { "pop", "Pop" }, { "big", "Bigger" }, { "plain", "Plain" } },
		function() return db.critStyle end, function(v) db.critStyle = v end)
	y = Choice(panel, y, "Spread",
		{ { "none", "None" }, { "tight", "Tight" }, { "normal", "Normal" }, { "wide", "Wide" } },
		function() return db.spread end, function(v) db.spread = v end)
	y = Choice(panel, y, "Short numbers",
		{ { "short", "12.4k" }, { "full", "12,431" }, { "raw", "12431" } },
		function() return db.numbers end, function(v) db.numbers = v end)
	local leftEnd = y

	-- right column: which numbers show
	local show, inc = db.show, db.incoming
	local function flag(t, key)
		return function() return t[key] end, function(v) t[key] = v end
	end
	colX = MARGIN + COL_W + COL_GAP
	y = -58
	y = Section(panel, y, "Show")
	y = Check(panel, y, "Normal hits", flag(show, "normal"))
	y = Check(panel, y, "Critical hits", flag(show, "crit"))
	y = Check(panel, y, "Auto-attacks", flag(show, "swing"))
	y = Check(panel, y, "Abilities / spells", flag(show, "spell"))
	y = Check(panel, y, "Damage over time", flag(show, "dot"))
	y = Check(panel, y, "Heals", flag(show, "heal"))
	y = Check(panel, y, "Misses / avoidance", flag(show, "miss"))
	y = Check(panel, y, "Pet damage", flag(show, "pet"))

	y = Section(panel, y - 10, "Incoming")
	y = Check(panel, y, "Damage taken", flag(inc, "damage"))
	y = Check(panel, y, "Heals", flag(inc, "heals"))
	y = Check(panel, y, "Hide Blizzard text", flag(db, "hideBlizzard"))

	panel:SetHeight(-math.min(y, leftEnd) + 16)
	panel:SetScript("OnShow", function() for _, fn in ipairs(refreshers) do fn() end end)
	panel:SetScript("OnHide", function() ns.CloseDropdowns() end)
end

function ns.OpenOptions()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end
