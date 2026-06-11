--[=[
	@class TestEliminate
	Throwaway quest for playtesting the quest loop end to end: a single kill
	completes it, so one elimination exercises IncreaseProgress, onCompleted
	and the QuestsList UI's completed state. Delete once the loop is trusted.
]=]

local questTypes = require(script.Parent.Parent.questTypes)

local TestEliminate: questTypes.Quest = {
	questId = "TestEliminate_1",
	kind = "kill",
	title = "Test: One Elimination",
	description = "Eliminate 1 player.",
	requiredAmount = 1,

	onCompleted = function(player, progress)
		print(string.format("[Quest] %s completed %s", player.Name, progress.questId))
	end,
}

return TestEliminate
