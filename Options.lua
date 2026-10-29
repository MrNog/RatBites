local ADDON, ns = ...

-- RatBites' settings window: a side menu (Numbers: Show, Spells, Look, Boxes, saved in the profile;
-- Setup: Profiles and App), the open page on its right as one column of one-line rows, the setting's
-- name on the left and its control on the right, and under it a bar with the profile in use, Test
-- and Move boxes.

local C, rgb
local panel
local refreshers = {}

local WIDTH = 780
local SIDE_W = 190      -- the side menu
local MARGIN = 26       -- a page's margin, inside the area right of the menu
local COL_W = WIDTH - SIDE_W - MARGIN * 2
local ROW_H = 34
local CONTROL_W = 170   -- dropdowns and buttons
local TOP = -46         -- where a page's first section starts, under the title bar
local FOOT_H = 46       -- the bar along the bottom
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
-- note: one short grey line under the heading saying what the section is for
local function Section(parent, y, text, first, note)
	if not first then y = y - 20 end
	local fs = Text(parent, 11, C.accentText)
	fs:SetPoint("TOPLEFT", MARGIN, y)
	fs:SetText(text:upper())
	local rule = ns.Rule(parent)
	rule:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	rule:SetWidth(math.max(1, COL_W - fs:GetStringWidth() - 8))
	stripe = false
	if note then
		local line = Text(parent, 13, C.textDim)
		line:SetPoint("TOPLEFT", MARGIN, y - 20)
		line:SetWidth(COL_W)
		line:SetJustifyH("LEFT")
		line:SetText(note)
		return y - 46
	end
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
	row.label = fs
	return row
end

