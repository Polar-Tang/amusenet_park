local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FXPart = require(script.Parent.FXPart)

local WindsFX = {}
WindsFX.__index = WindsFX

local Effects = ReplicatedStorage.Shared.Effects
local circle = Effects.winds.WaveCircle
local point = Effects.winds.WaveTail

function WindsFX:CreateRing(CF, template)
	local ourTemplate = template or circle
	local newParams = {
		lifeTime = 1,
		template = ourTemplate,
		props = {
			CFrame = CF,
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
			AudioCanCollide = false,
			Parent = workspace,
		},
	}
	newParams.fade = {
		delay = 0,
		duration = 0.3,
	}
	newParams.scale = {
		duration = 0.3,
		scaleBy = 2,
	}
	
	FXPart.new(newParams)
end

-- local ring = newInstance.Part

return WindsFX
