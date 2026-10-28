local ADDON, ns = ...

-- Healers watch their raid frames, not nameplates, so your heals can show on the frame of the player
-- you healed: ElvUI, Grid, Blizzard's party frames or any other unit frame. Every frame with a "unit"
-- attribute for you, a party or a raid member is a candidate; buttons of a group header (the raid
-- and party frames) win over single frames such as the player frame.

local candidates = {}  -- frame -> 2 for a group header's button, 1 for any other unit frame
local dirty = true
local collectedAt = 0

local function GroupUnit(unit)
	return unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$")
end

local function Collect()
	wipe(candidates)
	local f = EnumerateFrames()
	while f do
		local unit = f.GetAttribute and f:GetAttribute("unit")
		if type(unit) == "string" and GroupUnit(unit) then
			local parent = f:GetParent()
			local header = parent and parent.GetAttribute
				and (parent:GetAttribute("showRaid") ~= nil or parent:GetAttribute("showParty") ~= nil)
			candidates[f] = header and 2 or 1
		end
		f = EnumerateFrames(f)
	end
	dirty = false
	collectedAt = GetTime()
end

-- group headers make their buttons as the group grows, so a roster change looks again
for _, event in ipairs({ "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
	ns.On(event, function() dirty = true end)
end

-- true while the frame is up and still shows that player (headers hand buttons to other players)
function ns.FrameShows(f, guid)
	if not f:IsVisible() then return false end
	local unit = f:GetAttribute("unit")
	return type(unit) == "string" and UnitGUID(unit) == guid
end

-- the unit frame showing this player, or nil
function ns.FrameFor(guid)
	if dirty then Collect() end
	local best, bestScore = nil, 0
	for f, score in pairs(candidates) do
		if score > bestScore and ns.FrameShows(f, guid) then
			best, bestScore = f, score
		end
	end
	-- a frame made since the last look: look once more, at most every 10 sec
	if not best and GetTime() - collectedAt > 10 then
		Collect()
		return ns.FrameFor(guid)
	end
	return best
end
