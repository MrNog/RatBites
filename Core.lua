local ADDON, ns = ...

-- anchor (output: your damage and heals on others): "plates" = on the unit's nameplate, "box" = My box
-- what lands on you always goes to the Received box; receivedFloat also floats it over your character
-- animation: "arc", "rise", "stay", "fountain" or "fall" (Bites.lua's Path)
-- critStyle: "pop" = starts large and settles, "big" = larger, "plain" = colour only
-- numbers: "short" = 12.4k, "full" = 12,431, "raw" = 12431
ns.DEFAULTS = {
	enabled = true,
	anchor = "plates",
	receivedFloat = false,
	animation = "arc",
	height = 70,
	duration = 1.5,
	boxScroll = "up",
	boxTime = 5,
	boxes = {
		mine = { x = 300, y = -60, w = 200, h = 220 },
		received = { x = -300, y = -60, w = 200, h = 220 },
	},
	scale = 1,
	iconScale = 1,  -- an icon's size against its number's text
	font = "friz",
	icons = true,
	classColor = false,
	bigGold = true,
	critStyle = "pop",
	spread = "normal",
	numbers = "short",
	show = { normal = true, crit = true, swing = true, spell = true, dot = true, miss = true, pet = true, heal = true },
	incoming = { damage = false, heals = false },
	hideBlizzard = true,
	bgOn = true,
	bgArt = 0.5,
	minimapButton = true,
	minimapAngle = 220,
}

local function copyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			copyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffe8c35aRatBites|r: " .. tostring(msg))
end

-- event fan-out: several files can listen to the same event
local handlers = {}
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do fn(...) end
end)
function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		ev:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

-- The game's own numbers over the mobs you hit. While RatBites draws them, the game's are turned off;
-- the values they had are kept and put back when RatBites stops.
local BLIZZARD_CVARS = { "CombatDamage", "PetMeleeDamage", "CombatHealing" }

function ns.ApplyBlizzardText()
	local db = ns.db
	if db.enabled and db.hideBlizzard then
		if not db.blizzSaved then
			db.blizzSaved = {}
			for _, cvar in ipairs(BLIZZARD_CVARS) do db.blizzSaved[cvar] = GetCVar(cvar) end
		end
		for _, cvar in ipairs(BLIZZARD_CVARS) do SetCVar(cvar, "0") end
	elseif db.blizzSaved then
		for cvar, value in pairs(db.blizzSaved) do SetCVar(cvar, value) end
		db.blizzSaved = nil
	end
end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	RatBitesDB = RatBitesDB or {}
	copyDefaults(ns.DEFAULTS, RatBitesDB)
	ns.db = RatBitesDB
	-- output goes on nameplates or into My box; older choices (target only, centre screen) fold into nameplates
	if ns.db.anchor ~= "box" then ns.db.anchor = "plates" end
	ns.db.receivedOn = nil
end)

ns.On("PLAYER_LOGIN", function()
	ns.playerGUID = UnitGUID("player")
	ns.ApplyBlizzardText()
	ns.CreateOptions()
end)

-- /rb is the game's Raid Browser
SLASH_RATBITES1 = "/bites"
SLASH_RATBITES2 = "/ratbites"
SlashCmdList.RATBITES = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "test" then
		ns.Test()
	elseif msg == "move" then
		ns.SetBoxesUnlocked(not ns.BoxesUnlocked())
	elseif msg == "plates" then
		ns.ReportPlates()
	else
		ns.OpenOptions()
	end
end
