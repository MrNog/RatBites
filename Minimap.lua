local ADDON, ns = ...

-- The app icon on the minimap's edge, in the game's round tracking border. Left-click opens the
-- settings, right-click unlocks the boxes; drag it around the edge.

local button

local function Place()
	local a = math.rad(ns.app.minimapAngle)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
end

local function Create()
	local b = CreateFrame("Button", "RatBitesMinimapButton", Minimap)
	b:SetWidth(31); b:SetHeight(31)
	b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]])

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53); border:SetHeight(53)
	border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
	border:SetPoint("TOPLEFT")
	-- the medallion art is already cut round
	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetWidth(21); icon:SetHeight(21)
	icon:SetTexture([[Interface\AddOns\RatBites\Media\UI\medallion]])
	icon:SetPoint("CENTER", 1, 1)

	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local sc = Minimap:GetEffectiveScale()
			ns.app.minimapAngle = math.deg(math.atan2(py / sc - my, px / sc - mx))
			Place()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			ns.SetBoxesUnlocked(not ns.BoxesUnlocked())
		else
			ns.OpenOptions()
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("RatBites")
		GameTooltip:AddLine("Click: settings", 1, 1, 1)
		GameTooltip:AddLine("Right-click: move boxes", 1, 1, 1)
		GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
		-- read on hover only: the game counts every addon's memory when asked
		UpdateAddOnMemoryUsage()
		local kb = GetAddOnMemoryUsage(ADDON)
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Memory", kb >= 1024 and format("%.1f MB", kb / 1024) or format("%d KB", kb),
			0.6, 0.6, 0.6, 1, 0.82, 0)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- shows or hides the button after the "Minimap button" setting changes
function ns.UpdateMinimapButton()
	if ns.app.minimapButton then
		button = button or Create()
		Place()
		button:Show()
	elseif button then
		button:Hide()
	end
end

-- made as soon as RatBites loads (its settings are read by then), so minimap button bars that
-- collect buttons at login find it on their first pass
ns.On("ADDON_LOADED", function(name)
	if name == ADDON then ns.UpdateMinimapButton() end
end)
