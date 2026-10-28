local ADDON, ns = ...

-- xCT-style boxes: My box takes what you do (damage and heals), Received box what is done to you,
-- whenever a "... on" setting sends numbers there. A new line comes in at one edge and pushes the
-- older ones along; each line fades out at the end of its Line time, and lines that no longer fit
-- drop off. Unlocked, a box shows its frame to be dragged and resized.

local LINE_GAP = 4
local FADE = 0.5   -- a line fades over its last half second
local MERGE_TIME = 0.4
local EDGE_PAD = 8  -- left- or right-aligned lines keep this far from the box's side
local NAMES = { mine = "My box", received = "Received box" }

local boxes = {}
local unlocked = false

-- a box's spot is kept as its centre's offset from the screen's centre, plus its size
local function Save(box)
	local p = ns.db.boxes[box.key]
	local x, y = box:GetCenter()
	local cx, cy = UIParent:GetCenter()
	p.x, p.y = x - cx, y - cy
	p.w, p.h = box:GetWidth(), box:GetHeight()
end

local function Place(box)
	local p = ns.db.boxes[box.key]
	box:ClearAllPoints()
	box:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
	box:SetWidth(p.w); box:SetHeight(p.h)
end

local function NewLine(box)
	local line = CreateFrame("Frame", nil, box)
	line:SetWidth(1); line:SetHeight(1)
	line.text = line:CreateFontString(nil, "OVERLAY")
	line.text:SetShadowColor(0, 0, 0, 1)
	line.text:SetShadowOffset(1, -1)
	line.edge = line:CreateTexture(nil, "ARTWORK")
	line.edge:SetTexture(ns.FLAT)
	line.edge:SetVertexColor(0, 0, 0)
	line.icon = line:CreateTexture(nil, "OVERLAY")
	line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	line.icon:SetPoint("RIGHT", line.text, "LEFT", -4, 0)
	line.edge:SetPoint("TOPLEFT", line.icon, "TOPLEFT", -1, 1)
	line.edge:SetPoint("BOTTOMRIGHT", line.icon, "BOTTOMRIGHT", 1, -1)
	return line
end

local function Drop(box, i)
	local line = table.remove(box.lines, i)
	line:Hide()
	table.insert(box.pool, line)
end

-- A line is an anchor point with its icon and text around it. Centred, the text sits on the point;
-- left, the point is the box's left edge and icon then text run right from it; right, the text ends
-- on the box's right edge with the icon before it.
local function Align(box, line)
	local align = ns.db.boxAlign
	line.text:ClearAllPoints()
	if align == "left" then
		local icon = line.icon:IsShown() and line.icon:GetWidth() + 4 or 0
		line.text:SetPoint("LEFT", line, "CENTER", icon, 0)
		return EDGE_PAD
	elseif align == "right" then
		line.text:SetPoint("RIGHT", line, "CENTER", 0, 0)
		return box:GetWidth() - EDGE_PAD
	end
	line.text:SetPoint("CENTER", line, "CENTER", 0, 0)
	return box:GetWidth() / 2
end

-- newest line first: at the bottom when lines scroll up, at the top when they scroll down
local function Layout(box)
	local up = ns.db.boxScroll ~= "down"
	local room, offset = box:GetHeight(), 0
	for i = 1, #box.lines do
		local line = box.lines[i]
		local h = math.max(line.size, line.size * ns.db.iconScale) + LINE_GAP
		if offset + h > room then
			for j = #box.lines, i, -1 do Drop(box, j) end
			return
		end
		local x = Align(box, line)
		line:ClearAllPoints()
		if up then
			line:SetPoint("CENTER", box, "BOTTOMLEFT", x, offset + h / 2)
		else
			line:SetPoint("CENTER", box, "TOPLEFT", x, -offset - h / 2)
		end
		offset = offset + h
	end
end

local function Fade(box)
	local now, life = GetTime(), ns.db.boxTime
	for i = #box.lines, 1, -1 do
		local line = box.lines[i]
		local age = now - line.at
		if age >= life then
			Drop(box, i)
		elseif age > life - FADE then
			line:SetAlpha((life - age) / FADE)
		end
	end
end

