local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)

local progressLoadingBar = Roact.Component:extend("progressLoadingBar")

local PERCENTAGE = 100

function progressLoadingBar:init()
	
end


function progressLoadingBar:unMount()
	self._increaseConnection:Disconnect()
	self._ancestryConnection:Disconnect()
end

function progressLoadingBar:render()
	return Roact.createElement("Frame", {
		Position = UDim2.new(0.5, 0, 0.75, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0.5, 0, 0.1, 0),
	}, {

		BarBackground = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(38, 38, 38),
			BackgroundTransparency = 0.6,
		}, {

			UICorner = Roact.createElement("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),

			UIStroke = Roact.createElement("UIStroke", {
				Color = Color3.fromRGB(0, 0, 0),
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			}),

			Bar = Roact.createElement("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 30, 0),
				BackgroundTransparency = 0.2,
				Size = UDim2.fromScale(math.min(PERCENTAGE, self.props.percentage) / PERCENTAGE, 1),
			}, {
				UICorner = Roact.createElement("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
			}),
		}),
	})
end

function progressLoadingBar:willUnmount()
	if self._connection then
		self._connection:Disconnect()
	end
	if self._increaseConnection then
		self._increaseConnection:Disconnect()
	end
end
return progressLoadingBar
