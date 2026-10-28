local ADDON, ns = ...

-- 3.3.5a nameplates are unnamed children of WorldFrame and carry no GUID. A plate is known by its two
-- status bars (health and cast bar); its first font string holds the unit's name, the second its level.
-- A hit is matched to a plate by name. When several shown plates share that name, the target's plate
-- is the one the client draws at full alpha, and other mobs keep the plate they were last matched to.

local plates = {}     -- plate -> its name font string
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
		end
	end
	seen = count
end

-- the plate showing this unit, or nil when none can be told apart
function ns.PlateFor(guid, name)
	if not name then return nil end
	Scan()
	local only, count = nil, 0
	local isTarget = UnitExists("target") and UnitGUID("target") == guid
	local last = lastPlate[guid]
	local pick
	for f, text in pairs(plates) do
		if f:IsShown() and text:GetText() == name then
			count = count + 1
			only = f
			if isTarget and f:GetAlpha() > 0.99 then pick = f end
			if not pick and f == last then pick = f end
		end
	end
	if count == 1 then pick = only end
	if pick then lastPlate[guid] = pick end
	return pick
end

-- true while the plate still shows the unit it was matched to
function ns.PlateShows(plate, name)
	return plate:IsShown() and plates[plate] and plates[plate]:GetText() == name
end

-- a mob's GUID is gone for good once it dies
ns.On("COMBAT_LOG_EVENT_UNFILTERED", function(_, event, _, _, _, destGUID)
	if event == "UNIT_DIED" then lastPlate[destGUID] = nil end
end)
