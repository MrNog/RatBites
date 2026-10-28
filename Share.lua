local ADDON, ns = ...

-- The share window: one text box. Export fills it with the active profile as text to copy; import
-- takes a pasted text and loads it into the active profile. The box never takes the keyboard by
-- itself: you click into it, and it lets go on Escape and when the window closes.

local win, box, importButton, note, mode

local function Build()
	win = CreateFrame("Frame", "RatBitesShare", UIParent)
	win:SetWidth(480); win:SetHeight(270)
	win:SetFrameStrata("FULLSCREEN_DIALOG")
	win:SetToplevel(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:SetPoint("CENTER")
	ns.SkinWindow(win)
	tinsert(UISpecialFrames, "RatBitesShare")
	local head, title = ns.TitleBar(win, 30)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() win:StartMoving() end)
	head:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
	win.title = title

	note = win:CreateFontString(nil, "OVERLAY")
	note:SetFont(STANDARD_TEXT_FONT, 12)
	note:SetTextColor(ns.rgb(ns.C.textDim))
	note:SetPoint("TOPLEFT", 22, -42)
	note:SetPoint("RIGHT", -22, 0)
	note:SetJustifyH("LEFT")

	-- the text sits in a dark well that scrolls with the mouse wheel
	local back = ns.Skin(CreateFrame("Frame", nil, win), ns.C.panelD, 0.9)
	back:SetPoint("TOPLEFT", 22, -66)
	back:SetPoint("BOTTOMRIGHT", -22, 52)
	local well = CreateFrame("ScrollFrame", nil, win)
	well:SetAllPoints(back)
	well:SetFrameLevel(back:GetFrameLevel() + 1)
	box = CreateFrame("EditBox", nil, well)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(430)
	box:SetTextInsets(6, 6, 6, 6)
	well:SetScrollChild(box)
	well:EnableMouseWheel(true)
	well:SetScript("OnMouseWheel", function(self, delta)
		local y = self:GetVerticalScroll() - delta * 20
		self:SetVerticalScroll(math.max(0, math.min(y, self:GetVerticalScrollRange())))
	end)
	-- a click anywhere in the well puts the cursor in the box
	well:EnableMouse(true)
	well:SetScript("OnMouseDown", function() box:SetFocus() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self)
		if mode == "export" then self:HighlightText() end
	end)
	-- an exported text stays as it is, whatever is typed into it
	box:SetScript("OnTextChanged", function(self, user)
		if mode == "export" and user then
			self:SetText(win.exported)
			self:HighlightText()
		end
	end)

	importButton = ns.RedButton(win, "Import", 140, 22)
	importButton:SetPoint("BOTTOMRIGHT", -22, 18)
	importButton:SetScript("OnClick", function()
		local ok, why = ns.ImportProfile(box:GetText())
		if ok then
			ns.Print("Profile imported into " .. ns.ActiveProfile() .. ".")
			win:Hide()
		else
			note:SetText("|cffff6060" .. why .. "|r")
		end
	end)

	win:SetScript("OnHide", function() box:ClearFocus() end)
end

-- "export": the active profile as text to copy; "import": an empty box to paste one into
function ns.OpenShare(which)
	if not win then Build() end
	mode = which
	if which == "export" then
		win.title:SetText("Share " .. ns.ActiveProfile())
		note:SetText("Click the text, then Ctrl+C to copy it and send it to a friend.")
		win.exported = ns.ExportProfile()
		box:SetText(win.exported)
		importButton:Hide()
	else
		win.title:SetText("Import into " .. ns.ActiveProfile())
		note:SetText("Paste a shared RatBites profile (Ctrl+V), then Import. It replaces " .. ns.ActiveProfile() .. ".")
		box:SetText("")
		importButton:Show()
	end
	box:SetCursorPosition(0)
	win:Show()
end
