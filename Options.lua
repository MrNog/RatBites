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
	ns.RelayoutBoxes()
	ns.UpdateMinimapButton()
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

-- The training-yard picture behind the settings, as RatStash's behind its windows. Its subject sits in
-- the right third, so the picture keeps its right edge and a dark wash fades in from the left, where
-- the rows' names are. The file is 1024x512; the picture is 4:3.
local BG_TEX = [[Interface\AddOns\RatBites\Media\settings-bg]]
local BG_ASPECT = 4 / 3

local function PaintArt(art, wash, w, h)
	local db = ns.db
	local a = db.bgOn and (db.bgArt or 0) or 0
	if a <= 0 then art:Hide(); wash:Hide(); return end
	art:SetTexture(BG_TEX)
	local want = w / h
	if want < BG_ASPECT then
		local span = want / BG_ASPECT
		art:SetTexCoord(1 - span, 1, 0, 1)
	else
		local span = BG_ASPECT / want
		art:SetTexCoord(0, 1, 0.5 - span / 2, 0.5 + span / 2)
	end
	art:Show()
	-- stronger art = thinner wash
	local d = C.panelD
	wash:SetTexture(ns.FLAT)
	wash:SetGradientAlpha("HORIZONTAL", d[1], d[2], d[3], 0.95 - a * 0.25, d[1], d[2], d[3], 0.85 - a * 0.65)
	wash:Show()
end

