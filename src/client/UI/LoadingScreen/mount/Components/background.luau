local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)
local background = Roact.Component:extend("CustomProximityPrompts")

function background:render()
	return Roact.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(135, 206, 235),
		ZIndex = 0,
		BorderSizePixel = 0,
	})
end

return background
