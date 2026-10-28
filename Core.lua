local ADDON, ns = ...

-- anchor: "plates" = on each enemy's nameplate, "target" = your target only, "screen" = a fixed spot
-- critStyle: "pop" = starts large and settles, "big" = larger, "plain" = colour only
-- numbers: "short" = 12.4k, "full" = 12,431, "raw" = 12431
ns.DEFAULTS = {
	enabled = true,
	anchor = "plates",
	scale = 1,
	font = "friz",
	icons = true,
	classColor = false,
	bigGold = true,
	critStyle = "pop",
	numbers = "short",
	show = { normal = true, crit = true, swing = true, spell = true, dot = true, miss = true, pet = true, heal = true },
	incoming = { damage = false, heals = false },
	hideBlizzard = true,
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
end)

ns.On("PLAYER_LOGIN", function()
	ns.playerGUID = UnitGUID("player")
	ns.ApplyBlizzardText()
	ns.CreateOptions()
end)

SLASH_RATBITES1 = "/rb"
SLASH_RATBITES2 = "/ratbites"
SlashCmdList.RATBITES = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "test" then
		ns.Test()
	else
		ns.OpenOptions()
	end
end
