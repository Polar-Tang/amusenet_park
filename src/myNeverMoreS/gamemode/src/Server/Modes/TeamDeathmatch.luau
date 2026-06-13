--[=[
	@class TeamDeathmatch
	The "tdm" strategy: two teams, a kill on an enemy scores the attacker's
	team one point. GameModeService already created the Team instances, runs
	the timer/score-cap win checks and replicates ScoreState — this class only
	maps events to `deps.addScore` and keeps both teams populated:

	  * every assignment (players and bots) goes to the team with the smallest
	    TOTAL head count — real players plus living bots — so a 1-player,
	    4-bot match comes out 1+2 vs 0+3, not 1+2 vs 2 (idempotent for
	    players: onPlayerAdded fires from both the match-start sweep and
	    PlayerAdded);
	  * pre-placed `NPC`-tagged rigs already in the map are adopted into the
	    match at Start (GameTeam attribute + registration), before payload
	    bots spawn, so the bots balance around them; an adopted rig that dies
	    respawns as an `NPC_models` template, and Stop despawns adopted rigs
	    along with mode bots;
	  * each registered rig carries its team in the replicated `GameTeam`
	    attribute (NpcSpawner pre-tag, or the adoption sweep) AND on its
	    server-side fake actor, so the whole hit pipeline (which only reads
	    Player-shaped `.Team`/`.Neutral`) sees the team without branching,
	    plus a team-colored Highlight so players can read bot allegiance;
	  * dead bots are replaced on the same team after NPC_RESPAWN_DELAY, so a
	    bot match doesn't decay to empty teams.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local BaseMode = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.BaseMode)
local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)
local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)

local NpcSpawner = require(ServerScriptService.Server.NPC.NpcSpawner)

local TeamDeathmatch = setmetatable({}, { __index = BaseMode })
TeamDeathmatch.__index = TeamDeathmatch

function TeamDeathmatch.new(config: gameModeTypes.ModeConfig)
	local self = setmetatable(BaseMode.new(config) :: any, TeamDeathmatch)

	-- rig Model -> TeamId, for same-team respawn and Stop teardown.
	self._npcTeams = {} :: { [Model]: gameModeTypes.TeamId }

	return self
end

-- Total head count per team id: real players (Team instances were created
-- from config.teams by GameModeService before Start) plus registered bots.
-- _npcTeams keeps a dead bot's entry until its same-team replacement spawns,
-- so the totals stay stable across the respawn delay.
function TeamDeathmatch._teamTotals(self): { [gameModeTypes.TeamId]: number }
	local totals = {}
	for _, spec in self.config.teams :: { gameModeTypes.TeamSpec } do
		local team = Teams:FindFirstChild(spec.id) :: Team?
		totals[spec.id] = team and #team:GetPlayers() or 0
	end
	for _, teamId in pairs(self._npcTeams) do
		if totals[teamId] then
			totals[teamId] += 1
		end
	end
	return totals
end

-- Smallest-total team id; config spec order breaks ties so the first team
-- fills first on an even field.
function TeamDeathmatch._smallestTeamId(self, totals: { [gameModeTypes.TeamId]: number }): gameModeTypes.TeamId?
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

function TeamDeathmatch.onPlayerAdded(self, player: Player)
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

