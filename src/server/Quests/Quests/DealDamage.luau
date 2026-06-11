--[=[
	@class DealDamage
	Damage quest: progressed by EffectService with the damage actually dealt
	(`IncreaseProgress("damage", context.damage)`).
]=]

local questTypes = require(script.Parent.Parent.questTypes)

local DealDamage: questTypes.Quest = {
	questId = "DealDamage_1",
	kind = "damage",
	title = "Warm Up the Barrel",
	description = "Deal 500 damage to other players.",
	requiredAmount = 500,

	onCompleted = function(player, progress)
		print(string.format("[Quest] %s completed %s", player.Name, progress.questId))
	end,
}

return DealDamage
