local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

--[[
	First-person mode strategy. Mirrors ThirdPerson: it no longer extends
	CameraHandlerBase nor creates its own effects. It receives the shared
	_cameraState from the mediator, mirrors workspace.CurrentCamera into it
	each frame, and pins arm + tool LocalTransparencyModifier so the real
	character arms stay visible (no viewmodel).
]]
local FirstPersonCamera = {}
FirstPersonCamera.__index = FirstPersonCamera

function FirstPersonCamera.new(cameraState)
	local self = setmetatable({}, FirstPersonCamera)

	self._cameraState = cameraState
	self._maid = Maid.new()
	self._key = HttpService:GenerateGUID(false)

	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	self.hrp = character.PrimaryPart

	-- No viewmodel in first person: show the real character arms (and the welded
	-- weapon) by pinning their LocalTransparencyModifier to 0 every frame, which
	-- overrides the engine's first-person hide.
	local arms = {
		character:FindFirstChild("Left Arm"),
		character:FindFirstChild("Right Arm"),
	}

	local stepName = "FirstPersonCamera_" .. self._key
	RunService:BindToRenderStep(stepName, Enum.RenderPriority.Camera.Value, function()
		local baseCFrame = Workspace.CurrentCamera.CFrame

		local desiredRotation = baseCFrame - baseCFrame.Position
		local desiredPosition = baseCFrame.Position

		self._cameraState.CFrame = CFrame.new(desiredPosition) * desiredRotation
		
		for _, arm in arms do
			arm.LocalTransparencyModifier = 0
		end
	end)

	self._maid:GiveTask(function()
		RunService:UnbindFromRenderStep(stepName)
	end)

	return self
end

function FirstPersonCamera.Destroy(self)
	self._maid:DoCleaning()
end

return FirstPersonCamera
