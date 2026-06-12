--[=[
	@function canPlayerDamageHumanoid
	Friendly-fire gate, shared by client hit prediction and server validation.
	`player` may be a real Player or a getCharacterActor fake (NPC rigs).

	Teams resolve through the game-mode `resolveTeam` rule (Player.Team when
	not Neutral, else the rig's replicated GameTeam attribute). A side with no
	team allows damage — exactly the pre-gamemode behavior for neutral players
	and dummy rigs — so combat outside team modes is untouched.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)

local function canPlayerDamageHumanoid(player: Player, taggedHumanoid: Humanoid): boolean
	-- If the humanoid is already dead, no need to apply more damage
	if not taggedHumanoid:IsA("Humanoid") or taggedHumanoid.Health <= 0 then
		return false
	end

	local taggedCharacter = taggedHumanoid.Parent :: Model?
	local attackerTeam = resolveTeam(player.Character, player)
	local defenderTeam = resolveTeam(taggedCharacter, Players:GetPlayerFromCharacter(taggedCharacter))

	-- Either side teamless (neutral player, dummy, pre-match) => allow damage
	if not attackerTeam or not defenderTeam then
		return true
	end

	-- Only allow damage across teams
	return attackerTeam ~= defenderTeam
end

return canPlayerDamageHumanoid
