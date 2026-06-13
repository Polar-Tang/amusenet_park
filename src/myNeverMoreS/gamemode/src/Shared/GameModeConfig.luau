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
	koth = {
		id = "koth",
		displayName = "King of the Hill",
		-- Points (banked per KOTH_TICK_INTERVAL while a team holds the hill),
		-- not kills: ~100s of uncontested control to win.
		targetScore = 100,
		timeLimitSeconds = 600,
		teams = {
			{ id = "Crimson", displayName = "Crimson", color = BrickColor.new("Bright red") },
			{ id = "Azure", displayName = "Azure", color = BrickColor.new("Bright blue") },
		},
		respawnEnabled = true,
		equipDefaultWeapon = true,
	},
	ctf = {
		id = "ctf",
		displayName = "Capture the Flag",
		-- Captures (an enemy flag carried home while your own flag is at base),
		-- so the cap is small — first team to 3 captures, or the leader at time-up.
		targetScore = 3,
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
