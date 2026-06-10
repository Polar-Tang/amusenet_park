local AbilityConstants = {}

AbilityConstants.DefensePriority = {
	-- Highest priority - executes first
	PERFECT_BLOCK = 1, -- Timing-based blocks that can negate all damage
	COUNTER = 2, -- Counter-attacks that might cancel incoming damage
	PARRY = 3, -- Deflection mechanics

	-- Middle priority
	DAMAGE_REDUCTION = 4, -- Percentage-based damage reduction
	ARMOR = 5, -- Flat damage reduction

	-- Lowest priority - executes last
	CHIP_DAMAGE = 6, -- Final pass-through damage
	STAMINA_COST = 7, -- Resource consumption (always runs)
}

return AbilityConstants
