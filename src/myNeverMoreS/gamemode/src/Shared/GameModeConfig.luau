--[=[
	@class GameModeConfig
	Data-driven mode declarations, CombatConfig-in-spirit: one ModeConfig per
	mode id. Adding a mode = one entry here + one strategy class registered in
	GameModeService.MODE_REGISTRY (+ the strategy file itself).
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)

local GameModeConfig: { [string]: gameModeTypes.ModeConfig } = {
	tdm = {
		id = "tdm",
		displayName = "Team Deathmatch",
		targetScore = 30,
		timeLimitSeconds = 600,
		teams = {
			{ id = "Crimson", displayName = "Crimson", color = BrickColor.new("Bright red") },
			{ id = "Azure", displayName = "Azure", color = BrickColor.new("Bright blue") },
		},
		respawnEnabled = true,
		equipDefaultWeapon = true,
	},
}

return GameModeConfig
