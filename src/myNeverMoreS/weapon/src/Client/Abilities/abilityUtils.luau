local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local attacksArray = require(StarterPlayer.StarterPlayerScripts.Client.Public.attacksArray)
local attacksData = require(StarterPlayer.StarterPlayerScripts.Client.Public.attacksData)
local ticks = {}
local module = {}

module.get_skill_by_index = function(index)
	local current_char_name = Players.LocalPlayer.Character:GetAttribute("char_name")
	local char_abilities = attacksData[current_char_name]
	local abilityName = attacksArray[current_char_name][index]
	local attack_data = char_abilities[abilityName]
	if not attack_data then
		return
	end

	return attack_data
end

module.resetTicks = function()
	ticks = {}
end

module.isCD = function(index): boolean
	local startTime = tick()
	local lastTime = ticks[index]

	local attack_data = module.get_skill_by_index(index)
	if not attack_data then
		print("Player got invalid char_name")
		return false
	end

	if not lastTime then
		ticks[index] = startTime
	else
		local time_passed = startTime - lastTime
		print("time_passed ", time_passed)
		if time_passed < attack_data.cooldown then
			return true
		end
	end
	ticks[index] = startTime
	return false
end
return module
