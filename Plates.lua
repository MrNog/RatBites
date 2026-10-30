local ADDON, ns = ...

-- 3.3.5a nameplates are unnamed children of WorldFrame and carry no GUID. A plate is known by its two
-- status bars (health and cast bar); its first font string holds the unit's name, the second its level.
-- A hit is matched to a plate by name. When several shown plates share that name, the target's plate
-- is the one the client draws at full alpha, and other mobs keep the plate they were last matched to.

local plates = {}     -- plate -> its name font string
local highlights = {} -- plate -> the glow the client shows on it while the unit is under the mouse
local seen = 0        -- WorldFrame children already looked at
local lastPlate = {}  -- GUID -> plate it was last matched to

local function IsPlate(f)
	if f:GetName() or f:GetObjectType() ~= "Frame" then return false end
	local health, cast = f:GetChildren()
	return health and cast and health:GetObjectType() == "StatusBar" and cast:GetObjectType() == "StatusBar"
end

local function NameText(f)
	for i = 1, select("#", f:GetRegions()) do
		local region = select(i, f:GetRegions())
		if region:GetObjectType() == "FontString" then return region end
	end
end

-- plates are created as they first come into view and reused after that, so only new children are read
local function Scan()
	local count = WorldFrame:GetNumChildren()
	if count == seen then return end
	local children = { WorldFrame:GetChildren() }
	for i = seen + 1, count do
		local f = children[i]
		if f and IsPlate(f) then
			local name = NameText(f)
			if name then plates[f] = name end
			-- the sixth region: threat glow, border, cast border, shield, spell icon, highlight
			local glow = select(6, f:GetRegions())
			if glow and glow:GetObjectType() == "Texture" then highlights[f] = glow end
		end
	end
	seen = count
end

-- ElvUI draws its own plate on top (plate.UnitFrame) and holds every plate at full alpha, so its own
-- target flag is read instead
local function IsTargetPlate(f)
	if f.UnitFrame then return f.UnitFrame.isTarget end
	return f:GetAlpha() > 0.99
end

-- plates show a player's name without the realm the combat log may add ("Name-Realm")
local function Bare(name)
	return name and (name:match("^([^%-]+)%-") or name)
end

-- An AoE lands on many plates in one frame, so the shown plates are listed by name once per frame
-- (GetTime holds still within a frame) instead of every plate being read for every hit. The lists
-- are reused from frame to frame.
local byName, spare, builtAt = {}, {}, nil
local function Index()
	local now = GetTime()
	if builtAt == now then return end
	builtAt = now
	Scan()
	for n, list in pairs(byName) do
		wipe(list)
		spare[#spare + 1] = list
		byName[n] = nil
	end
	for f, text in pairs(plates) do
		if f:IsShown() then
			local n = text:GetText()
			if n then
				local list = byName[n]
				if not list then
					list = table.remove(spare) or {}
					byName[n] = list
				end
				list[#list + 1] = f
			end
		end
	end
end

-- the plate showing this unit, or nil when none can be told apart
function ns.PlateFor(guid, name)
	name = Bare(name)
	if not name then return nil end
	Index()
	local list = byName[name]
	if not list then return nil end
	if #list == 1 then
		lastPlate[guid] = list[1]
		return list[1]
	end
	local isTarget = UnitExists("target") and UnitGUID("target") == guid
	local last = lastPlate[guid]
	local pick
	for _, f in ipairs(list) do
		if isTarget and IsTargetPlate(f) then pick = f end
		if not pick and f == last then pick = f end
	end
	if pick then lastPlate[guid] = pick end
	return pick
end

-- Mobs sharing a name ("Dummy") can't be told apart by it, so a mob's plate is learned when you
-- target it (its plate is drawn apart) or put the mouse on it (its plate lights up). The client
-- updates the plates a moment after the event, so they are read on the next frame.
local learn = CreateFrame("Frame")
learn:Hide()
local pending = {}  -- "target" / "mouseover" -> true
learn:SetScript("OnUpdate", function(self)
	self:Hide()
	Scan()
	for unit in pairs(pending) do
		local guid, name = UnitGUID(unit), UnitName(unit)
		if guid and name then
			for f, text in pairs(plates) do
				if f:IsShown() and text:GetText() == name then
					local lit
					if unit == "target" then
						lit = IsTargetPlate(f)
					else
						lit = highlights[f] and highlights[f]:IsShown()
					end
					if lit then
						lastPlate[guid] = f
						break
					end
				end
			end
		end
	end
	wipe(pending)
end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() pending.mouseover = true; learn:Show() end)
ns.On("PLAYER_TARGET_CHANGED", function() pending.target = true; learn:Show() end)
-- every mob you hit is remembered for its fight only: a raid night's trash would otherwise pile up
ns.On("PLAYER_REGEN_ENABLED", function() wipe(lastPlate) end)

-- true while the plate still shows the unit it was matched to
function ns.PlateShows(plate, name)
	return plate:IsShown() and plates[plate] and plates[plate]:GetText() == Bare(name)
end

-- /bites plates: what RatBites sees, to tell a plate it can't find from a name that doesn't match
function ns.ReportPlates()
	Scan()
	local total, names = 0, {}
	for f, text in pairs(plates) do
		total = total + 1
		if f:IsShown() then names[#names + 1] = tostring(text:GetText()) end
	end
	ns.Print(format("%d WorldFrame children, %d plates found, %d shown: %s", WorldFrame:GetNumChildren(),
		total, #names, table.concat(names, ", ")))
	if ns.lastDest then
		ns.Print(format("last number went to \"%s\" (%s)", ns.lastDest, ns.lastDestPlate and "on its plate" or "no plate"))
	end
end

-- a mob's GUID is gone for good once it dies
ns.On("COMBAT_LOG_EVENT_UNFILTERED", function(_, event, _, _, _, destGUID)
	if event == "UNIT_DIED" then lastPlate[destGUID] = nil end
end)
