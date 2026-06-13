--[=[
	@class TeamDeathmatch
	The "tdm" strategy: two teams, a kill on an enemy scores the attacker's team
	one point. Everything team-vs-team that isn't the win condition — the NPC
	roster (adopt/spawn/respawn/despawn) and balanced team assignment — lives in
	TeamMode; GameModeService owns the timer, score cap, win checks and
	ScoreState replication. This class only maps enemy kills to `deps.addScore`.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local TeamMode = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.TeamMode)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)
local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)

local TeamDeathmatch = setmetatable({}, { __index = TeamMode })
TeamDeathmatch.__index = TeamDeathmatch

-- No new fields over TeamMode; the typeof captures the `onKill` override.
export type TeamDeathmatch = typeof(setmetatable({}, TeamDeathmatch)) & TeamMode.TeamMode

function TeamDeathmatch.new(config: gameModeTypes.ModeConfig): TeamDeathmatch
	return setmetatable(TeamMode.new(config) :: any, TeamDeathmatch) :: TeamDeathmatch
end

function TeamDeathmatch.onKill(self: TeamDeathmatch, attackerChar: Model, defenderChar: Model)
	if attackerChar == defenderChar or not self._deps then
		return
	end

	local attackerTeam = resolveTeam(attackerChar, getCharacterActor(attackerChar))
	local defenderTeam = resolveTeam(defenderChar, getCharacterActor(defenderChar))
	-- Only enemy kills score: teamless victims (dummies) and friendly fire feed
	-- nothing.
	if not attackerTeam or not defenderTeam or attackerTeam == defenderTeam then
		return
	end

	self._deps.addScore(attackerTeam.Name, 1)
end

return TeamDeathmatch