--[=[
	Adopts a rig into the match: marks its server-side fake actor with the
	team (the rig's replicated `GameTeam` attribute was already set — by
	NpcSpawner pre-tag for payload bots, by the Start sweep for pre-placed
	rigs), outlines it in the team color, and arms the same-team respawn on
	death. `Humanoid.Died` is used instead of the kill signal because it also
	covers deaths EffectService never sees (falls, despawn damage).
]=]
function TeamDeathmatch._registerNpc(self, rig: Model, teamId: gameModeTypes.TeamId)
	local actor = getCharacterActor(rig) :: any
	actor.Team = Teams:FindFirstChild(teamId)
	actor.Neutral = false
	self._npcTeams[rig] = teamId

	-- Friend-or-foe readability: outline the rig in its team color (players
	-- have the playerlist/team color, bots have nothing else visible).
	for _, spec in self.config.teams :: { gameModeTypes.TeamSpec } do
		if spec.id == teamId then
			local highlight = Instance.new("Highlight")
			highlight.Name = "TeamHighlight"
			highlight.FillTransparency = 1
			highlight.OutlineColor = spec.color.Color
			highlight.Parent = rig
			break
		end
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	self._maid[rig] = humanoid.Died:Connect(function()
		self._maid[rig] = nil
		task.delay(GameModeConstants.NPC_RESPAWN_DELAY, function()
			self:_respawnNpc(rig, teamId)
		end)
	end)
end

function TeamDeathmatch._despawnNpc(self, rig: Model)
	self._maid[rig] = nil
	self._npcTeams[rig] = nil
	-- Untag first so the NPC binders run their Destroy before the rig dies.
	CollectionService:RemoveTag(rig, Constants.NPC_TAG)
	rig:Destroy()
end

function TeamDeathmatch._respawnNpc(self, deadRig: Model, teamId: gameModeTypes.TeamId)
	if not self._deps or self._deps.getScoreState().phase ~= "active" then
		return
	end
	if self._npcTeams[deadRig] then
		self:_despawnNpc(deadRig)
	end

	local spawned = NpcSpawner.Spawn(1, { teamId })
	self:_registerNpc(spawned[1], teamId)
end

function TeamDeathmatch.Start(self, payload: gameModeTypes.MatchPayload)
	-- Adopt pre-placed rigs first: NPC-tagged map rigs that no spawner owns
	-- (no GameTeam attribute) join the smallest team, so the payload bots
	-- below balance around them. From here on they are mode-owned like any
	-- spawned bot: same-team template respawn on death, despawned by Stop.
	for _, rig in CollectionService:GetTagged(Constants.NPC_TAG) do
		if
			rig:IsA("Model")
			and rig:IsDescendantOf(Workspace)
			and not self._npcTeams[rig]
			and rig:GetAttribute(GameModeConstants.TEAM_ATTRIBUTE) == nil
		then
			local teamId = self:_smallestTeamId(self:_teamTotals())
			if teamId then
				rig:SetAttribute(GameModeConstants.TEAM_ATTRIBUTE, teamId)
				self:_registerNpc(rig, teamId)
			end
		end
	end

	local botCount = payload.botCount or 0
	if botCount <= 0 then
		return
	end

	-- Each bot goes to the smallest TOTAL (players + bots assigned so far),
	-- so the sides come out even around however the humans landed.
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

	local rigs = NpcSpawner.Spawn(#teamIds, teamIds)
	for index, rig in rigs do
		self:_registerNpc(rig, teamIds[index])
	end
end

function TeamDeathmatch.onKill(self, attackerChar: Model, defenderChar: Model)
	if attackerChar == defenderChar then
		return
	end

	local attackerTeam = resolveTeam(attackerChar, getCharacterActor(attackerChar))
	local defenderTeam = resolveTeam(defenderChar, getCharacterActor(defenderChar))
	-- Only enemy kills score: teamless victims (dummies) and friendly fire
	-- feed nothing.
	if not attackerTeam or not defenderTeam or attackerTeam == defenderTeam then
		return
	end

	self._deps.addScore(attackerTeam.Name, 1)
end

function TeamDeathmatch.Stop(self)
	self._maid:DoCleaning()
	-- Despawn mode-owned bots so NPC brains stop shooting during the end
	-- screen (untag runs the binder Destroy chain).
	for rig in pairs(self._npcTeams) do
		CollectionService:RemoveTag(rig, Constants.NPC_TAG)
		rig:Destroy()
	end
	table.clear(self._npcTeams)
end

return TeamDeathmatch
