local ADDON, ns = ...

-- RatBites' settings window: five tabs along the top (General, Look, Motion, Show, Boxes), each a
-- single column of roomy one-line rows, the setting's name on the left and its control on the right.

local C, rgb
local panel
local refreshers = {}

local WIDTH = 640
local MARGIN = 30
local COL_W = WIDTH - MARGIN * 2
local ROW_H = 36
local CONTROL_W = 170   -- dropdowns and buttons
local TOP = -96         -- where a page's first section starts, under the tabs
local stripe = false    -- every other row in a section gets a faint band

local function Changed()
	for _, fn in ipairs(refreshers) do fn() end
	ns.ApplyBlizzardText()
	ns.RelayoutBoxes()
	ns.UpdateMinimapButton()
	ns.RefreshLegend()
end

-- plain text, no drop shadow (the shadow made small text look bold)
local function Text(parent, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, size)
	fs:SetShadowOffset(0, 0)
	fs:SetTextColor(rgb(color or C.text))
	return fs
end

-- a gold heading with a hairline to the column's end; first = the page's top one, without the gap
local function Section(parent, y, text, first)
	if not first then y = y - 22 end
	local fs = Text(parent, 11, C.accentText)
	fs:SetPoint("TOPLEFT", MARGIN, y)
	fs:SetText(text:upper())
	local rule = ns.Rule(parent)
	rule:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	rule:SetWidth(math.max(1, COL_W - fs:GetStringWidth() - 8))
	stripe = false
	return y - 26
end

-- one setting's row: its name on the left; the control goes on the right
local function Row(parent, y, label)
	local row = CreateFrame("Button", nil, parent)
	row:SetPoint("TOPLEFT", MARGIN - 8, y)
	row:SetWidth(COL_W + 16)
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
	local fs = Text(row, 14)
	fs:SetPoint("LEFT", 10, 0)
	fs:SetText(label)
	return row
end

