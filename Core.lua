local ADDON, ns = ...

-- One profile's settings. ns.db is the active profile.
-- route: the two Where grids. What you do: rows dmg (your damage) and heal (your heals on others), each
-- ticking plate (over their nameplate), me (over your character) and mine (Output box). What lands on
-- you: rows healMe, dmgMe and powerMe (mana, rage, energy, runic power), each ticking me and recv
-- (Input box).
-- noPlateToBox: a number wanted over a nameplate that isn't on screen goes to My box instead
-- joinShields: a shield your heal makes (Val'anyr, Divine Aegis) joins that heal's number
-- animation, healAnimation: how damage and heals move, on plates and over you: "arc", "rise" or "stay"
-- (Bites.lua's Plan)
-- critStyle: "pop" = starts large and settles, "big" = larger
-- numbers: "short" = 12.4k, "full" = 12,431
ns.DEFAULTS = {
	route = {
		dmg = { plate = true, me = false, mine = false },
		heal = { plate = true, me = false, mine = false },
		healMe = { me = false, recv = true },
		dmgMe = { me = false, recv = true },
		powerMe = { me = false, recv = false },
	},
	noPlateToBox = true,
	joinShields = true,
	animation = "arc",
	healAnimation = "arc",
	duration = 1.5,
	-- each box: text size (scale, on top of the Look page's), style ("scroll" = a list of lines;
	-- "arc", "rise" or "stay" = numbers float out of it like on plates; "pop" = every hit lands like a
	-- crit, then rises), its spot and size, where new lines come in ("up" = at the bottom), text
	-- alignment, merge (sec: the same spell again within this joins its line as a total with "xN"; 0 = off) and
	-- how long a line stays (sec)
	boxes = {
		mine = { scale = 1, style = "scroll", x = 300, y = -60, w = 200, h = 220, scroll = "up", align = "left", merge = 3, time = 5 },
		received = { scale = 1, style = "scroll", x = -300, y = -60, w = 200, h = 220, scroll = "up", align = "left", merge = 0,
			time = 5 },
	},
	scale = 1,
	align = "center",  -- floating numbers: "center", "left" (icons in one column) or "right"
	font = "lsm:Blender Pro",
	icons = true,
	-- the Spells page, by spell name: true = not on plates and over you (noPlates) or not in the
	-- boxes (noBoxes); both = hidden
	noPlates = {},
	noBoxes = {},
	classColorFor = "off",  -- "normal" = your normal damage in your class colour
	critStyle = "pop",
	critSize = 5,  -- a crit (Pop or Bigger) against a normal hit
	numbers = "short",
	show = { normal = true, crit = true, swing = true, spell = true, dot = true, miss = true, pet = true,
		shield = true, overheal = true },
}

-- The app's own settings: one set for the account, whatever profile is in use.
ns.APP_DEFAULTS = {
	enabled = true,
	hideBlizzard = true,
	bgOn = true,
	minimapButton = true,
	minimapAngle = 220,
}

-- The presets Copy from offers: only what differs from the defaults (the Tank preset is the defaults).
-- A font from SharedMedia that isn't installed falls back to the game's own.
ns.PRESETS = { "Healer", "DPS", "Tank" }
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
			healMe = { recv = true },
			dmgMe = { recv = false },
		},
		classColorFor = "normal",
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
	local app, root = ns.app, RatBitesDB
	if app.enabled and app.hideBlizzard then
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
	-- a spell unticked when the Spells page had one tick per spell stays hidden everywhere
	if db.hideSpells then
		for name in pairs(db.hideSpells) do db.noPlates[name], db.noBoxes[name] = true, true end
		db.hideSpells = nil
	end
	-- the grids lost the places that meant the same as another: over the nameplate of what lands on
	-- you is over you, and each side has its own box
	local r = db.route
	for _, key in ipairs({ "healMe", "dmgMe" }) do
		if r[key].plate then r[key].me = true end
		if r[key].mine then r[key].recv = true end
		r[key].plate, r[key].mine = nil, nil
	end
	for _, key in ipairs({ "dmg", "heal" }) do
		if r[key].recv then r[key].mine = true end
		r[key].recv = nil
	end
	-- settings cut for good: big hits in gold, icon size, travel distance, the spells filter (the
	-- Spells page does it); the app's settings moved out of the profiles
	db.bigGold, db.iconScale, db.height = nil, nil, nil
	db.show.spell = true
	db.enabled, db.hideBlizzard, db.bgOn, db.minimapButton, db.minimapAngle = nil, nil, nil, nil, nil
	-- the Spells tab lists the spellbook only: spells once collected from the combat log go
	db.seen, db.seenClean = nil, nil
	-- settings made simpler: each old choice to the nearest one left
	if db.animation == "fountain" or db.animation == "fall" then db.animation = "arc" end
	if db.numbers == "raw" then db.numbers = "full" end
	if db.critStyle == "plain" then db.critStyle = "big" end
	if db.classColorFor == "crit" then db.classColorFor = "normal" end
	for _, b in pairs(db.boxes or {}) do
		if b.merge and b.merge ~= 0 then b.merge = 1 end
	end
	db.spread, db.bgArt = nil, nil
	-- the Font list holds only the fonts big crits have images for: one picked before goes to Blender Pro
	local font = db.font and db.font:match("^lsm:(.+)")
	if not (font and ns.CRIT_GLYPHS[font]) then db.font = "lsm:Blender Pro" end
	-- crits went from 2.7x to 5x by default: a profile still on the old default follows, once
	-- heals got their own animation: they start as damage moves
	if not db.healAnimSet then
		db.healAnimation = db.animation
		db.healAnimSet = true
	end
	if not db.critSizeSet then
		if db.critSize == 2.7 then db.critSize = 5 end
		db.critSizeSet = true
	end
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
-- profiles: shared by the account; any character uses any of them, with another one for its second
-- spec if it likes
--------------------------------------------------------------------------------

-- A profile is made from the defaults the first time it is used.
local function Profile(name)
	local profiles = RatBitesDB.profiles
	profiles[name] = profiles[name] or {}
	copyDefaults(ns.DEFAULTS, profiles[name])
	Upgrade(profiles[name])
	return profiles[name]
end

-- every profile's name, Default first, the rest by name
function ns.ProfileNames()
	local names = {}
	for name in pairs(RatBitesDB.profiles) do
		if name ~= "Default" then names[#names + 1] = name end
	end
	table.sort(names)
	table.insert(names, 1, "Default")
	return names
end

-- the profile this character uses now: its second spec's one while in that spec, else its own
function ns.ActiveProfile()
	local char = ns.char
	if char.second and (GetActiveTalentGroup() or 1) == 2 then return char.second end
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

-- this character's profile (spec "second": the one for its second spec, nil = the same)
function ns.SetProfile(name, spec)
	if spec == "second" then ns.char.second = name else ns.char.profile = name end
	ns.UseProfile()
end

-- a new profile from the defaults, used from now on in the spec you are in; false and why when it can't
function ns.CreateProfile(name)
	name = strtrim(name or "")
	if name == "" then return false, "Type a name first." end
	if RatBitesDB.profiles[name] then return false, name .. " already exists." end
	Profile(name)
	local char = ns.char
	if char.second and (GetActiveTalentGroup() or 1) == 2 then char.second = name else char.profile = name end
	ns.UseProfile()
	return true
end

-- a profile no character uses any more goes; the characters on it go to Default
function ns.DeleteProfile(name)
	if name == "Default" or not RatBitesDB.profiles[name] then return end
	RatBitesDB.profiles[name] = nil
	for _, char in pairs(RatBitesDB.chars) do
		if char.profile == name then char.profile = "Default" end
		if char.second == name then char.second = nil end
	end
	ns.db = nil
	ns.UseProfile()
	ns.Print(name .. " is deleted.")
end

-- copies another profile, or a preset ("preset:Healer"), into the one in use; says in chat what it did
function ns.CopyProfile(from)
	local name = ns.ActiveProfile()
	local preset = from:match("^preset:(.+)")
	local copy
	if preset then
		copy = deepCopy(ns.ROLE_DEFAULTS[preset] or {})
		copyDefaults(ns.DEFAULTS, copy)
	else
		if from == name then
			ns.Print("You are already using " .. name .. ": pick another profile to copy from.")
			return
		end
		copy = deepCopy(Profile(from))
	end
	RatBitesDB.profiles[name] = copy
	ns.db = nil
	ns.UseProfile()
	ns.Print("Copied " .. (preset and preset .. " preset" or from) .. " into " .. name .. ".")
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
	-- the app's settings, once in each profile, start from the Default profile's
	if not root.app then
		root.app = {}
		for k in pairs(ns.APP_DEFAULTS) do root.app[k] = root.profiles.Default and root.profiles.Default[k] end
	end
	copyDefaults(ns.APP_DEFAULTS, root.app)
	ns.app = root.app
	root.chars = root.chars or {}
	local key = UnitName("player") .. " - " .. GetRealmName()
	root.chars[key] = root.chars[key] or {}
	local char = root.chars[key]
	ns.char = char
	-- "switch with my talents" was a tick and a profile for each spec
	if char.dual ~= nil then
		if char.dual and char.spec then
			char.profile = char.spec[1]
			if char.spec[2] ~= char.spec[1] then char.second = char.spec[2] end
		end
		char.dual, char.spec = nil, nil
	end
	copyDefaults({ profile = "Default", seen = {} }, char)
	ns.db = Profile(ns.ActiveProfile())
end)

ns.On("PLAYER_LOGIN", function()
	ns.playerGUID = UnitGUID("player")
	-- the spec is known by now: in the second spec, its profile may differ from the one loaded
	ns.UseProfile()
	ns.ApplyBlizzardText()
end)

ns.On("ACTIVE_TALENT_GROUP_CHANGED", function()
	if ns.char.second then ns.UseProfile() end
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
	elseif msg == "font" then
		ns.ReportFont()
	elseif msg == "plates" then
		ns.ReportPlates()
	else
		ns.OpenOptions()
	end
end
