--[=[
	@class KingOfTheHill
	The "koth" strategy: two teams fight over one hill (a BasePart tagged
	KOTH_ZONE_TAG). A team that holds the hill ALONE banks KOTH_POINTS_PER_TICK
	every KOTH_TICK_INTERVAL; a contested hill (both teams present) or an empty
	one scores nothing. First team to the score cap (or the leader at time-up)
	wins — GameModeService owns that check, this class only reports the holder
	to `deps.addScore`.

	It extends TeamMode for everything team-vs-team that isn't the win condition
	(the NPC roster + balanced assignment), and delegates the actual occupancy
	test to ZoneController (sibling of NpcController). The hill itself is found by
	tag at Start; if the map has no tagged hill the mode still runs (bots, teams,
	respawns) but never scores — a loud warn, not a crash, so a misconfigured map
	is obvious in a playtest.

	The scoring tick is mode-owned (a Heartbeat accumulator in `_maid`), not a
	GameModeService hook: KOTH is the only time-driven mode so far, and keeping
	the cadence here avoids widening the strategy surface. ZoneController.Scan
	throttles itself, so ticking every frame is cheap.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local TeamMode = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.TeamMode)
local ZoneController = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.ZoneController)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)

local KingOfTheHill = setmetatable({}, { __index = TeamMode })
KingOfTheHill.__index = KingOfTheHill

function KingOfTheHill.new(config: gameModeTypes.ModeConfig)
	local self = setmetatable(TeamMode.new(config) :: any, KingOfTheHill)

	self._zone = nil -- ZoneController?, built at Start once the hill is found
	self._accum = 0 -- Heartbeat accumulator toward the next scoring tick

	return self
end

-- The first BasePart tagged KOTH_ZONE_TAG that's actually in the world.
function KingOfTheHill._findZone(_self): BasePart?
	for _, inst in CollectionService:GetTagged(GameModeConstants.KOTH_ZONE_TAG) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
			return inst
		end
	end
	return nil
end

-- Classic KOTH control: exactly one team inside controls; zero teams (empty) or
-- two-plus (contested) => nobody scores.
function KingOfTheHill._controllingTeam(_self, counts: { [gameModeTypes.TeamId]: number }): gameModeTypes.TeamId?
	local controller: gameModeTypes.TeamId? = nil
	local present = 0
	for teamId, count in counts do
		if count > 0 then
			present += 1
			controller = teamId
		end
	end
	return if present == 1 then controller else nil
end

function KingOfTheHill._tickControl(self)
	if not self._zone or not self._deps then
		return
	end

	local controller = self:_controllingTeam(self._zone:Scan())
	-- Expose the live holder so HUD/visuals can react ("" = contested/empty).
	self._zone:GetZone():SetAttribute(GameModeConstants.KOTH_CONTROLLER_ATTRIBUTE, controller or "")

	if controller then
		self._deps.addScore(controller, GameModeConstants.KOTH_POINTS_PER_TICK)
	end
end

function KingOfTheHill.Start(self, payload: gameModeTypes.MatchPayload)
	-- Roster + balanced team assignment first (TeamMode owns the bots).
	TeamMode.Start(self, payload)

	local zonePart = self:_findZone()
	if not zonePart then
		warn(`[KingOfTheHill] no BasePart tagged "{GameModeConstants.KOTH_ZONE_TAG}" — the hill will never score`)
		return
	end

	-- Maid-owned: TeamMode.Stop's DoCleaning destroys the zone (clearing its
	-- controller attribute) and disconnects the tick.
	self._zone = self._maid:Add(ZoneController.new(zonePart))

	self._maid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime)
		self._accum += deltaTime
		if self._accum < GameModeConstants.KOTH_TICK_INTERVAL then
			return
		end
		self._accum -= GameModeConstants.KOTH_TICK_INTERVAL
		self:_tickControl()
	end))
end

return KingOfTheHill
