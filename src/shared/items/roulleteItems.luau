--[=[
	Roulette reward table.

	6 equal sectors of π/3 radians (60°) each.
	Angles are measured from the top of the wheel, clockwise (0 = top pointer).
	3 Common → 2 Uncommon → 1 Epic, left to right around the wheel.

	@module roulleteItems
]=]

export type RewardEntry = {
	name: string,
	rarety: string,
	angle: number, -- radians, centre of this sector from wheel top, clockwise
}

local TAU = 2 * math.pi
local SECTOR = TAU / 6 -- π/3 ≈ 1.047 rad  (60°)

local RouletteItems: { RewardEntry } = {
	{ name = "Coins",     rarety = "Common",   angle = 0           },
	{ name = "Potion",    rarety = "Common",   angle = SECTOR      },
	{ name = "Shield",    rarety = "Common",   angle = 2 * SECTOR  },
	{ name = "Sword",     rarety = "Uncommon", angle = 3 * SECTOR  },
	{ name = "Armor",     rarety = "Uncommon", angle = 4 * SECTOR  },
	{ name = "Dragon Egg",rarety = "Epic",     angle = 5 * SECTOR  },
}

return RouletteItems
