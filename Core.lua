local ADDON, ns = ...

-- One profile's settings. ns.db is the active profile.
-- route: the Where grid. Rows dmg (your damage), heal (your heals on others), healMe and dmgMe (heals
-- and damage landing on you); each ticks plate (over the unit's nameplate, or over you for what lands
-- on you), me (over your character), mine (My box) and recv (Received box)
-- noPlateToBox: a number wanted over a nameplate that isn't on screen goes to My box instead
-- joinShields: a shield your heal makes (Val'anyr, Divine Aegis) joins that heal's number
-- animation: "arc", "rise", "stay", "fountain" or "fall" (Bites.lua's Path)
-- critStyle: "pop" = starts large and settles, "big" = larger, "plain" = colour only
-- numbers: "short" = 12.4k, "full" = 12,431, "raw" = 12431
ns.DEFAULTS = {
	enabled = true,
	route = {
		dmg = { plate = true, me = false, mine = false, recv = false },
		heal = { plate = true, me = false, mine = false, recv = false },
		healMe = { plate = false, me = false, mine = false, recv = true },
		dmgMe = { plate = false, me = false, mine = false, recv = true },
	},
	noPlateToBox = true,
	joinShields = true,
	animation = "arc",
	height = 70,
	duration = 1.5,
	-- each box: its spot and size, where new lines come in ("up" = at the bottom), text alignment,
	-- merge (sec: the same spell again within this joins its line as a total with "xN"; 0 = off) and
	-- how long a line stays (sec)
	boxes = {
		mine = { x = 300, y = -60, w = 200, h = 220, scroll = "up", align = "left", merge = 3, time = 5 },
		received = { x = -300, y = -60, w = 200, h = 220, scroll = "up", align = "left", merge = 0, time = 5 },
	},
	scale = 1,
	iconScale = 1,  -- an icon's size against its number's text
	font = "friz",
	icons = true,
	classColorFor = "off",  -- "normal" = your normal damage, "crit" = your crits; the other keeps its colour
	bigGold = true,
	critStyle = "pop",
	critSize = 2.7,  -- a crit (Pop or Bigger) against a normal hit
	spread = "normal",
	numbers = "short",
	show = { normal = true, crit = true, swing = true, spell = true, dot = true, miss = true, pet = true,
		shield = true, overheal = true },
	hideBlizzard = true,
	bgOn = true,
	bgArt = 0.5,
	minimapButton = true,
	minimapAngle = 220,
}

-- The profiles every account has; a profile is made from the defaults the first time it is used.
ns.PROFILES = { "Default", "Healer", "DPS", "Tank" }

-- How the Healer and DPS profiles start: only what differs from the defaults (Default and Tank start
-- plain). A font from SharedMedia that isn't installed falls back to the game's own.
ns.ROLE_DEFAULTS = {
	Healer = {
		route = {
			dmg = { plate = true, mine = true },
			heal = { plate = true, mine = true },
			healMe = { me = true, recv = true },
			dmgMe = { recv = false },
		},
		show = { shield = false },
		joinShields = false,
		font = "lsm:Blender Pro",
		boxes = {
			mine = { x = 354, y = -49, w = 230, h = 127, align = "right" },
			received = { x = -357, y = -51, w = 239, h = 132 },
		},
	},
	DPS = {
		route = {
			dmg = { plate = true, mine = true },
			heal = { plate = false },
			healMe = { mine = true, recv = true },
			dmgMe = { recv = false },
		},
		classColorFor = "normal",
		height = 50,
		duration = 1.6,
		font = "lsm:Blender Pro",
		boxes = {
			mine = { x = 360, y = -39, w = 241, h = 153, align = "right" },
			received = { x = -361, y = -39, w = 242, h = 156, merge = 3 },
		},
	},
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

local function deepCopy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = type(v) == "table" and deepCopy(v) or v end
	return c
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
-- the values they had are kept (account-wide: they are the game's settings) and put back when
-- RatBites stops.
local BLIZZARD_CVARS = { "CombatDamage", "PetMeleeDamage", "CombatHealing" }

function ns.ApplyBlizzardText()
	local db, root = ns.db, RatBitesDB
	if db.enabled and db.hideBlizzard then
		if not root.blizzSaved then
			root.blizzSaved = {}
			for _, cvar in ipairs(BLIZZARD_CVARS) do root.blizzSaved[cvar] = GetCVar(cvar) end
		end
		for _, cvar in ipairs(BLIZZARD_CVARS) do SetCVar(cvar, "0") end
	elseif root.blizzSaved then
		for cvar, value in pairs(root.blizzSaved) do SetCVar(cvar, value) end
		root.blizzSaved = nil
	end
end

-- Before the Where grid, a profile said where numbers go with "Show on" (anchor), "Heals with no
-- nameplate", the received checkboxes and "Shields from heals": read once into the grid.
local function UpgradeRoute(db)
	if db.anchor == nil and db.incoming == nil then return end
	local r = db.route
	local anchor = db.anchor or "plates"
	r.dmg.plate = anchor == "plates" or anchor == "both" or anchor == "dmgplates" or anchor == "target" or anchor == "screen"
	r.dmg.mine = anchor == "box" or anchor == "both" or anchor == "healsplates"
	r.heal.plate = anchor == "plates" or anchor == "both" or anchor == "healsplates" or anchor == "target" or anchor == "screen"
	r.heal.mine = anchor == "box" or anchor == "both" or anchor == "dmgplates"
	if db.show and db.show.heal == false then
		r.heal.plate, r.heal.mine = false, false
	end
	db.noPlateToBox = db.noPlateHeals ~= "hide"
	local inc = db.incoming or {}
	r.healMe.recv, r.healMe.me = inc.heals and true or false, (inc.heals and db.receivedFloat) and true or false
	r.dmgMe.recv, r.dmgMe.me = inc.damage and true or false, (inc.damage and db.receivedFloat) and true or false
	if db.healShields == "hide" then db.show.shield = false end
	db.joinShields = db.healShields ~= "line"
	db.anchor, db.noPlateHeals, db.incoming, db.receivedFloat, db.healShields, db.receivedOn = nil, nil, nil, nil, nil, nil
	if db.show then db.show.heal = nil end
end

-- Older settings, read into a profile: where numbers go (into the Where grid); box settings once
-- shared by both boxes; class colour once two checkboxes (normal hits win when both were on, so
-- crits keep standing out).
local function Upgrade(db)
	UpgradeRoute(db)
	for _, key in ipairs({ "mine", "received" }) do
		local b = db.boxes[key]
		if db.boxScroll then b.scroll = db.boxScroll end
		if db.boxAlign then b.align = db.boxAlign end
		if db.boxTime then b.time = db.boxTime end
		if db.boxMerge and key == "mine" then b.merge = db.boxMerge end
	end
	db.boxScroll, db.boxAlign, db.boxTime, db.boxMerge = nil, nil, nil, nil
	if db.classColor then
		db.classColorFor = "normal"
	elseif db.classCrit then
		db.classColorFor = "crit"
	end
	db.classColor, db.classCrit = nil, nil
end

--------------------------------------------------------------------------------
-- profiles: shared by the account; each character picks one, or one per talent spec
--------------------------------------------------------------------------------

-- A new (or reset) profile starts from its role's setup, then the defaults fill the rest.
local function Profile(name)
	local profiles = RatBitesDB.profiles
	profiles[name] = profiles[name] or deepCopy(ns.ROLE_DEFAULTS[name] or {})
	copyDefaults(ns.DEFAULTS, profiles[name])
	Upgrade(profiles[name])
	return profiles[name]
end

-- the profile this character uses now: its spec's one with dual spec on, else its own choice
function ns.ActiveProfile()
	local char = ns.char
	if char.dual then return char.spec[GetActiveTalentGroup() or 1] end
	return char.profile
end

-- every part of RatBites that shows a setting looks at it again
function ns.ProfileChanged()
	if ns.RefreshOptions then ns.RefreshOptions() end
	ns.ApplyBlizzardText()
	if ns.PlaceBoxes then ns.PlaceBoxes() end
	if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
	if ns.RefreshLegend then ns.RefreshLegend() end
end

function ns.UseProfile()
	local name = ns.ActiveProfile()
	if ns.db == RatBitesDB.profiles[name] then return end
	ns.db = Profile(name)
	ns.ProfileChanged()
end

-- the active profile's setting for this character (with dual spec on, for the spec in use)
function ns.SetProfile(name)
	local char = ns.char
	if char.dual then char.spec[GetActiveTalentGroup() or 1] = name else char.profile = name end
	ns.UseProfile()
end

-- both say in chat what they did: on the Profiles tab nothing else shows the change
function ns.CopyProfile(from)
	local name = ns.ActiveProfile()
	if from == name then
		ns.Print("You are already using " .. name .. ": pick another profile to copy from.")
		return
	end
	RatBitesDB.profiles[name] = deepCopy(Profile(from))
	ns.db = nil
	ns.UseProfile()
	ns.Print("Copied " .. from .. "'s settings into " .. name .. ".")
end

function ns.ResetProfile()
	local name = ns.ActiveProfile()
	RatBitesDB.profiles[name] = nil
	ns.db = nil
	ns.UseProfile()
	ns.Print(name .. " is back to the default settings.")
end

--------------------------------------------------------------------------------
-- sharing a profile as text: "RB1:" then the settings in a small format read back by our own parser
-- (never run as code), and only settings RatBites knows, of the right type, are kept
--   n<number>;   t / f (true / false)   s<length>:<text>   { key value ... }
--------------------------------------------------------------------------------

local SHARE_TAG = "RB1:"

local function Write(v, out)
	local kind = type(v)
	if kind == "number" then
		out[#out + 1] = "n" .. tostring(v) .. ";"
	elseif kind == "boolean" then
		out[#out + 1] = v and "t" or "f"
	elseif kind == "string" then
		out[#out + 1] = "s" .. #v .. ":" .. v
	elseif kind == "table" then
		out[#out + 1] = "{"
		for k, val in pairs(v) do
			Write(k, out)
			Write(val, out)
		end
		out[#out + 1] = "}"
	end
end

-- the value at s[i] and the index after it, or nil, nil when the text is not well formed
local function Read(s, i, depth)
	if depth > 8 then return nil, nil end
	local c = s:sub(i, i)
	if c == "n" then
		local j = s:find(";", i, true)
		local num = j and tonumber(s:sub(i + 1, j - 1))
		if not num then return nil, nil end
		return num, j + 1
	elseif c == "t" then
		return true, i + 1
	elseif c == "f" then
		return false, i + 1
	elseif c == "s" then
		local j = s:find(":", i, true)
		local len = j and tonumber(s:sub(i + 1, j - 1))
		if not len or len < 0 or j + len > #s then return nil, nil end
		return s:sub(j + 1, j + len), j + len + 1
	elseif c == "{" then
		local t = {}
		i = i + 1
		while s:sub(i, i) ~= "}" do
			if i > #s then return nil, nil end
			local k, v
			k, i = Read(s, i, depth + 1)
			if not i or (type(k) ~= "string" and type(k) ~= "number") then return nil, nil end
			v, i = Read(s, i, depth + 1)
			if not i then return nil, nil end
			t[k] = v
		end
		return t, i + 1
	end
	return nil, nil
end

-- only the settings the defaults have, each of the defaults' type; anything else falls back
local function Clean(src, def)
	local out = {}
	for k, dv in pairs(def) do
		local v = src[k]
		if type(dv) == "table" then
			out[k] = Clean(type(v) == "table" and v or {}, dv)
		elseif type(v) == type(dv) then
			out[k] = v
		else
			out[k] = dv
		end
	end
	return out
end

function ns.ExportProfile()
	local out = { SHARE_TAG }
	Write(Clean(ns.db, ns.DEFAULTS), out)
	return table.concat(out)
end

-- reads a shared text into the active profile; returns true, or false and why not
function ns.ImportProfile(text)
	text = strtrim(text or "")
	if text:sub(1, #SHARE_TAG) ~= SHARE_TAG then return false, "That isn't a RatBites profile." end
	local t, after = Read(text, #SHARE_TAG + 1, 0)
	if type(t) ~= "table" or after ~= #text + 1 then return false, "The profile text is cut or damaged." end
	RatBitesDB.profiles[ns.ActiveProfile()] = Clean(t, ns.DEFAULTS)
	ns.db = nil
	ns.UseProfile()
	return true
end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	RatBitesDB = RatBitesDB or {}
	local root = RatBitesDB
	-- settings from before profiles become the Default profile
	if not root.profiles then
		local old = {}
		for k, v in pairs(root) do
			if k ~= "blizzSaved" then old[k] = v; root[k] = nil end
		end
		root.profiles = { Default = old }
	end
	root.chars = root.chars or {}
	local key = UnitName("player") .. " - " .. GetRealmName()
	root.chars[key] = root.chars[key] or {}
	ns.char = root.chars[key]
	copyDefaults({ profile = "Default", dual = false, spec = { "Default", "Default" } }, ns.char)
	ns.db = Profile(ns.ActiveProfile())
end)

ns.On("PLAYER_LOGIN", function()
	ns.playerGUID = UnitGUID("player")
	-- the spec is known by now: with dual spec on, its profile may differ from the one loaded
	ns.UseProfile()
	ns.ApplyBlizzardText()
	ns.CreateOptions()
end)

ns.On("ACTIVE_TALENT_GROUP_CHANGED", function()
	if ns.char.dual then ns.UseProfile() end
	-- the Profiles tab marks the spec in use
	if ns.RefreshOptions then ns.RefreshOptions() end
end)

-- /rb is the game's Raid Browser
SLASH_RATBITES1 = "/bites"
SLASH_RATBITES2 = "/ratbites"
SlashCmdList.RATBITES = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "test" then
		ns.Test()
	elseif msg == "colors" or msg == "colours" then
		ns.ToggleLegend()
	elseif msg == "move" then
		ns.SetBoxesUnlocked(not ns.BoxesUnlocked())
	elseif msg == "last" then
		ns.PrintTrace()
	elseif msg == "plates" then
		ns.ReportPlates()
	else
		ns.OpenOptions()
	end
end
