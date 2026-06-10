local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Crosshair = require(script.Parent.components.Crosshair)
local MobileButtons = require(script.Parent.components.MobileButtons)
local SpinRoulette = require(script.Parent.components.SpinRoulette)
local Roact = require(ReplicatedStorage.Shared.Roact)

local CrosshairProvider = require(script.Parent.Context.CrosshairContext.CrosshairProvider)

local App = Roact.Component:extend("App")

function App:render()
	return Roact.createElement("ScreenGui", {
		ResetOnSpawn = true,
		IgnoreGuiInset = true,
	}, {
		-- PromptProvider = Roact.createElement(PromptProvider, {}, {
		-- }),
		CrosshairProvider = Roact.createElement(CrosshairProvider, {
			cameraMediator = self.props.cameraMediator,
		}, {
			-- Crosshair = Roact.createElement(Crosshair) -- already used in :render
		}),
		MobileButtons = Roact.createElement(MobileButtons, {
				weaponClient = self.props.weaponClient,
			}),
		-- SpinRoulette = Roact.createElement(SpinRoulette),
	})
end

return App