-- checkbox: retail's dark box with a bronze edge and a yellow tick; the whole row toggles it
local function Check(parent, y, label, get, set)
	local row = Row(parent, y, label)
	local box, tick = ns.CheckBox(row, 20)
	box:SetPoint("RIGHT", -8, 0)
	row:SetScript("OnClick", function() set(not get()); Changed() end)
	refreshers[#refreshers + 1] = function()
		if get() then tick:Show() else tick:Hide() end
	end
	return y - ROW_H
end

-- a dropdown on the right of its row, showing the current choice
local function Choice(parent, y, label, values, get, set)
	local row = Row(parent, y, label)
	local drop = ns.Dropdown(row, CONTROL_W, values, get, function(key) set(key); Changed() end)
	drop:SetPoint("RIGHT", -8, 0)
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
	plus:SetPoint("RIGHT", -8, 0)
	local value = Text(row, 13, C.accentText)
	value:SetWidth(58)
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

-- a red button on the right of its row; label() gives its text after each change
local function Action(parent, y, text, onClick, label)
	local row = Row(parent, y, text)
	local b = ns.RedButton(row, "", CONTROL_W, 22)
	b:SetPoint("RIGHT", -8, 0)
	b:SetScript("OnClick", function() onClick(); Changed() end)
	refreshers[#refreshers + 1] = function() b:SetText(label()) end
	return y - ROW_H
end

local function Percent(v) return format("%d%%", v * 100 + 0.5) end

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

--------------------------------------------------------------------------------
-- the pages
--------------------------------------------------------------------------------

local function GeneralPage(page, db, flag)
	local y = Section(page, TOP, "Numbers", true)
	y = Check(page, y, "Enabled", flag(db, "enabled"))
	y = Action(page, y, "Test numbers",
		function() ns.SetTestLoop(not ns.TestLooping()) end,
		function() return ns.TestLooping() and "Stop" or "Start" end)
	y = Check(page, y, "Hide the game's own numbers", flag(db, "hideBlizzard"))
	y = Section(page, y, "Output: what you do")
	y = Choice(page, y, "Show on",
		{ { "plates", "Nameplates" }, { "box", "My box" },
			{ "healsplates", "Heals plates, dmg box" }, { "dmgplates", "Dmg plates, heals box" } },
		flag(db, "anchor"))
	y = Choice(page, y, "Heals with no nameplate",
		{ { "box", "My box" }, { "column", "Column" }, { "hide", "Hide" } },
		flag(db, "noPlateHeals"))
	y = Section(page, y, "Receiving: what lands on you")
	y = Check(page, y, "Also float over my character", flag(db, "receivedFloat"))
	y = Section(page, y, "Window")
	y = Check(page, y, "Minimap button", flag(db, "minimapButton"))
	y = Check(page, y, "Background art", flag(db, "bgOn"))
	y = Stepper(page, y, "Art strength", 0.1, 1, 0.1, function(v) return format("%.1f", v) end, flag(db, "bgArt"))
	return y
end

local function LookPage(page, db, flag)
	local y = Section(page, TOP, "Text", true)
	y = Choice(page, y, "Font", ns.FontList(), flag(db, "font"))
	y = Stepper(page, y, "Text size", 0.5, 2, 0.1, Percent, flag(db, "scale"))
	y = Choice(page, y, "Number format",
		{ { "short", "12.4k" }, { "full", "12,431" }, { "raw", "12431" } },
		flag(db, "numbers"))
	y = Section(page, y, "Icons")
	y = Check(page, y, "Spell icons", flag(db, "icons"))
	y = Stepper(page, y, "Icon size", 0.5, 2, 0.1, Percent, flag(db, "iconScale"))
	y = Section(page, y, "Colors")
	y = Action(page, y, "Color examples",
		function() ns.ToggleLegend() end,
		function() return "Show (/bites colors)" end)
	y = Choice(page, y, "Critical hits",
		{ { "pop", "Pop" }, { "big", "Bigger" }, { "plain", "Plain" } },
		flag(db, "critStyle"))
	y = Check(page, y, "Big hits in gold", flag(db, "bigGold"))
	y = Choice(page, y, "My class color for",
		{ { "off", "Off" }, { "normal", "Normal hits" }, { "crit", "Crits" } },
		flag(db, "classColorFor"))
	return y
end

local function MotionPage(page, db, flag)
	local y = Section(page, TOP, "Floating numbers", true)
	y = Choice(page, y, "Animation",
		{ { "arc", "Arc" }, { "rise", "Rise" }, { "stay", "Stay" }, { "fountain", "Fountain" }, { "fall", "Fall" } },
		flag(db, "animation"))
	y = Choice(page, y, "Sideways drift",
		{ { "none", "None" }, { "tight", "Tight" }, { "normal", "Normal" }, { "wide", "Wide" } },
		flag(db, "spread"))
	y = Stepper(page, y, "Travel distance", 20, 150, 10, function(v) return format("%d", v) end, flag(db, "height"))
	y = Stepper(page, y, "Time on screen", 0.8, 4, 0.1, function(v) return format("%.1fs", v) end, flag(db, "duration"))
	return y
end

local function ShowPage(page, db, flag)
	local show, inc = db.show, db.incoming
	local y = Section(page, TOP, "What you do", true)
	y = Check(page, y, "Normal hits", flag(show, "normal"))
	y = Check(page, y, "Critical hits", flag(show, "crit"))
	y = Check(page, y, "Auto-attacks", flag(show, "swing"))
	y = Check(page, y, "Spells and abilities", flag(show, "spell"))
	y = Check(page, y, "Damage over time", flag(show, "dot"))
	y = Check(page, y, "Heals and shields", flag(show, "heal"))
	y = Choice(page, y, "Shields from heals",
		{ { "join", "Join the heal" }, { "line", "Own line" }, { "hide", "Hide" } },
		flag(db, "healShields"))
	y = Check(page, y, "Misses (dodge, parry ...)", flag(show, "miss"))
	y = Check(page, y, "Pet damage", flag(show, "pet"))
	y = Section(page, y, "What is done to you")
	y = Check(page, y, "Damage taken", flag(inc, "damage"))
	y = Check(page, y, "Heals received", flag(inc, "heals"))
	return y
end

local function BoxesPage(page, db, flag)
	local y = Section(page, TOP, "Both boxes", true)
	y = Action(page, y, "Move and resize boxes",
		function() ns.SetBoxesUnlocked(not ns.BoxesUnlocked()) end,
		function() return ns.BoxesUnlocked() and "Lock" or "Unlock" end)
	-- the same four rows for each box, on its own settings
	for _, def in ipairs({ { "mine", "My box: what you do" }, { "received", "Received box: what lands on you" } }) do
		local box = db.boxes[def[1]]
		y = Section(page, y, def[2])
		y = Choice(page, y, "New lines come in at",
			{ { "up", "The bottom" }, { "down", "The top" } },
			flag(box, "scroll"))
		y = Choice(page, y, "Text alignment",
			{ { "left", "Left" }, { "center", "Center" }, { "right", "Right" } },
			flag(box, "align"))
		y = Choice(page, y, "Merge repeats within",
			{ { 0, "Off" }, { 0.5, "0.5 sec" }, { 1, "1 sec" }, { 2, "2 sec" }, { 3, "3 sec" } },
			flag(box, "merge"))
		y = Stepper(page, y, "Each line stays", 2, 10, 1, function(v) return format("%ds", v) end, flag(box, "time"))
	end
	return y
end

local PAGES = {
	{ "general", "General", GeneralPage },
	{ "look", "Look", LookPage },
	{ "motion", "Motion", MotionPage },
	{ "show", "Show", ShowPage },
	{ "boxes", "Boxes", BoxesPage },
}

--------------------------------------------------------------------------------
-- tabs: small cut-corner plates standing on the hairline under them; the open one takes the window's
-- fill, a gold edge and gold text
--------------------------------------------------------------------------------

local TAB_H, TAB_PAD, TAB_GAP = 28, 18, 4
local TAB_X, TAB_Y = 90, -42   -- clear of the medallion over the top-left corner

local function PaintTab(tab, on)
	if on then
		ns.TintChamfer(tab.chamfer, ns.WIN_FILL, C.accent)
		tab.text:SetTextColor(rgb(C.accentText))
	else
		ns.TintChamfer(tab.chamfer, C.panelD, ns.WIN_EDGE)
		tab.text:SetTextColor(rgb(C.textDim))
	end
end

function ns.CreateOptions()
	C, rgb = ns.C, ns.rgb
	local db = ns.db
	panel = CreateFrame("Frame", "RatBitesOptions", UIParent)
	panel:Hide()
	panel:SetWidth(WIDTH)
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

	-- everything under the title bar lives on the body, so minimizing hides it all
	local body = CreateFrame("Frame", nil, panel)
	body:SetAllPoints(panel)

	local function flag(t, key)
		return function() return t[key] end, function(v) t[key] = v end
	end

	-- the tabs and the gold hairline they stand on
	local line = body:CreateTexture(nil, "ARTWORK")
	line:SetTexture(ns.FLAT)
	line:SetVertexColor(rgb(C.accent))
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", ns.INSET, TAB_Y - TAB_H)
	line:SetPoint("TOPRIGHT", -ns.INSET, TAB_Y - TAB_H)
	local tabs, pages, lowest = {}, {}, 0
	local function Open(key)
		db.tab = key
		ns.CloseDropdowns()
		for k, page in pairs(pages) do
			if k == key then page:Show() else page:Hide() end
			PaintTab(tabs[k], k == key)
		end
	end
	local x = TAB_X
	for _, def in ipairs(PAGES) do
		local key = def[1]
		local tab = CreateFrame("Button", nil, body)
		tab.chamfer = ns.SmallChamfer(tab, true)
		tab.text = Text(tab, 13)
		tab.text:SetPoint("CENTER", 0, 0)
		tab.text:SetText(def[2])
		tab:SetWidth(tab.text:GetStringWidth() + TAB_PAD * 2)
		tab:SetHeight(TAB_H)
		-- the open tab covers the hairline under it, so it joins the page
		tab:SetPoint("TOPLEFT", body, "TOPLEFT", x, TAB_Y)
		tab:SetFrameLevel(body:GetFrameLevel() + 3)
		tab:SetScript("OnClick", function() PlaySound("igMainMenuOptionCheckBoxOn"); Open(key) end)
		x = x + tab:GetWidth() + TAB_GAP
		tabs[key] = tab

		local page = CreateFrame("Frame", nil, body)
		page:SetAllPoints(body)
		page:Hide()
		pages[key] = page
		lowest = math.min(lowest, def[3](page, db, flag))
	end

	-- Minimized, the window folds into its medallion, floating where the medallion was: drag it away,
	-- click it to open the window again around it. The test and unlocked boxes keep going meanwhile.
	local MEDAL_X, MEDAL_Y = 10, -8   -- the medallion's centre from the window's top-left corner
	local dot = CreateFrame("Button", "RatBitesOptionsIcon", UIParent)
	dot:SetWidth(60); dot:SetHeight(60)
	dot:SetFrameStrata("DIALOG")
	dot:SetMovable(true)
	dot:SetClampedToScreen(true)
	dot:RegisterForDrag("LeftButton")
	dot:Hide()
	local medal = ns.Medallion(dot)
	medal:ClearAllPoints()
	medal:SetPoint("CENTER", dot, "CENTER")
	dot:SetScript("OnDragStart", function(self) self:StartMoving() end)
	dot:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	dot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("RatBites")
		GameTooltip:AddLine("Click: open settings", 1, 1, 1)
		GameTooltip:AddLine("Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	dot:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local folding = false
	local function Minimize()
		local left, top = panel:GetLeft(), panel:GetTop()
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", left + MEDAL_X, top + MEDAL_Y)
		folding = true
		panel:Hide()
		folding = false
		dot:Show()
	end
	local function Restore()
		local x, y = dot:GetCenter()
		dot:Hide()
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - MEDAL_X, y - MEDAL_Y)
		panel:Show()
	end
	dot:SetScript("OnClick", Restore)
	ns.RestoreOptions = function()
		if dot:IsShown() then Restore() return true end
	end

	-- the minimize button left of the X, at the X's size
	local mini = ns.MinusButton(head)
	mini:SetWidth(head.close:GetWidth()); mini:SetHeight(head.close:GetHeight())
	mini:SetPoint("RIGHT", head.close, "LEFT", -4, 0)
	mini:SetScript("OnClick", Minimize)

	panel:SetHeight(-lowest + 24)
	refreshers[#refreshers + 1] = function() PaintArt(art, wash, panel:GetWidth(), panel:GetHeight()) end
	Open(pages[db.tab] and db.tab or "general")
	panel:SetScript("OnShow", function() for _, fn in ipairs(refreshers) do fn() end end)
	panel:SetScript("OnHide", function()
		ns.CloseDropdowns()
		if folding then return end
		-- boxes left unlocked would keep catching clicks meant for the game
		ns.SetBoxesUnlocked(false)
		ns.SetTestLoop(false)
	end)
end

function ns.OpenOptions()
	if ns.RestoreOptions() then return end
	if panel:IsShown() then panel:Hide() else panel:Show() end
end
