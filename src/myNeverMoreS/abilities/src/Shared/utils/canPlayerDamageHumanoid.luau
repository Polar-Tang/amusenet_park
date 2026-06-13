--[=[
	@function canPlayerDamageHumanoid
	Friendly-fire gate, shared by client hit prediction and server validation.
	`player` may be a real Player or a getCharacterActor fake (NPC rigs).

	Teams resolve through the game-mode `resolveTeam` rule (Player.Team when
	not Neutral, else the rig's replicated GameTeam attribute). A side with no
	team allows damage — exactly the pre-gamemode behavior for neutral players
	and dummy rigs — so combat outside team modes is untouched.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)
local isDamageableByTeam = require(script.Parent.isDamageableByTeam)

local function canPlayerDamageHumanoid(player: Player, taggedHumanoid: Humanoid): boolean
	return isDamageableByTeam(resolveTeam(player.Character, player), taggedHumanoid)
end

return canPlayerDamageHumanoid
