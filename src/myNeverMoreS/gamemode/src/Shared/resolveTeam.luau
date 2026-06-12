--[=[
	@function resolveTeam
	One team-resolution rule shared by the damage check
	(canPlayerDamageHumanoid, client prediction + server validation) and the
	mode strategies, so they can never disagree.

	A combatant's team is, in order:
	  1. its Player's (or fake actor's) `.Team` when not Neutral — real players
	     assigned by a mode, and NPC fake actors the mode marked server-side;
	  2. the character's replicated `GameTeam` attribute — the NPC rig's team
	     identity, readable on every client;
	  3. nil — teamless (dummies, pre-match players, non-team modes).

	Callers treat nil as "allow damage", preserving the pre-gamemode neutral
	behavior exactly.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)

local function resolveTeam(character: Model?, actor: Player?): Team?
	if actor and not actor.Neutral and actor.Team then
		return actor.Team
	end

	local teamName = character and character:GetAttribute(GameModeConstants.TEAM_ATTRIBUTE)
	if typeof(teamName) == "string" then
		return Teams:FindFirstChild(teamName) :: Team?
	end

	return nil
end

return resolveTeam
