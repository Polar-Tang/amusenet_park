--[=[
	@class NpcController

	Mode-agnostic NPC roster for a match. A game-mode strategy (TeamDeathmatch
	today, KOTH/CTF tomorrow) owns the *policy* — which team a bot joins, when a
	match is active — while this controller owns the *bookkeeping* every mode
	shares:

	  * tracks the live rig -> team map (the same rig identity used for
	    head-count balancing and Stop teardown);
	  * registers a rig into the match: marks its server-side fake actor with the
	    team (so the hit pipeline, which only reads Player-shaped `.Team`/
	    `.Neutral`, sees the team without branching), team-colors it with a
	    Highlight, and arms a same-team respawn on death;
	  * spawns payload bots through NpcSpawner and registers each;
	  * adopts pre-placed `NPC`-tagged map rigs the spawner doesn't own;
	  * despawns the whole roster on Stop (untag runs the binder Destroy chain).

	The mode keeps team-assignment out of here: `AdoptPrePlaced`/`Spawn` take the
	team ids the mode already decided, and `GetTeamCounts` feeds the mode's own
	balancing. `Register`'s team id must be truthy (team modes); a nil id marks
	the rig Neutral for a future FFA mode but is not tracked for respawn balance.

	`Humanoid.Died` (not the kill signal) drives respawn because it also covers
	deaths EffectService never sees (falls, despawn damage).
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)

local NpcSpawner = require(ServerScriptService.Server.NPC.NpcSpawner)

local NpcController = {}
NpcController.__index = NpcController

export type NpcController = typeof(setmetatable(
	{} :: {
		_teams: { gameModeTypes.TeamSpec }?,
		_isMatchActive: () -> boolean,
		-- rig Model -> TeamId, for same-team respawn, balancing and teardown.
		_npcRigs: { [Model]: gameModeTypes.TeamId },
		_maid: any,
	},
	NpcController
))

--[=[
	@param teams { TeamSpec }? -- the mode's teams, for Highlight colors (nil => no outline)
	@param isMatchActive () -> boolean -- respawn gate; read lazily at each death
]=]
function NpcController.new(teams: { gameModeTypes.TeamSpec }?, isMatchActive: () -> boolean): NpcController
	local self = setmetatable({}, NpcController)

	self._teams = teams
	self._isMatchActive = isMatchActive
	self._npcRigs = {}
	self._maid = Maid.new()

	return self :: NpcController
end

-- Bot head count per team id (respawn-stable: a dead bot keeps its entry until
-- its same-team replacement spawns, so totals don't dip during the delay). The
-- mode adds its real-player counts on top for balancing.
function NpcController.GetTeamCounts(self: NpcController): { [gameModeTypes.TeamId]: number }
	local counts = {}
	for _, teamId in self._npcRigs do
		counts[teamId] = (counts[teamId] or 0) + 1
	end
	return counts
end

-- Team-colored outline so players can read a bot's allegiance (players have the
-- playerlist/team color, a bot has nothing else visible).
function NpcController._applyHighlight(self: NpcController, rig: Model, teamId: gameModeTypes.TeamId)
	if not self._teams then
		return
	end
	for _, spec in self._teams do
		if spec.id == teamId then
			local highlight = Instance.new("Highlight")
			highlight.Name = "TeamHighlight"
			highlight.FillTransparency = 1
			highlight.OutlineColor = spec.color.Color
			highlight.Parent = rig
			break
		end
	end
end

--[=[
	Registers a rig into the match: marks its fake actor with the team (its
	replicated `GameTeam` attribute is set elsewhere — NpcSpawner pre-tag for
	payload bots, the adoption sweep for pre-placed rigs), outlines it, and arms
	the same-team respawn on death.
]=]
function NpcController.Register(self: NpcController, rig: Model, teamId: gameModeTypes.TeamId)
	local actor = getCharacterActor(rig) :: any
	actor.Team = teamId and Teams:FindFirstChild(teamId) or nil
	actor.Neutral = teamId == nil
	self._npcRigs[rig] = teamId

	self:_applyHighlight(rig, teamId)

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	self._maid[rig] = humanoid.Died:Connect(function()
		self._maid[rig] = nil
		task.delay(GameModeConstants.NPC_RESPAWN_DELAY, function()
			self:_respawn(rig, teamId)
		end)
	end)
end

--[=[
	Spawns `count` bots onto random goals (NpcSpawner) and registers each on the
	matching team. `teamIds` is indexed 1..count.

	@return { Model } -- the spawned, registered rigs
]=]
function NpcController.Spawn(self: NpcController, count: number, teamIds: { gameModeTypes.TeamId }): { Model }
	local rigs = NpcSpawner.Spawn(count, teamIds)
	for index, rig in rigs do
		self:Register(rig, teamIds[index])
	end
	return rigs
end

--[=[
	Adopts pre-placed `NPC`-tagged map rigs the spawner doesn't own (no GameTeam
	attribute, not already tracked) into the match. `assign(rig)` is the mode's
	team policy, called per rig so each adoption affects the next one's balance
	(Register updates GetTeamCounts immediately); a nil return skips the rig.
]=]
function NpcController.AdoptPrePlaced(self: NpcController, assign: (Model) -> gameModeTypes.TeamId?)
	for _, rig in CollectionService:GetTagged(Constants.NPC_TAG) do
		if
			rig:IsA("Model")
			and rig:IsDescendantOf(Workspace)
			and not self._npcRigs[rig]
			and rig:GetAttribute(GameModeConstants.TEAM_ATTRIBUTE) == nil
		then
			local teamId = assign(rig)
			if teamId then
				rig:SetAttribute(GameModeConstants.TEAM_ATTRIBUTE, teamId)
				self:Register(rig, teamId)
			end
		end
	end
end

-- Untag (runs the NPC binder Destroy chain) then destroy a single rig.
function NpcController._despawn(self: NpcController, rig: Model)
	self._maid[rig] = nil
	self._npcRigs[rig] = nil
	CollectionService:RemoveTag(rig, Constants.NPC_TAG)
	rig:Destroy()
end

-- Replace a dead bot on the same team, but only while the match is live (the
-- end screen freezes combat — no new bots should appear).
function NpcController._respawn(self: NpcController, deadRig: Model, teamId: gameModeTypes.TeamId)
	if not self._isMatchActive() then
		return
	end
	if self._npcRigs[deadRig] then
		self:_despawn(deadRig)
	end
	self:Spawn(1, { teamId })
end

-- Despawns the whole roster (Stop teardown): drop the Died connections, then
-- untag + destroy every tracked rig so NPC brains stop shooting.
function NpcController.DespawnAll(self: NpcController)
	self._maid:DoCleaning()
	for rig in self._npcRigs do
		CollectionService:RemoveTag(rig, Constants.NPC_TAG)
		rig:Destroy()
	end
	table.clear(self._npcRigs)
end

function NpcController.Destroy(self: NpcController)
	self:DespawnAll()
end

return NpcController
