--[=[
	@class TeamMode
	Base for team-vs-team modes (TeamDeathmatch, KingOfTheHill). Owns the shared
	team-vs-team bookkeeping so a concrete mode only writes its *win condition*:

	  * the NPC roster (NpcController): adopt pre-placed `NPC` rigs at Start,
	    spawn the payload bots, same-team respawn on death, despawn on Stop;
	  * balanced assignment — every player and bot joins the team with the
	    smallest TOTAL head count (real players plus living bots), so a lopsided
	    human split is evened out by where the bots land.

	Subclasses supply the scoring on top of this: TeamDeathmatch maps enemy
	kills to points (`onKill`), KingOfTheHill banks points for the team holding
	the zone (a Heartbeat tick). A subclass that needs extra Start/Stop work
	overrides them and CHAINS the TeamMode method (`TeamMode.Start(self, ...)`),
	so the roster lifecycle is never skipped.

	This is the same context/strategy split as the rest of the project: the
	long-lived bookkeeping (NpcController, team balance) lives here once, the
	thin per-mode behavior sits in the leaf classes.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local BaseMode = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.BaseMode)
local NpcController = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.NpcController)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)

local TeamMode = setmetatable({}, { __index = BaseMode })
TeamMode.__index = TeamMode

export type TeamMode = typeof(setmetatable(
	{} :: {
		_npc: any,
	},
	TeamMode
)) & BaseMode.BaseMode

function TeamMode.new(config: gameModeTypes.ModeConfig): TeamMode
	local self = setmetatable(BaseMode.new(config) :: any, TeamMode)

	-- Shared NPC roster: respawn gate reads _deps lazily (nil until Init).
	self._npc = NpcController.new(config.teams, function()
		return self._deps ~= nil and self._deps.getScoreState().phase == "active"
	end)

	return self :: TeamMode
end

-- Total head count per team id: real players (Team instances were created from
-- config.teams by GameModeService before Start) plus registered bots.
-- NpcController keeps a dead bot's count until its same-team replacement spawns,
-- so the totals stay stable across the respawn delay.
function TeamMode._teamTotals(self: TeamMode): { [gameModeTypes.TeamId]: number }
	local totals = {}
	for _, spec in self.config.teams :: { gameModeTypes.TeamSpec } do
		local team = Teams:FindFirstChild(spec.id) :: Team?
		totals[spec.id] = team and #team:GetPlayers() or 0
	end
	for teamId, count in self._npc:GetTeamCounts() do
		if totals[teamId] then
			totals[teamId] += count
		end
	end
	return totals
end

-- Smallest-total team id; config spec order breaks ties so the first team fills
-- first on an even field.
function TeamMode._smallestTeamId(self: TeamMode, totals: { [gameModeTypes.TeamId]: number }): gameModeTypes.TeamId?
	local best: gameModeTypes.TeamId? = nil
	local bestCount = math.huge
	for _, spec in self.config.teams :: { gameModeTypes.TeamSpec } do
		local count = totals[spec.id]
		if count and count < bestCount then
			best, bestCount = spec.id, count
		end
	end
	return best
end

function TeamMode.onPlayerAdded(self: TeamMode, player: Player)
	-- Idempotent: already on one of this mode's teams => leave them there.
	if player.Team and player.Team.Parent == Teams then
		for _, spec in self.config.teams :: { gameModeTypes.TeamSpec } do
			if player.Team.Name == spec.id then
				return
			end
		end
	end

	local teamId = self:_smallestTeamId(self:_teamTotals())
	local team = teamId and Teams:FindFirstChild(teamId) :: Team?
	if team then
		player.Team = team
		player.Neutral = false
	end
end

function TeamMode.Start(self: TeamMode, payload: gameModeTypes.MatchPayload)
	-- Adopt pre-placed rigs first: NPC-tagged map rigs that no spawner owns join
	-- the smallest team, so the payload bots below balance around them. From
	-- here on they are mode-owned like any spawned bot (NpcController: same-team
	-- respawn on death, despawned by Stop).
	self._npc:AdoptPrePlaced(function()
		return self:_smallestTeamId(self:_teamTotals())
	end)

	local botCount = payload.botCount or 0
	if botCount <= 0 then
		return
	end

	-- Each bot goes to the smallest TOTAL (players + bots assigned so far), so
	-- the sides come out even around however the humans landed.
	local teamIds = {}
	local totals = self:_teamTotals()
	for index = 1, botCount do
		local teamId = self:_smallestTeamId(totals)
		if not teamId then
			break
		end
		teamIds[index] = teamId
		totals[teamId] += 1
	end
	if #teamIds == 0 then
		return
	end

	self._npc:Spawn(#teamIds, teamIds)
end

function TeamMode.Stop(self: TeamMode)
	self._maid:DoCleaning()
	-- Despawn mode-owned bots so NPC brains stop shooting during the end screen.
	self._npc:DespawnAll()
end

return TeamMode
