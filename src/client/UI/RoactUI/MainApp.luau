local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)

local App = require(script.Parent.App)
local CameraMediator = require(script.Parent.Parent.cameraHandlers.camerasStates.CameraMediator)

export type MainAppDeps = {
	-- The "Armed" Binder (not a bound class): the WeaponClient is
	-- character-scoped, so MainApp resolves the current one itself and
	-- re-injects the new instance into the tree on every rebind (respawn).
	weaponBinder: any,
	cameraMediator: CameraMediator.CameraMediator,
}

return function(deps: MainAppDeps)
	local player = Players.LocalPlayer
	local PlayerGui = player:WaitForChild("PlayerGui")

	local function makeElement(weaponClient)
		return Roact.createElement(App, {
			cameraMediator = deps.cameraMediator,
			weaponClient = weaponClient,
		})
	end

	local mount = Roact.mount(makeElement(deps.weaponBinder:Get(player.Character)), PlayerGui, "UI")

	deps.weaponBinder:GetClassAddedSignal():Connect(function(weaponClient)
		if Players:GetPlayerFromCharacter(weaponClient.Char) == player then
			mount = Roact.update(mount, makeElement(weaponClient))
		end
	end)

	return mount
end