local function Create(key)
	local box = CreateFrame("Frame", key == "mine" and "RatBitesMyBox" or "RatBitesReceivedBox", UIParent)
	box.key = key
	box.lines, box.pool = {}, {}
	box:SetFrameStrata("LOW")
	box:SetMovable(true)
	box:SetResizable(true)
	box:SetClampedToScreen(true)
	box:SetMinResize(100, 60)
	box:EnableMouse(false)
	box:RegisterForDrag("LeftButton")
	box:SetScript("OnDragStart", function() box:StartMoving() end)
	box:SetScript("OnDragStop", function()
		box:StopMovingOrSizing()
		Save(box); Place(box)
	end)
	box:SetScript("OnUpdate", function() Fade(box) end)

	-- shown only while unlocked: a dark frame with the box's name and a size grip
	local edit = CreateFrame("Frame", nil, box)
	edit:SetAllPoints(box)
	ns.Skin(edit, ns.C.panelD, 0.6)
	edit:SetBackdropBorderColor(ns.rgb(ns.C.accent))
	local title = ns.Font(edit:CreateFontString(nil, "OVERLAY"), 12)
	title:SetTextColor(ns.rgb(ns.C.accentText))
	title:SetPoint("TOP", 0, -6)
	title:SetText(NAMES[key])
	local grip = CreateFrame("Button", nil, edit)
	grip:SetWidth(16); grip:SetHeight(16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
	grip:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
	grip:SetPushedTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])
	grip:SetScript("OnMouseDown", function() box:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		box:StopMovingOrSizing()
		Save(box); Place(box); Layout(box)
	end)
	edit:Hide()
	box.edit = edit

	Place(box)
	return box
end

-- one line into a box: "mine" or "received"
function ns.BoxAdd(key, label, color, size, icon)
	local box = boxes[key]
	if not box then return end
	local db = ns.db
	-- The same spell landing again right away in the same colour (a glyph's five splashes, a point or
	-- two apart) joins the line before it as "x5", keeping that line's number, so a burst can't push
	-- the heal that caused it out of the box.
	local last = box.lines[1]
	if last and icon and last.iconPath == icon and last.color == color and GetTime() - last.at < MERGE_TIME then
		last.count = last.count + 1
		last.text:SetText(last.label .. " x" .. last.count)
		last.at = GetTime()
		last:SetAlpha(1)
		return
	end
	local line = table.remove(box.pool) or NewLine(box)
	line.label, line.iconPath, line.color, line.count = label, icon, color, 1
	size = size * db.scale
	line.text:SetFont(ns.FontPath(), size, color.thick and "THICKOUTLINE" or "OUTLINE")
	line.text:SetText(label)
	line.text:SetTextColor(color[1], color[2], color[3])
	if icon and db.icons then
		line.icon:SetTexture(icon)
		line.icon:SetWidth(size * db.iconScale); line.icon:SetHeight(size * db.iconScale)
		line.icon:Show(); line.edge:Show()
	else
		line.icon:Hide(); line.edge:Hide()
	end
	line.size, line.at = size, GetTime()
	line:SetAlpha(1)
	line:Show()
	table.insert(box.lines, 1, line)
	Layout(box)
end

function ns.BoxesUnlocked() return unlocked end

-- Unlocked, both boxes show their frames and take the mouse, with a few sample lines to size them by.
function ns.SetBoxesUnlocked(on)
	unlocked = on
	for _, box in pairs(boxes) do
		box:EnableMouse(on)
		if on then box.edit:Show() else box.edit:Hide() end
	end
	if on then
		ns.BoxAdd("mine", "12.4k", ns.COLOR.crit, 26)
		ns.BoxAdd("mine", "+1923", ns.COLOR.heal, 20)
		ns.BoxAdd("mine", "2331", { 0.72, 0.72, 0.72 }, 20)
		ns.BoxAdd("received", "-640", ns.COLOR.taken, 18)
		ns.BoxAdd("received", "+812", ns.COLOR.heal, 18)
	end
end

-- after a setting changes: the scroll direction or the scale may move every line
function ns.RelayoutBoxes()
	for _, box in pairs(boxes) do Layout(box) end
end

ns.On("PLAYER_LOGIN", function()
	boxes.mine = Create("mine")
	boxes.received = Create("received")
end)