-- a red button on the right of its row; label() gives its text after each change
local function Action(parent, y, text, onClick, label)
	local row = Row(parent, y, text)
	local b = ns.RedButton(row, "", 150, 22)
	b:SetPoint("RIGHT", -4, 0)
	b:SetScript("OnClick", function() onClick(); Changed() end)
	refreshers[#refreshers + 1] = function() b:SetText(label()) end
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
	local art = panel:CreateTexture(nil, "BORDER")
	art:SetPoint("TOPLEFT", ns.INSET, -ns.INSET); art:SetPoint("BOTTOMRIGHT", -ns.INSET, ns.INSET)
	ns.CoverCorners(panel, art)
	local wash = panel:CreateTexture(nil, "ARTWORK")
	wash:SetAllPoints(art)

	local head, title = ns.TitleBar(panel, 30)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() panel:StartMoving() end)
	head:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
	title:SetText("RatBites")
	ns.Medallion(panel)

	-- every row lives on the body, so minimizing hides them all and leaves the title bar
	local body = CreateFrame("Frame", nil, panel)
	body:SetAllPoints(panel)
	local fullHeight, minimized
	local MINI_HEIGHT = 36

	-- the minimize button left of the X: a gold minus, a plus while minimized
	local mini = ns.RedButton(head, "", 20, 20)
	mini:SetPoint("RIGHT", head.close, "LEFT", -4, 0)
	local across = mini:CreateTexture(nil, "OVERLAY")
	across:SetTexture(ns.FLAT); across:SetVertexColor(1, 0.82, 0)
	across:SetWidth(8); across:SetHeight(2); across:SetPoint("CENTER")
	local down = mini:CreateTexture(nil, "OVERLAY")
	down:SetTexture(ns.FLAT); down:SetVertexColor(1, 0.82, 0)
	down:SetWidth(2); down:SetHeight(8); down:SetPoint("CENTER")
	down:Hide()

	-- the window keeps its top edge where it is while it shrinks or grows
	local function SetMinimized(on)
		minimized = on
		local left, top = panel:GetLeft(), panel:GetTop()
		if left and top then
			panel:ClearAllPoints()
			panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
		ns.CloseDropdowns()
		if on then body:Hide(); down:Show() else body:Show(); down:Hide() end
		panel:SetHeight(on and MINI_HEIGHT or fullHeight)
		for _, fn in ipairs(refreshers) do fn() end
	end
	mini:SetScript("OnClick", function() SetMinimized(not minimized) end)

	local fonts = ns.FontList()

	-- left column: where the numbers show and how they look
	colX = MARGIN
	local y = -58
	y = Section(body, y, "General")
	y = Check(body, y, "Enabled",
		function() return db.enabled end, function(v) db.enabled = v end)
	y = Action(body, y, "Test numbers",
		function() ns.SetTestLoop(not ns.TestLooping()) end,
		function() return ns.TestLooping() and "Stop" or "Start" end)
	y = Choice(body, y, "Show on",
		{ { "plates", "Nameplates" }, { "target", "Target only" }, { "screen", "Center screen" }, { "box", "My box" } },
		function() return db.anchor end, function(v) db.anchor = v end)
	y = Choice(body, y, "Received shows on",
		{ { "box", "Received box" }, { "floating", "Floating" } },
		function() return db.receivedOn end, function(v) db.receivedOn = v end)
	y = Stepper(body, y, "Text size", 0.5, 2, 0.1, function(v) return format("%d%%", v * 100 + 0.5) end,
		function() return db.scale end, function(v) db.scale = v end)
	y = Stepper(body, y, "Icon size", 0.5, 2, 0.1, function(v) return format("%d%%", v * 100 + 0.5) end,
		function() return db.iconScale end, function(v) db.iconScale = v end)
	y = Choice(body, y, "Font", fonts,
		function() return db.font end, function(v) db.font = v end)

	y = Section(body, y - 10, "Motion")
	y = Choice(body, y, "Animation",
		{ { "arc", "Arc" }, { "rise", "Rise" }, { "stay", "Stay" }, { "fountain", "Fountain" }, { "fall", "Fall" } },
		function() return db.animation end, function(v) db.animation = v end)
	y = Choice(body, y, "Spread",
		{ { "none", "None" }, { "tight", "Tight" }, { "normal", "Normal" }, { "wide", "Wide" } },
		function() return db.spread end, function(v) db.spread = v end)
	y = Stepper(body, y, "Height", 20, 150, 10, function(v) return format("%d", v) end,
		function() return db.height end, function(v) db.height = v end)
	y = Stepper(body, y, "Duration", 0.8, 4, 0.1, function(v) return format("%.1fs", v) end,
		function() return db.duration end, function(v) db.duration = v end)

	y = Section(body, y - 10, "Look")
	y = Check(body, y, "Spell icons",
		function() return db.icons end, function(v) db.icons = v end)
	y = Check(body, y, "Class-colored damage",
		function() return db.classColor end, function(v) db.classColor = v end)
	y = Check(body, y, "Big hits in gold",
		function() return db.bigGold end, function(v) db.bigGold = v end)
	y = Choice(body, y, "Crit style",
		{ { "pop", "Pop" }, { "big", "Bigger" }, { "plain", "Plain" } },
		function() return db.critStyle end, function(v) db.critStyle = v end)
	y = Choice(body, y, "Short numbers",
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
	y = Section(body, y, "Show")
	y = Check(body, y, "Normal hits", flag(show, "normal"))
	y = Check(body, y, "Critical hits", flag(show, "crit"))
	y = Check(body, y, "Auto-attacks", flag(show, "swing"))
	y = Check(body, y, "Abilities / spells", flag(show, "spell"))
	y = Check(body, y, "Damage over time", flag(show, "dot"))
	y = Check(body, y, "Heals", flag(show, "heal"))
	y = Check(body, y, "Misses / avoidance", flag(show, "miss"))
	y = Check(body, y, "Pet damage", flag(show, "pet"))

	y = Section(body, y - 10, "Received")
	y = Check(body, y, "Damage taken", flag(inc, "damage"))
	y = Check(body, y, "Heals", flag(inc, "heals"))
	y = Check(body, y, "Hide Blizzard text", flag(db, "hideBlizzard"))

	y = Section(body, y - 10, "Boxes")
	y = Choice(body, y, "Scroll",
		{ { "up", "Up" }, { "down", "Down" } },
		function() return db.boxScroll end, function(v) db.boxScroll = v end)
	y = Stepper(body, y, "Line time", 2, 10, 1, function(v) return format("%ds", v) end,
		function() return db.boxTime end, function(v) db.boxTime = v end)
	y = Action(body, y, "Move boxes",
		function() ns.SetBoxesUnlocked(not ns.BoxesUnlocked()) end,
		function() return ns.BoxesUnlocked() and "Lock" or "Unlock" end)

	y = Section(body, y - 10, "Window")
	y = Check(body, y, "Minimap button", flag(db, "minimapButton"))
	y = Check(body, y, "Background art", flag(db, "bgOn"))
	y = Stepper(body, y, "Art strength", 0.1, 1, 0.1, function(v) return format("%.1f", v) end,
		function() return db.bgArt end, function(v) db.bgArt = v end)

	fullHeight = -math.min(y, leftEnd) + 16
	panel:SetHeight(fullHeight)
	refreshers[#refreshers + 1] = function()
		if minimized then
			art:Hide(); wash:Hide()
		else
			PaintArt(art, wash, panel:GetWidth(), panel:GetHeight())
		end
	end
	panel:SetScript("OnShow", function() for _, fn in ipairs(refreshers) do fn() end end)
	panel:SetScript("OnHide", function()
		ns.CloseDropdowns()
		-- boxes left unlocked would keep catching clicks meant for the game
		ns.SetBoxesUnlocked(false)
		ns.SetTestLoop(false)
	end)
end

function ns.OpenOptions()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end
