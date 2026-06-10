local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local SlideAbility = require(script.Parent.SlideAbility)
local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
-- Create the slide ability
local slideAbility = SlideAbility.new({
	character = Players.LocalPlayer.Character,
	humanoid = character:FindFirstChild("Humanoid"),
	hrp = character.PrimaryPart,
	player = Players.LocalPlayer,
	type = "Movement",
	weapon_stats = {
		speed = 1.0,
		damage = 0, -- Slide does no damage
	},
	_maid = Maid.new(),
})

-- Initialize with custom end effect
slideAbility:Init({
	endFx = function(ability)
		
	end,
})
ContextActionService:BindAction("Tuvieja", function(_, _, inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseWheel then
            slideAbility:Execute({})
		end
	end, false, Enum.UserInputType.MouseWheel)

return {}