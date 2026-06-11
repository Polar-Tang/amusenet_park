--[=[
	@class EliminatePlayers
	Kill quest: progressed by EffectService each time a player's damage
	leaves the defender dead (`IncreaseProgress("kill", 1)`).
]=]

local questTypes = require(script.Parent.Parent.questTypes)

local EliminatePlayers: questTypes.Quest = {
	questId = "EliminatePlayers_1",
	kind = "kill",
	title = "First Blood",
	description = "Eliminate 3 players.",
	requiredAmount = 3,

	onCompleted = function(player, progress)
		-- Unique reward logic belongs here (experience, roulette spin, skin...)
		print(string.format("[Quest] %s completed %s", player.Name, progress.questId))
	end,
}

return EliminatePlayers
