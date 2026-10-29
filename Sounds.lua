local ADDON, ns = ...

-- Crit sounds: a sound on your own crits, one bag per role.
--   heal crit       -> heal   (every class)
--   Hunter          -> gun with a gun in the ranged slot, else bow
--   tanking         -> tank   (every class)
--   any other crit  -> your class's DPS bag, named by class: deathknight, paladin, mage, ...
-- A list the pack doesn't have falls back to dps.
-- The sounds are in Sounds\<Class>\ folders; Sounds\List.lua (written by Sounds\Update sounds.bat,
-- since the game can't list a folder) sets the global RatBitesSounds:
--   RatBitesSounds = {
--     path = [[Interface\AddOns\RatBites\Sounds\]],
--     tank = { "Tank\\a.ogg", "Tank\\b.ogg" }, heal = { ... }, deathknight = { ... }, ...
--   }
-- A list with several files plays them all, in a shuffled order, before any of them repeats.
-- Timing: one sound per spell however many targets it crits (Divine Storm on four mobs is one
-- sound); a different spell critting in the same moment plays too, STAGGER later, so the two are
-- heard apart; at most two sounds per GAP seconds, so an AoE or a run of DoT crits never bursts.

local GAP, STAGGER = 0.5, 0.15
local lastFile = {}
local windowAt, windowCount, lastSpell = 0, 0, nil

function ns.SoundPack()
	local p = RatBitesSounds
	return type(p) == "table" and type(p.path) == "string" and p or nil
end

-- Volume: a game addon can't turn one sound down, so the pack carries quieter copies of every
-- sound (volumes = { 25, 50, 75 } -> v25\, v50\, v75\) and the setting picks one; 100 = the sound itself.
function ns.PackVolumes()
	local p = ns.SoundPack()
	return p and type(p.volumes) == "table" and #p.volumes > 0 and p.volumes or nil
end

function ns.VolumeFolder()
	local want, volumes = ns.app.critVolume or 100, ns.PackVolumes()
	if not volumes or want >= 100 then return "" end
	for _, v in ipairs(volumes) do
		if v == want then return "v" .. v .. "\\" end
	end
	return ""
end

-- the active shapeshift form's name (stances, presences, forms)
local function FormName()
	local i = GetShapeshiftForm()
	if not i or i == 0 then return nil end
	local _, name = GetShapeshiftFormInfo(i)
	return name
end

-- Tree with the most points (1-3).
local function MainTree()
	local best, bestPoints = 1, -1
	for i = 1, (GetNumTalentTabs() or 0) do
		local _, _, points = GetTalentTabInfo(i)
		if (points or 0) > bestPoints then best, bestPoints = i, points or 0 end
	end
	return best
end

-- Tanking right now: a Protection warrior or paladin (by talents: Righteous Fury alone isn't
-- tanking, a Ret or Holy paladin may have it on), Frost Presence, Bear / Dire Bear Form.
local function Tanking(class)
	if class == "WARRIOR" then return MainTree() == 3 end
	if class == "PALADIN" then return MainTree() == 2 end
	if class == "DEATHKNIGHT" then return FormName() == GetSpellInfo(48263) end -- Frost Presence
	if class == "DRUID" then
		local form = FormName()
		return form ~= nil and (form == GetSpellInfo(5487) or form == GetSpellInfo(9634)) -- Bear / Dire Bear
	end
	return false
end

-- "Guns" in the client's own language: the 4th weapon subclass of the auction house list.
local gunWord
local function HoldsGun()
	local link = GetInventoryItemLink("player", 18)
	if not link then return false end
	local subType = select(7, GetItemInfo(link))
	if not subType then return false end
	if not gunWord then gunWord = select(4, GetAuctionItemSubClasses(1)) or "Guns" end
	return subType == gunWord
end

local HEAL_KINDS = { heal = true, overheal = true }

-- which list of the pack this crit uses; while "Test as" names a class, your real crits use its bag
-- too, so a class's sounds can be heard on your own hits (heals keep the heal bag)
function ns.CritRole(kind)
	if HEAL_KINDS[kind] then return "heal" end
	if ns.preview then return ns.preview.role end
	local class = select(2, UnitClass("player"))
	if class == "HUNTER" then return HoldsGun() and "gun" or "bow" end
	if Tanking(class) then return "tank" end
	return strlower(class)
end

-- A shuffle bag per list: every variant plays once before any plays again (Fisher-Yates shuffle),
-- and a refilled bag never starts with the one that just played.
local bags = {}
local function Pick(role, list)
	if #list == 1 then return list[1] end
	local bag = bags[role]
	if not bag or #bag == 0 then
		bag = {}
		for i, f in ipairs(list) do bag[i] = f end
		for i = #bag, 2, -1 do
			local j = math.random(i)
			bag[i], bag[j] = bag[j], bag[i]
		end
		if bag[#bag] == lastFile[role] then bag[1], bag[#bag] = bag[#bag], bag[1] end
		bags[role] = bag
	end
	return table.remove(bag)
end

-- plays a list of the pack, or its dps list when it lacks that one; the file played, or nil
local function Play(role)
	local pack = ns.SoundPack()
	if not pack then return nil end
	local list = pack[role]
	if type(list) ~= "table" or #list == 0 then list, role = pack.dps, "dps" end
	if type(list) ~= "table" or #list == 0 then return nil end
	local file = Pick(role, list)
	lastFile[role] = file
	PlaySoundFile(pack.path .. ns.VolumeFolder() .. file)
	return file
end

-- the second sound of a window waits STAGGER after the first
local later = CreateFrame("Frame")
later:Hide()
later:SetScript("OnUpdate", function(self, elapsed)
	self.wait = self.wait - elapsed
	if self.wait <= 0 then
		self:Hide()
		Play(self.role)
	end
end)

-- from the combat log: one of your own crits landed; spell: its name ("melee" for swings)
function ns.CritSound(kind, spell)
	if not ns.app.critSounds then return end
	local now = GetTime()
	if now - windowAt >= GAP then
		windowAt, windowCount, lastSpell = now, 1, spell
		Play(ns.CritRole(kind))
		return
	end
	if spell == lastSpell or windowCount >= 2 then return end
	windowCount, lastSpell = windowCount + 1, spell
	later.role, later.wait = ns.CritRole(kind), math.max(0, windowAt + STAGGER - now)
	later:Show()
end

-- the test plays a role's sound whatever the setting, so you can hear it
function ns.PlayRole(role) return Play(role) end

-- "Test as": every class with the roles it can play. ns.preview is for this session only.
local LABEL = { tank = "Tank", heal = "Healer", dps = "DPS", bow = "Bow", gun = "Gun" }
local CLASSES = {
	{ "DEATHKNIGHT", "tank", "dps" }, { "DRUID", "tank", "heal", "dps" }, { "HUNTER", "bow", "gun" },
	{ "MAGE", "dps" }, { "PALADIN", "tank", "heal", "dps" }, { "PRIEST", "heal", "dps" }, { "ROGUE", "dps" },
	{ "SHAMAN", "heal", "dps" }, { "WARLOCK", "dps" }, { "WARRIOR", "tank", "dps" },
}

function ns.PreviewValues()
	local out = { { "", "Test as me" } }
	for _, c in ipairs(CLASSES) do
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c[1]] or c[1]
		local color = RAID_CLASS_COLORS[c[1]]
		local hex = color and format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255) or ""
		for i = 2, #c do
			out[#out + 1] = { c[1] .. ":" .. c[i], hex .. name .. "|r · " .. LABEL[c[i]] }
		end
	end
	return out
end

function ns.PreviewKey() return ns.preview and ns.preview.key or "" end

function ns.SetPreview(key)
	local class, role = strsplit(":", key or "")
	if role == "dps" then role = strlower(class) end
	ns.preview = role and { key = key, class = class, role = role } or nil
end

-- /bites sound: one of each list, a second apart
function ns.TestSounds()
	if not ns.SoundPack() then
		ns.Print("no crit sounds: Sounds\\List.lua is missing (run Sounds\\Update sounds.bat).")
		return
	end
	local roles = { "tank", "heal", "deathknight", "druid", "mage", "paladin", "priest", "rogue", "shaman", "warlock",
		"warrior", "bow", "gun" }
	local i, wait = 0, 0
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		i = i + 1
		local role = roles[i]
		if not role then self:SetScript("OnUpdate", nil); return end
		local file = Play(role)
		ns.Print(role .. ": " .. (file or "|cff8a8d93none|r"))
		wait = file and 1.2 or 0
	end)
end
