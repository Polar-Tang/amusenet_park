local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AmmoCounter = require(script.Parent.components.AmmoCounter)
local Crosshair = require(script.Parent.components.Crosshair)
local DeathScreen = require(script.Parent.components.DeathScreen)
local MobileButtons = require(script.Parent.components.MobileButtons)
-- local SpinRoulette = require(script.Parent.components.SpinRoulette)
local QuestsList = require(script.Parent.components.QuestsList)
local Roact = require(ReplicatedStorage.Shared.Roact)

local CrosshairProvider = require(script.Parent.Context.CrosshairContext.CrosshairProvider)

local App = Roact.Component:extend("App")

function App:render()
	return Roact.createElement("ScreenGui", {
		-- Roact owns this ScreenGui for the whole session: letting the engine
		-- delete it on spawn would orphan the tree, and the DeathScreen flow
		-- needs the UI alive across death -> respawn.
		ResetOnSpawn = false,
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
		QuestsList = Roact.createElement(QuestsList),
		AmmoCounter = Roact.createElement(AmmoCounter),
		DeathScreen = Roact.createElement(DeathScreen, {
			cameraMediator = self.props.cameraMediator,
		}),
		-- SpinRoulette = Roact.createElement(SpinRoulette),
	})
end

return App
