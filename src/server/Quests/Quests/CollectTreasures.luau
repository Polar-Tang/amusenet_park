--[=[
	@class CollectTreasures
	Catch quest: progress it from whatever service hands out treasures (the
	future chest/radar binder prompt) via `IncreaseProgress("catch", 1)`.
]=]

local questTypes = require(script.Parent.Parent.questTypes)

local CollectTreasures: questTypes.Quest = {
	questId = "CollectTreasures_1",
	kind = "catch",
	title = "Treasure Hunter",
	description = "Collect 3 treasures around the map.",
	requiredAmount = 3,

	onCompleted = function(player, progress)
		print(string.format("[Quest] %s completed %s", player.Name, progress.questId))
	end,
}

return CollectTreasures
