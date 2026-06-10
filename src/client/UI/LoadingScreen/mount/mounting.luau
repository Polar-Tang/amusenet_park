local RS = game:GetService("ReplicatedStorage")
local Roact = require(RS.Shared.Roact)


local Players = game:GetService("Players")
local App = require(script.Parent.App)

local MainApp = Roact.Component:extend("MainApp")

function MainApp:render()
	return Roact.createElement("ScreenGui", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, {
		-- PromptProvider = Roact.createElement(PromptProvider, {}, {
		AppUI = Roact.createElement(App, {
            progress = self.props.progress,
        }),
		-- }),
	})
end

return function(parent)
    local player = Players.LocalPlayer
    local PlayerGui = player:WaitForChild("PlayerGui")
    local mounting = Roact.mount(Roact.createElement(MainApp, { progress = parent.progress, finnishSignal = parent.finnishSignal }), PlayerGui, "LoadingScreen")
    return mounting
end