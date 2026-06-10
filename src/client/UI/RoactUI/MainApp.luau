local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)

local App = require(script.Parent.App)
local CameraMediator = require(script.Parent.Parent.cameraHandlers.camerasStates.CameraMediator)

export type MainAppDeps = {
	weaponClient: any,
	cameraMediator: CameraMediator.CameraMediator,
}

return function(deps: MainAppDeps)
	local player = Players.LocalPlayer
	local PlayerGui = player:WaitForChild("PlayerGui")

	local mount = Roact.mount(
		Roact.createElement(App, {
			cameraMediator = deps.cameraMediator,
			weaponClient = deps.weaponClient,
		}),
		PlayerGui,
		"UI"
	)

	return mount
end
