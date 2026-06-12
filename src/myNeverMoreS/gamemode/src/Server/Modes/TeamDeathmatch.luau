--[=[
	@class TeamDeathmatch
	The "tdm" strategy: two teams, a kill on an enemy scores the attacker's
	team one point. GameModeService already created the Team instances, runs
	the timer/score-cap win checks and replicates ScoreState — this class only
	maps events to `deps.addScore` and keeps both teams populated:

	  * players are balance-assigned onto the smaller team (idempotent —
	    onPlayerAdded fires from both the match-start sweep and PlayerAdded);
	  * bots spawn alternating across teams; each rig carries its team in the
	    replicated `GameTeam` attribute (set by NpcSpawner pre-tag) AND on its
	    server-side fake actor, so the whole hit pipeline (which only reads
	    Player-shaped `.Team`/`.Neutral`) sees the team without branching;
	  * dead bots are replaced on the same team after NPC_RESPAWN_DELAY, so a
	    bot match doesn't decay to empty teams.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")

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

-- The mode team with the fewest players right now (Team instances were
-- created from config.teams by GameModeService before Start).
function TeamDeathmatch._smallerTeam(self): Team?
	local best: Team? = nil
	local bestCount = math.huge
	for _, spec in self.config.teams :: { gameModeTypes.TeamSpec } do
		local team = Teams:FindFirstChild(spec.id) :: Team?
		if team then
			local count = #team:GetPlayers()
			if count < bestCount then
				best, bestCount = team, count
			end
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

	local team = self:_smallerTeam()
	if team then
		player.Team = team
		player.Neutral = false
	end
end

--[=[
	Adopts a spawned rig into the match: marks its server-side fake actor with
	the team (the rig's replicated `GameTeam` attribute was set by NpcSpawner
	pre-tag) and arms the same-team respawn on death. `Humanoid.Died` is used
	instead of the kill signal because it also covers deaths EffectService
	never sees (falls, despawn damage).
]=]
function TeamDeathmatch._registerNpc(self, rig: Model, teamId: gameModeTypes.TeamId)
	local actor = getCharacterActor(rig) :: any
	actor.Team = Teams:FindFirstChild(teamId)
	actor.Neutral = false
	self._npcTeams[rig] = teamId

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
	local botCount = payload.botCount or 0
	if botCount <= 0 then
		return
	end

	-- Alternate across teams so both sides stay even regardless of count.
	local teamIds = {}
	local specs = self.config.teams :: { gameModeTypes.TeamSpec }
	for index = 1, botCount do
		teamIds[index] = specs[((index - 1) % #specs) + 1].id
	end

	local rigs = NpcSpawner.Spawn(botCount, teamIds)
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
