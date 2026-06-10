local WeightedRandom = {}
local rand = Random.new()

-- entries: { {value = anything, weight = number}, ... }
function WeightedRandom.Pick(entries)
	local total = 0
	for _, e in ipairs(entries) do
		total += e.weight
	end
	if total <= 0 then return nil end

	local roll = rand:NextInteger(1, total)
	local cumulative = 0
	for _, e in ipairs(entries) do
		cumulative += e.weight
		if roll <= cumulative then
			return e.value
		end
	end
end

WeightedRandom.GetRarity = function()
    
    return WeightedRandom.Pick({
        {value = "Common",    weight = 200},
        {value = "Uncommon",  weight = 80},
        {value = "Rare",      weight = 45},
        {value = "Epic",      weight = 12},
        {value = "Legendary", weight = 5},
    })
end

return WeightedRandom