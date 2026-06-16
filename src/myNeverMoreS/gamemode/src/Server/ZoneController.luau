--[=[
	@class ZoneController

	Mode-agnostic occupancy scan for a single zone part (the KOTH hill today, a
	CTF flag-stand or a control point tomorrow). Sibling of NpcController: the
	mode hands it a part, calls `Scan()` on its own cadence, and reads back the
	count of distinct LIVING combatants inside, grouped by team.

	Why a spatial query, not AdorneeBoundingBox: the hill is a part the map
	already authored, so its CFrame/Size are known — the question is "who is
	standing in it", which is a containment test (`GetPartBoundsInBox`), not the
	reactive bounding-box tracking AdorneeBoundingBox provides. (If the zone ever
	MOVES, observe its box reactively and feed each emission's CFrame/Size into
	the same query.)

	Team identity comes from the shared `resolveTeam` rule (Player/actor `.Team`,
	else the rig's `GameTeam` attribute), so players and bots are counted with no
	branching — teamless characters (dummies, pre-match players) resolve nil and
	are ignored. `Scan` throttles internally (KOTH_SCAN_INTERVAL) like
	TargetController.Scan gates VISION_SCAN_INTERVAL, so a mode ticking every
	Heartbeat is still cheap; between throttle windows the last counts are
	returned.

	The mode owns the *policy*: what "control" means (sole occupant vs.
	contested) and what scoring follows. This controller only reports occupancy.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)
local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)

local ZoneController = {}
ZoneController.__index = ZoneController

export type ZoneController = typeof(setmetatable(
	{} :: {
		_zone: BasePart,
		_params: OverlapParams,
		_interval: number,
		_lastScan: number,
		-- Distinct living combatants inside the zone, per team id; cached so a
		-- per-frame caller is throttled to KOTH_SCAN_INTERVAL.
		_lastCounts: { [gameModeTypes.TeamId]: number },
	},
	ZoneController
))

function ZoneController.new(zone: BasePart, interval: number?): ZoneController
	local self = setmetatable({}, ZoneController)

	self._zone = zone
	-- KOTH ticks at its own rate; CTF passes CTF_SCAN_INTERVAL. Same throttle.
	self._interval = interval or GameModeConstants.KOTH_SCAN_INTERVAL
	self._lastScan = 0
	self._lastCounts = {}

	-- Exclude the zone part itself; everything else (player rigs, NPC rigs)
	-- counts. Kept on the instance so the query allocates no params per scan.
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { zone }
	self._params = params

	return self :: ZoneController
end

function ZoneController.GetZone(self: ZoneController): BasePart
	return self._zone
end

--[=[
	Distinct living combatants inside the zone, grouped by team id. Throttled to
	KOTH_SCAN_INTERVAL — a call inside the window returns the cached counts, so a
	mode may call this every Heartbeat for free.
]=]
function ZoneController.Scan(self: ZoneController): { [gameModeTypes.TeamId]: number }
	local now = os.clock()
	if now - self._lastScan < self._interval then
		return self._lastCounts
	end
	self._lastScan = now

	local parts = Workspace:GetPartBoundsInBox(self._zone.CFrame, self._zone.Size, self._params)

	-- One body has many parts in the box; dedupe up to the character Model.
	local seen: { [Model]: true } = {}
	local counts: { [gameModeTypes.TeamId]: number } = {}

	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or seen[model] then
			continue
		end
		seen[model] = true

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		-- Same neutral rule as the damage check: a teamless body (dummy,
		-- pre-match player) resolves nil and never counts toward control.
		local team = resolveTeam(model, getCharacterActor(model) :: any)
		if team then
			counts[team.Name] = (counts[team.Name] or 0) + 1
		end
	end

	self._lastCounts = counts
	return counts
end

--[=[
	Living character Models inside the zone that carry `tag`. CTF reads it with
	the carrier tag to find flag-carriers standing in a home zone; unlike Scan
	this isn't throttled (the query shape differs and the caller already ticks on
	its own cadence). A teamless body still appears here if it holds the tag — the
	mode applies the team/eligibility rule on top.
]=]
function ZoneController.GetTaggedOccupants(self: ZoneController, tag: string): { Model }
	local parts = Workspace:GetPartBoundsInBox(self._zone.CFrame, self._zone.Size, self._params)

	local seen: { [Model]: true } = {}
	local result: { Model } = {}

	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or seen[model] then
			continue
		end
		seen[model] = true

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		if CollectionService:HasTag(model, tag) then
			table.insert(result, model)
		end
	end

	return result
end

--[=[
	Every living character Model inside the zone, untagged and ungrouped. KOTH
	reads it to credit per-player hill time (each occupant that resolves to a real
	player banks a tick). Like GetTaggedOccupants this isn't throttled — the
	caller (the KOTH tick) already runs on its own cadence.
]=]
function ZoneController.GetOccupants(self: ZoneController): { Model }
	local parts = Workspace:GetPartBoundsInBox(self._zone.CFrame, self._zone.Size, self._params)

	local seen: { [Model]: true } = {}
	local result: { Model } = {}

	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or seen[model] then
			continue
		end
		seen[model] = true

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		table.insert(result, model)
	end

	return result
end

function ZoneController.Destroy(self: ZoneController)
	-- Clear the controller readout so the hill stops showing an owner once the
	-- match tears down.
	self._zone:SetAttribute(GameModeConstants.KOTH_CONTROLLER_ATTRIBUTE, nil)
	self._lastCounts = {}
end

return ZoneController