-- a checkbox on a frame that toggles it when clicked
local function Tick(host, get, set)
	local box, tick = ns.CheckBox(host, 20)
	host:SetScript("OnClick", function() set(not get()); Changed() end)
	refreshers[#refreshers + 1] = function()
		if get() then tick:Show() else tick:Hide() end
	end
	return box
end

-- checkbox: retail's dark box with a bronze edge and a yellow tick; the whole row toggles it
local function Check(parent, y, label, get, set)
	local row = Row(parent, y, label)
	Tick(row, get, set):SetPoint("RIGHT", -8, 0)
	return y - ROW_H
end

-- a dropdown showing the current choice; values may be a function (a list that changes)
local function DropControl(parent, width, values, get, set)
	local drop = ns.Dropdown(parent, width, values, get, function(key) set(key); Changed() end)
	refreshers[#refreshers + 1] = function() drop:Refresh() end
	return drop
end

local function Choice(parent, y, label, values, get, set)
	local row = Row(parent, y, label)
	DropControl(row, CONTROL_W, values, get, set):SetPoint("RIGHT", -8, 0)
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

-- [-] value [+], as one frame
local function StepControl(parent, lo, hi, step, fmt, get, set)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(114); f:SetHeight(22)
	local minus = SignButton(f, false)
	minus:SetPoint("LEFT", 0, 0)
	local plus = SignButton(f, true)
	plus:SetPoint("RIGHT", 0, 0)
	local value = Text(f, 13, C.accentText)
	value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
	local function bump(d)
		local v = math.floor((get() + d) / step + 0.5) * step
		if v < lo - step / 2 or v > hi + step / 2 then return end
		set(v); Changed()
	end
	minus:SetScript("OnClick", function() bump(-step) end)
	plus:SetScript("OnClick", function() bump(step) end)
	refreshers[#refreshers + 1] = function() value:SetText(fmt(get())) end
	return f
end

local function Stepper(parent, y, label, lo, hi, step, fmt, get, set)
	local row = Row(parent, y, label)
	StepControl(row, lo, hi, step, fmt, get, set):SetPoint("RIGHT", -8, 0)
	return y - ROW_H
end

-- a tick for a setting that holds one of two values: ticked is on, unticked off
local function either(on, off, get, set)
	return function() return get() == on end, function(v) set(v and on or off) end
end

-- a setting by its path in the active profile ("show", "heal"): a getter and a setter that read
-- ns.db on every call, so they follow a profile switch
local function flag(...)
	local path = { ... }
	local last = table.remove(path)
	local function holder()
		local t = ns.db
		for _, k in ipairs(path) do t = t[k] end
		return t
	end
	return function() return holder()[last] end, function(v) holder()[last] = v end
end

-- an app setting: the same for every profile
local function app(key)
	return function() return ns.app[key] end, function(v) ns.app[key] = v end
end

-- A table of controls: one row per setting, one column per thing it's set for, with the columns'
-- names over them. cell(row, column, x, y) puts a row's control for a column, centred on x, y.
local GRID_LABEL = 200   -- room for the row names
local function Table(parent, y, columns, rows, cell)
	local colW = (COL_W - GRID_LABEL) / #columns
	local function centre(i) return MARGIN + GRID_LABEL + (i - 0.5) * colW end
	for i, col in ipairs(columns) do
		local head = Text(parent, 12, C.accentHi)
		head:SetWidth(colW - 4)
		head:SetJustifyH("CENTER")
		head:SetPoint("BOTTOM", parent, "TOPLEFT", centre(i), y - 22)
		head:SetText(col[2])
	end
	y = y - 26
	for _, def in ipairs(rows) do
		local row = Row(parent, y, def[2])
		for i, col in ipairs(columns) do cell(row, def, col, centre(i), y - ROW_H / 2) end
		y = y - ROW_H
	end
	return y
end

-- a Where grid: a checkbox in every cell, db.route[row][column]
local function Grid(parent, y, columns, rows)
	return Table(parent, y, columns, rows, function(row, def, col, x, cy)
		local cell = CreateFrame("Button", nil, row)
		cell:SetWidth(30); cell:SetHeight(30)
		cell:SetPoint("CENTER", parent, "TOPLEFT", x, cy)
		Tick(cell, flag("route", def[1], col[1])):SetPoint("CENTER")
	end)
end

-- ticks three to a line, each with its name after it
local function Ticks(parent, y, list)
	local per = 3
	local w = (COL_W + 16) / per
	for i, def in ipairs(list) do
		local col, line = (i - 1) % per, math.floor((i - 1) / per)
		local cell = CreateFrame("Button", nil, parent)
		cell:SetWidth(w - 4); cell:SetHeight(30)
		cell:SetPoint("TOPLEFT", MARGIN - 8 + col * w, y - line * 30)
		local hover = cell:CreateTexture(nil, "HIGHLIGHT")
		hover:SetTexture(ns.FLAT)
		hover:SetVertexColor(1, 1, 1, 0.05)
		hover:SetAllPoints(cell)
		Tick(cell, def[2], def[3]):SetPoint("LEFT", 8, 0)
		local fs = Text(cell, 14)
		fs:SetPoint("LEFT", 36, 0)
		fs:SetText(def[1])
	end
	return y - math.ceil(#list / per) * 30
end

local function Percent(v) return format("%d%%", v * 100 + 0.5) end

-- The training-yard picture behind the settings, as RatStash's behind its windows. Its subject sits in
-- the right third, so the picture keeps its right edge and a dark wash fades in from the left, where
-- the rows' names are. The file is 1024x512; the picture is 4:3.
local BG_TEX = [[Interface\AddOns\RatBites\Media\settings-bg]]
local BG_ASPECT = 4 / 3
local BG_ART = 0.5  -- how strongly the art shows through

local function PaintArt(art, wash, w, h)
	local a = ns.app.bgOn and BG_ART or 0
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

local function ShowPage(page)
	local y = Section(page, TOP, "What you do", true)
	y = Grid(page, y,
		{ { "plate", "Their plate" }, { "me", "Over me" }, { "mine", "Output box" } },
		{ { "dmg", "My damage" }, { "heal", "My heals" } })
	y = Check(page, y, "No nameplate? Use the Output box", flag("noPlateToBox"))
	y = Section(page, y, "What lands on you")
	y = Grid(page, y,
		{ { "me", "Over me" }, { "recv", "Input box" } },
		{ { "healMe", "Heals on me" }, { "dmgMe", "Damage on me" }, { "powerMe", "Mana, energy, rage" } })
	-- normal and crit hits, chosen for each kind of hit
	y = Section(page, y, "Which hits")
	y = Table(page, y, { { "normal", "Normal" }, { "crit", "Crit" } },
		{ { "spell", "Abilities" }, { "swing", "Auto-attacks" }, { "dot", "DoTs & bleeds" }, { "pet", "Pet" } },
		function(row, def, col, x, cy)
			local cell = CreateFrame("Button", nil, row)
			cell:SetWidth(30); cell:SetHeight(30)
			cell:SetPoint("CENTER", page, "TOPLEFT", x, cy)
			Tick(cell, flag("show", "hits", def[1], col[1])):SetPoint("CENTER")
		end)
	local misses, overheal = { flag("show", "miss") }, { flag("show", "overheal") }
	y = Ticks(page, y - 4, { { "Misses", misses[1], misses[2] }, { "Overheal", overheal[1], overheal[2] } })
	y = Choice(page, y, "Shields from my heals",
		{ { "heal", "+11k (+240)" }, { "line", "+11k   +240" }, { "off", "+11k" } },
		function()
			local db = ns.db
			return not db.show.shield and "off" or db.joinShields and "heal" or "line"
		end,
		function(v)
			local db = ns.db
			db.show.shield, db.joinShields = v ~= "off", v == "heal"
		end)
	return y
end

local function LookPage(page)
	local y = Section(page, TOP, "Text", true)
	y = Choice(page, y, "Font", ns.FontList(), flag("font"))
	y = Stepper(page, y, "Size", 0.5, 2, 0.1, Percent, flag("scale"))
	y = Choice(page, y, "Align", { { "center", "Center" }, { "left", "Left" }, { "right", "Right" } },
		flag("align"))
	y = Check(page, y, "Short numbers (12.4k)", either("short", "full", flag("numbers")))
	y = Check(page, y, "Spell icons", flag("icons"))
	y = Check(page, y, "Class color on my hits", either("normal", "off", flag("classColorFor")))
	y = Section(page, y, "Crits")
	y = Check(page, y, "Crits pop", either("pop", "big", flag("critStyle")))
	y = Stepper(page, y, "Crit size", 2, 30, 1, function(v) return format("%gx", v) end, flag("critSize"))
	y = Section(page, y, "Motion")
	local moves = { { "arc", "Arc" }, { "rise", "Rise" }, { "stay", "Stay" } }
	y = Choice(page, y, "Damage", moves, flag("animation"))
	y = Choice(page, y, "Heals", moves, flag("healAnimation"))
	y = Stepper(page, y, "Time on screen", 0.8, 4, 0.1, function(v) return format("%.1fs", v) end, flag("duration"))
	return y
end

-- the two boxes side by side, the same four settings for each
local function BoxesPage(page)
	local y = Section(page, TOP, "Boxes", true, "Move and resize them with Move boxes, below.")
	local controls = {
		style = function(row, key, x, cy)
			DropControl(row, 120, { { "scroll", "Scroll" }, { "arc", "Arc" }, { "rise", "Rise" }, { "stay", "Stay" },
				{ "pop", "Pop" } }, flag("boxes", key, "style")):SetPoint("CENTER", page, "TOPLEFT", x, cy)
		end,
		scroll = function(row, key, x, cy)
			DropControl(row, 120, { { "up", "Bottom" }, { "down", "Top" } }, flag("boxes", key, "scroll"))
				:SetPoint("CENTER", page, "TOPLEFT", x, cy)
		end,
		align = function(row, key, x, cy)
			DropControl(row, 120, { { "left", "Left" }, { "center", "Center" }, { "right", "Right" } },
				flag("boxes", key, "align")):SetPoint("CENTER", page, "TOPLEFT", x, cy)
		end,
		merge = function(row, key, x, cy)
			local cell = CreateFrame("Button", nil, row)
			cell:SetWidth(30); cell:SetHeight(30)
			cell:SetPoint("CENTER", page, "TOPLEFT", x, cy)
			Tick(cell, either(1, 0, flag("boxes", key, "merge"))):SetPoint("CENTER")
		end,
		scale = function(row, key, x, cy)
			StepControl(row, 0.5, 2, 0.1, Percent, flag("boxes", key, "scale"))
				:SetPoint("CENTER", page, "TOPLEFT", x, cy)
		end,
		time = function(row, key, x, cy)
			StepControl(row, 2, 10, 1, function(v) return format("%ds", v) end, flag("boxes", key, "time"))
				:SetPoint("CENTER", page, "TOPLEFT", x, cy)
		end,
	}
	y = Table(page, y - 4,
		{ { "mine", "Output box" }, { "received", "Input box" } },
		{ { "style", "Shows as" }, { "scale", "Text size" }, { "scroll", "New lines at" }, { "align", "Align" }, { "merge", "Merge repeats (x2, x3 ...)" },
			{ "time", "Each line stays" } },
		function(row, def, col, x, cy) controls[def[1]](row, col[1], x, cy) end)
	return y
end

-- Profiles live in Core.lua; this page picks this character's, and one for its second spec.
-- A small window asking before something that replaces a whole profile: the question, then the
-- action's button and Cancel. Esc cancels too.
local confirm
local function Confirm(question, yes, onYes)
	if not confirm then
		confirm = CreateFrame("Frame", "RatBitesConfirm", UIParent)
		confirm:SetWidth(380); confirm:SetHeight(140)
		confirm:SetFrameStrata("FULLSCREEN_DIALOG")
		confirm:SetToplevel(true)
		confirm:EnableMouse(true)
		confirm:SetPoint("CENTER", 0, 120)
		ns.SkinWindow(confirm)
		tinsert(UISpecialFrames, "RatBitesConfirm")
		local _, title = ns.TitleBar(confirm, 30)
		title:SetText("RatBites")
		confirm.text = Text(confirm, 14)
		confirm.text:SetPoint("TOPLEFT", 24, -46)
		confirm.text:SetPoint("RIGHT", -24, 0)
		confirm.text:SetJustifyH("CENTER")
		confirm.no = ns.RedButton(confirm, "Cancel", 120, 22)
		confirm.no:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -6, 20)
		confirm.no:SetScript("OnClick", function() confirm:Hide() end)
		confirm.yes = ns.RedButton(confirm, "", 120, 22)
		confirm.yes:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 6, 20)
	end
	confirm.text:SetText(question)
	confirm.yes:SetText(yes)
	confirm.yes:SetScript("OnClick", function()
		confirm:Hide()
		onYes()
		Changed()
	end)
	confirm:Show()
end


-- Your spells in a grid two wide that scrolls: every spell of yours that has made a number in a
-- fight (a spell shows up the first time you use it). Its ticks rule every number it makes, its
-- effects too (Seal of Corruption: Blood Corruption, Judgement of Corruption), and a small line under
-- its name says what those are. The grid is read again each time the window refreshes.
local SPELL_LINES, SPELL_COLS = 14, 2

-- what kind of number a spell makes, as the short word beside it
local TAGS = {
	swing = "auto-attack", spell = "hit", dot = "damage over time", heal = "heal", shield = "shield",
	power0 = "mana", power1 = "rage", power3 = "energy", power6 = "runic power",
}

local function byName(a, b) return a[1] < b[1] end

local GROUPS = { "Class spells", "Talents", "Glyphs", "Items" }

-- Melee and each class spell, talent, glyph and item proc that has made a number in the spec you're
-- in, in those four groups, each A to Z. A number goes to what it belongs to (ns.SpellOwner: Blood
-- Corruption to Seal of Corruption); a buff's or a boss's isn't listed. A row is { name, icon,
-- what = "hit · heal" }.
local GROUP_OF = { spell = 1, talent = 2, glyph = 3 }

local function SpellList(list)
	local seen, kinds = ns.char.seen, ns.char.kinds or {}
	local specs, spec = ns.char.specs or {}, GetActiveTalentGroup() or 1
	local rows, group, what = {}, {}, {}
	rows[MELEE], group[MELEE] = select(3, GetSpellInfo(6603)) or true, 1  -- Attack
	for name, icon in pairs(seen) do
		if not specs[name] or specs[name][spec] then
			local owner = ns.SpellOwner(name)
			local g = owner and GROUP_OF[ns.Have(owner)]
			if name == MELEE then owner, g = MELEE, 1 end
			if not owner and ns.FromGear(name) then owner, g = name, 4 end
			if g then
				rows[owner], group[owner] = rows[owner] or GetSpellTexture(owner) or icon, g
				local tag = TAGS[kinds[name]]
				if tag then
					what[owner] = what[owner] or {}
					if not tContains(what[owner], tag) then tinsert(what[owner], tag) end
				end
			end
		end
	end
	local groups = { {}, {}, {}, {} }
	for name, icon in pairs(rows) do
		local tags = what[name]
		if tags then table.sort(tags) end
		tinsert(groups[group[name]], { name, icon, what = tags and table.concat(tags, " \194\183 ") })
	end
	wipe(list)
	for g, rowsOf in ipairs(groups) do
		if #rowsOf > 0 then
			table.sort(rowsOf, byName)
			while #list % SPELL_COLS ~= 0 do list[#list + 1] = false end
			list[#list + 1] = { heading = GROUPS[g]:upper() }
			for _ = 2, SPELL_COLS do list[#list + 1] = false end
			for _, row in ipairs(rowsOf) do list[#list + 1] = row end
		end
	end
	while #list % SPELL_COLS ~= 0 do list[#list + 1] = false end
end

local function SpellsPage(page)
	local y = Section(page, TOP, "Your spells", true,
		"Where each spell shows: Plates (and over you), Boxes, or untick both to hide it.")
	local cellW = (COL_W + 16) / SPELL_COLS
	-- the two ticks' names over each column of spells
	for col = 1, SPELL_COLS do
		local right = MARGIN - 8 + col * cellW - 4
		for _, def in ipairs({ { "Plates", 54 }, { "Boxes", 14 } }) do
			local head = Text(page, 11, C.accentHi)
			head:SetPoint("BOTTOM", page, "TOPLEFT", right - def[2], y - 12)
			head:SetText(def[1])
		end
	end
	y = y - 16
	local cells, list, first, bar = {}, {}, 1, nil
	local function fill()
		SpellList(list)
		local shown = SPELL_LINES * SPELL_COLS
		first = math.max(1, math.min(first, #list - shown + 1))
		for i, cell in ipairs(cells) do
			local entry = list[first + i - 1]
			if entry and entry.heading then
				cell.spell = nil
				cell.label:SetText(entry.heading)
				cell.label:SetTextColor(rgb(C.accentText))
				cell.label:SetPoint("LEFT", 38, 0)
				cell.label:SetPoint("RIGHT", -76, 0)
				cell.what:SetText("")
				cell.icon:Hide(); cell.plates:Hide(); cell.boxes:Hide()
				cell:Show()
			elseif entry then
				cell.spell = entry[1]
				cell.label:SetText(entry[1])
				cell.label:SetTextColor(rgb(entry.inert and C.textDim or C.text))
				cell.what:SetText(entry.what or "")
				-- the name sits up a little when the line under it has something to say
				cell.label:SetPoint("LEFT", 38, entry.what and 6 or 0)
				cell.label:SetPoint("RIGHT", -76, entry.what and 6 or 0)
				cell.icon:SetTexture(type(entry[2]) == "string" and entry[2] or nil)
				cell.icon:Show()
				if entry.inert then
					cell.plates:Hide(); cell.boxes:Hide()
				else
					cell.plates:Show(); cell.boxes:Show()
					cell.plates:Paint(); cell.boxes:Paint()
				end
				cell:Show()
			else
				cell:Hide()
			end
		end
		bar:Paint(#list / SPELL_COLS, (first - 1) / SPELL_COLS)
	end
	local function scroll(_, delta)
		first = first - delta * SPELL_COLS * 2
		fill()
	end
	for line = 1, SPELL_LINES do
		for col = 1, SPELL_COLS do
			local cell = CreateFrame("Button", nil, page)
			cell:SetWidth(cellW - 4); cell:SetHeight(ROW_H - 2)
			cell:SetPoint("TOPLEFT", MARGIN - 8 + (col - 1) * cellW, y - (line - 1) * ROW_H)
			if line % 2 == 0 then
				local band = cell:CreateTexture(nil, "BACKGROUND")
				band:SetTexture(ns.FLAT)
				band:SetVertexColor(1, 1, 1, 0.03)
				band:SetAllPoints(cell)
			end
			local hover = cell:CreateTexture(nil, "HIGHLIGHT")
			hover:SetTexture(ns.FLAT)
			hover:SetVertexColor(1, 1, 1, 0.05)
			hover:SetAllPoints(cell)
			cell.icon = cell:CreateTexture(nil, "ARTWORK")
			cell.icon:SetWidth(22); cell.icon:SetHeight(22)
			cell.icon:SetPoint("LEFT", 8, 0)
			cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			cell.label = Text(cell, 13)
			cell.label:SetPoint("LEFT", 38, 0)
			cell.label:SetPoint("RIGHT", -76, 0)
			cell.label:SetJustifyH("LEFT")
			cell.what = Text(cell, 11, C.textDim)
			cell.what:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -1)
			cell.what:SetPoint("RIGHT", -76, 0)
			cell.what:SetJustifyH("LEFT")
			-- the game's tooltip for the spell, so a proc's name says what it is
			cell:SetScript("OnEnter", function(self)
				local id = self.spell and (ns.char.ids or {})[self.spell]
				local link = id and ("spell:" .. id) or (self.spell and GetSpellLink(self.spell))
				if not link then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink(link:match("spell:%d+"))
				GameTooltip:Show()
			end)
			cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
			-- a tick for plates and one for boxes; ticked = shown there
			local function Place(key, x)
				local b = CreateFrame("Button", nil, cell)
				b:SetWidth(28); b:SetHeight(28)
				b:SetPoint("CENTER", cell, "RIGHT", -x, 0)
				local box, tick = ns.CheckBox(b, 20)
				box:SetPoint("CENTER")
				function b:Paint()
					if ns.db[key][cell.spell] then tick:Hide() else tick:Show() end
				end
				b:SetScript("OnClick", function()
					local off = ns.db[key]
					off[cell.spell] = not off[cell.spell] or nil
					b:Paint()
				end)
				b:EnableMouseWheel(true)
				b:SetScript("OnMouseWheel", scroll)
				return b
			end
			cell.plates, cell.boxes = Place("noPlates", 54), Place("noBoxes", 14)
			cell:EnableMouseWheel(true)
			cell:SetScript("OnMouseWheel", scroll)
			cells[#cells + 1] = cell
		end
	end
	y = y - SPELL_LINES * ROW_H
	-- a scrollbar beside the grid while the list is longer than the page: a dark track and a gold
	-- thumb as tall as the share in view; drag the thumb, click the track or use the wheel
	local gridH = SPELL_LINES * ROW_H
	local track = CreateFrame("Button", nil, page)
	track:SetWidth(8); track:SetHeight(gridH)
	track:SetPoint("TOPLEFT", MARGIN + COL_W + 12, y + gridH)
	local well = track:CreateTexture(nil, "BACKGROUND")
	well:SetTexture(ns.FLAT)
	well:SetVertexColor(0, 0, 0, 0.45)
	well:SetAllPoints(track)
	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(8)
	local paint = thumb:CreateTexture(nil, "ARTWORK")
	paint:SetTexture(ns.FLAT)
	paint:SetVertexColor(rgb(C.accent))
	paint:SetAllPoints(thumb)
	thumb:SetScript("OnEnter", function() paint:SetVertexColor(rgb(C.accentHi)) end)
	thumb:SetScript("OnLeave", function() paint:SetVertexColor(rgb(C.accent)) end)
	local lines, top = 0, 0
	local function toLine(line)
		local want = math.floor(line + 0.5) * SPELL_COLS + 1
		if want ~= first then first = want; fill() end
	end
	function track:Paint(total, at)
		lines, top = math.ceil(total), at
		if lines <= SPELL_LINES then track:Hide() return end
		track:Show()
		local h = math.max(24, gridH * SPELL_LINES / lines)
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -(gridH - h) * top / (lines - SPELL_LINES))
	end
	thumb:SetScript("OnMouseDown", function(self)
		local _, cy = GetCursorPosition()
		local startY, startTop, scale = cy, top, self:GetEffectiveScale()
		self:SetScript("OnUpdate", function()
			local _, y2 = GetCursorPosition()
			local span = gridH - self:GetHeight()
			if span > 0 then toLine(startTop + (startY - y2) / scale / span * (lines - SPELL_LINES)) end
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	track:SetScript("OnClick", function(self)
		local _, cy = GetCursorPosition()
		local share = (self:GetTop() - cy / self:GetEffectiveScale()) / gridH
		toLine(share * lines - SPELL_LINES / 2)
	end)
	track:EnableMouseWheel(true)
	track:SetScript("OnMouseWheel", scroll)
	bar = track
	refreshers[#refreshers + 1] = fill
	return y
end


-- a name box: dark well, grey hint while empty. It takes the keyboard only when clicked, and lets go
-- on Escape, Enter and when the window closes.
local function NameBox(parent, width, hint, onEnter)
	local well = ns.Skin(CreateFrame("Frame", nil, parent), C.panelD, 0.9)
	well:SetWidth(width); well:SetHeight(24)
	local box = CreateFrame("EditBox", nil, well)
	box:SetAllPoints(well)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(8, 8, 0, 0)
	box:SetMaxLetters(32)
	local ghost = Text(well, 13, C.textDim)
	ghost:SetPoint("LEFT", 8, 0)
	ghost:SetText(hint)
	local function sync()
		if box:GetText() == "" and not box:HasFocus() then ghost:Show() else ghost:Hide() end
	end
	box:SetScript("OnTextChanged", sync)
	box:SetScript("OnEditFocusGained", sync)
	box:SetScript("OnEditFocusLost", sync)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); onEnter() end)
	parent:HookScript("OnHide", function() box:ClearFocus() end)
	well.box = box
	return well
end

local function ProfilesPage(page)
	local function names()
		local list = {}
		for _, name in ipairs(ns.ProfileNames()) do list[#list + 1] = { name, name } end
		return list
	end

	-- like ElvUI: the first row is the spec you're in (the profile every page edits), the second the
	-- other spec's; they swap when you switch spec. The secondary spec can use "the same" as the primary.
	local function second() return (GetActiveTalentGroup() or 1) == 2 end
	local function spec(isSecond) return isSecond and "secondary spec" or "primary spec" end

	local y = Section(page, TOP, "Profiles", true, "Every character on this account can use any of them.")
	local current = Row(page, y, "")
	DropControl(current, CONTROL_W, names, ns.ActiveProfile, function(v)
		if second() then ns.SetProfile(v, "second") else ns.SetProfile(v) end
	end):SetPoint("RIGHT", -8, 0)
	y = y - ROW_H
	local other = Row(page, y, "")
	DropControl(other, CONTROL_W,
		function()
			local list = names()
			if not second() then table.insert(list, 1, { "same", "The same" }) end
			return list
		end,
		function()
			if second() then return ns.char.profile end
			return ns.char.second or "same"
		end,
		function(v)
			if second() then ns.SetProfile(v) else ns.SetProfile(v ~= "same" and v or nil, "second") end
		end):SetPoint("RIGHT", -8, 0)
	y = y - ROW_H
	refreshers[#refreshers + 1] = function()
		current.label:SetText("Profile |cff9a9a9a(" .. spec(second()) .. ", in use)|r")
		other.label:SetText(spec(not second()):gsub("^%l", strupper) .. " uses")
	end
	local row = Row(page, y, "New profile")
	local well
	local create = ns.RedButton(row, "Create", 80, 22)
	create:SetPoint("RIGHT", -8, 0)
	local function make()
		local ok, why = ns.CreateProfile(well.box:GetText())
		if ok then
			well.box:SetText("")
			well.box:ClearFocus()
			Changed()
		else
			ns.Print(why)
		end
	end
	well = NameBox(row, CONTROL_W - 86, "name", make)
	well:SetPoint("RIGHT", create, "LEFT", -6, 0)
	create:SetScript("OnClick", make)
	y = y - ROW_H

	y = Section(page, y, "Edit the profile in use")
	y = Choice(page, y, "Copy from",
		function()
			local list = { { "none", "Choose" } }
			for _, preset in ipairs(ns.PRESETS) do list[#list + 1] = { "preset:" .. preset, preset .. " preset" } end
			for _, name in ipairs(ns.ProfileNames()) do
				if name ~= ns.ActiveProfile() then list[#list + 1] = { name, name } end
			end
			return list
		end,
		function() return "none" end,
		function(v)
			if v == "none" then return end
			local name = ns.ActiveProfile()
			local from = v:match("^preset:(.+)") and v:match("^preset:(.+)") .. " preset" or v
			Confirm("Copy " .. from .. " into " .. name .. "?\nEverything in " .. name .. " is replaced.",
				"Copy", function() ns.CopyProfile(v) end)
		end)
	y = Choice(page, y, "Delete a profile",
		function()
			local list = { { "none", "Choose" } }
			for _, name in ipairs(ns.ProfileNames()) do
				if name ~= "Default" and name ~= ns.ActiveProfile() then list[#list + 1] = { name, name } end
			end
			return list
		end,
		function() return "none" end,
		function(v)
			if v == "none" then return end
			Confirm("Delete " .. v .. "?\nCharacters using it go back to Default.", "Delete",
				function() ns.DeleteProfile(v) end)
		end)
	row = Row(page, y, "Reset, send or load")
	local last
	for _, def in ipairs({
		{ "Import", function() ns.OpenShare("import") end },
		{ "Export", function() ns.OpenShare("export") end },
		{ "Reset", function()
			local name = ns.ActiveProfile()
			Confirm("Reset " .. name .. " to the default settings?", "Reset", ns.ResetProfile)
		end },
	}) do
		local b = ns.RedButton(row, def[1], 80, 22)
		if last then b:SetPoint("RIGHT", last, "LEFT", -6, 0) else b:SetPoint("RIGHT", -8, 0) end
		b:SetScript("OnClick", def[2])
		last = b
	end
	return y - ROW_H
end

local function AppPage(page)
	local y = Section(page, TOP, "App", true, "The same for every profile.")
	y = Check(page, y, "RatBites on", app("enabled"))
	y = Check(page, y, "Hide the game's own numbers", app("hideBlizzard"))
	if ns.SoundPack() then y = Check(page, y, "Crit sounds", app("critSounds")) end
	if ns.PackVolumes() then
		-- each step plays a crit sound at the new volume, to hear it
		local get, set = app("critVolume")
		y = Stepper(page, y, "Crit volume", 25, 100, 25, function(v) return format("%d%%", v) end, get, function(v)
			set(v)
			ns.PlayRole(ns.CritRole("spell"))
		end)
	end
	y = Check(page, y, "Minimap button", app("minimapButton"))
	y = Check(page, y, "Background art", app("bgOn"))
	return y
end

-- the side menu: groups of pages, each with its icon
local MENU = {
	{ "Numbers", {
		{ "show", "Show", [[Interface\Icons\Ability_Hunter_SniperShot]], ShowPage },
		{ "spells", "Spells", [[Interface\Icons\Spell_Fire_Fireball02]], SpellsPage },
		{ "look", "Look", [[Interface\Icons\INV_Misc_Spyglass_03]], LookPage },
		{ "boxes", "Boxes", [[Interface\Icons\INV_Scroll_03]], BoxesPage },
	} },
	{ "Setup", {
		{ "profiles", "Profiles", [[Interface\Icons\Achievement_Character_Orc_Male]], ProfilesPage },
		{ "app", "App", [[Interface\Icons\INV_Misc_Wrench_01]], AppPage },
	} },
}

-- every row shows the active profile's value again (after a profile switch)
function ns.RefreshOptions()
	for _, fn in ipairs(refreshers) do fn() end
end

local MENU_TOP, MENU_ROW = -54, 34   -- the menu starts clear of the medallion

function ns.CreateOptions()
	C, rgb = ns.C, ns.rgb
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

	-- the side menu's edge: a hairline from under the title bar to the bottom
	local edge = body:CreateTexture(nil, "ARTWORK")
	edge:SetTexture(ns.FLAT)
	edge:SetVertexColor(rgb(ns.WIN_EDGE))
	edge:SetWidth(1)
	edge:SetPoint("TOPLEFT", SIDE_W, -30)
	edge:SetPoint("BOTTOMLEFT", SIDE_W, ns.INSET)

	local items, pages, lowest = {}, {}, 0
	local function Open(key)
		ns.char.tab = key
		ns.CloseDropdowns()
		for k, page in pairs(pages) do
			if k == key then page:Show() else page:Hide() end
			local item = items[k]
			if k == key then
				item.text:SetTextColor(rgb(C.accentText))
				item.band:Show()
			else
				item.text:SetTextColor(rgb(C.text))
				item.band:Hide()
			end
		end
	end
	local y = MENU_TOP
	for g, group in ipairs(MENU) do
		if g > 1 then y = y - 12 end
		local heading = Text(body, 11, C.textDim)
		heading:SetPoint("TOPLEFT", 22, y)
		heading:SetText(group[1]:upper())
		local rule = ns.Rule(body)
		rule:SetPoint("TOPLEFT", 22, y - 16)
		rule:SetWidth(SIDE_W - 40)
		y = y - 24
		for _, def in ipairs(group[2]) do
			local key = def[1]
			local item = CreateFrame("Button", nil, body)
			item:SetPoint("TOPLEFT", 14, y)
			item:SetWidth(SIDE_W - 28); item:SetHeight(MENU_ROW - 2)
			item.band = item:CreateTexture(nil, "BACKGROUND")
			item.band:SetTexture(ns.FLAT)
			item.band:SetVertexColor(1, 0.82, 0, 0.06)
			item.band:SetAllPoints(item)
			local hover = item:CreateTexture(nil, "HIGHLIGHT")
			hover:SetTexture(ns.FLAT)
			hover:SetVertexColor(1, 1, 1, 0.05)
			hover:SetAllPoints(item)
			local icon = item:CreateTexture(nil, "ARTWORK")
			icon:SetTexture(def[3])
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			icon:SetWidth(24); icon:SetHeight(24)
			icon:SetPoint("LEFT", 8, 0)
			item.text = Text(item, 15)
			item.text:SetPoint("LEFT", icon, "RIGHT", 10, 0)
			item.text:SetText(def[2])
			item:SetScript("OnClick", function() PlaySound("igMainMenuOptionCheckBoxOn"); Open(key) end)
			items[key] = item
			y = y - MENU_ROW

			local page = CreateFrame("Frame", nil, body)
			page:SetPoint("TOPLEFT", SIDE_W, 0)
			page:SetPoint("BOTTOMRIGHT", 0, 0)
			page:Hide()
			pages[key] = page
			lowest = math.min(lowest, def[4](page))
		end
	end
	lowest = math.min(lowest, y)

	-- the bar along the bottom, under the pages: the profile in use, Test and Move boxes
	local foot = CreateFrame("Frame", nil, body)
	foot:SetPoint("BOTTOMLEFT", SIDE_W + 1, ns.INSET)
	foot:SetPoint("BOTTOMRIGHT", -ns.INSET, ns.INSET)
	foot:SetHeight(FOOT_H)
	local footRule = ns.Rule(foot)
	footRule:SetPoint("TOPLEFT", 0, 0)
	footRule:SetPoint("TOPRIGHT", 0, 0)
	local who = Text(foot, 12, C.textDim)
	who:SetPoint("LEFT", MARGIN - 4, 0)
	local move = ns.RedButton(foot, "", 120, 22)
	move:SetPoint("RIGHT", -MARGIN + 6, 0)
	move:SetScript("OnClick", function() ns.SetBoxesUnlocked(not ns.BoxesUnlocked()); Changed() end)
	local test = ns.RedButton(foot, "", 120, 22)
	test:SetPoint("RIGHT", move, "LEFT", -6, 0)
	test:SetScript("OnClick", function() ns.SetTestLoop(not ns.TestLooping()); Changed() end)
	-- test as another class and role: its colour on the numbers, its crit sound
	DropControl(foot, 170, ns.PreviewValues, ns.PreviewKey, ns.SetPreview):SetPoint("RIGHT", test, "LEFT", -6, 0)
	refreshers[#refreshers + 1] = function()
		who:SetText("Profile: |cffffd100" .. ns.ActiveProfile() .. "|r")
		test:SetText(ns.TestLooping() and "Stop test" or "Test")
		move:SetText(ns.BoxesUnlocked() and "Lock boxes" or "Move boxes")
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


	panel:SetHeight(-lowest + FOOT_H + 20)
	refreshers[#refreshers + 1] = function() PaintArt(art, wash, panel:GetWidth(), panel:GetHeight()) end
	Open(pages[ns.char.tab] and ns.char.tab or "show")
	panel:SetScript("OnShow", function() for _, fn in ipairs(refreshers) do fn() end end)
	panel:SetScript("OnHide", function()
		ns.CloseDropdowns()
		if folding then return end
		-- boxes left unlocked would keep catching clicks meant for the game
		ns.SetBoxesUnlocked(false)
		ns.SetTestLoop(false)
	end)
end

-- the window is made the first time it opens, so a session that never opens it doesn't carry it
function ns.OpenOptions()
	if not panel then ns.CreateOptions() end
	if ns.RestoreOptions() then return end
	if panel:IsShown() then panel:Hide() else panel:Show() end
end
