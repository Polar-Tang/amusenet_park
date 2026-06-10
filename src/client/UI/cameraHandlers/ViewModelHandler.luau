--!nocheck
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local mathUtils = require(ReplicatedStorage.Shared.utils.mathUtils)
-- local bindSoundsToAnimationEvents = require(script.Parent.Parent.Utility.bindSoundsToAnimationEvents)

local camera = Workspace.CurrentCamera
local viewModels = ReplicatedFirst.ViewModels

--[[
	For src/client/UI/cameraHandlers/ViewModelHandler.luau we need to calculate the viewmodels offset to have aimPosition about the camera center. Read ViewModelController:update we are currently using and static offset value and the viewModels are not arranged when the position self.aimPosition is an attachment parented to the viewModels and the viewModels should :MoveTo to whatever's Y position requires to have self.aimPosition directly about the camera center.
]]

local ViewModelController = {}
ViewModelController.__index = ViewModelController

local function applyCharacterMeshToArm(armPart, armType, viewModel, meshId: number)
	if not armPart then
		return
	end

	-- Remove any existing CharacterMesh
	for _, child in armPart:GetChildren() do
		if child:IsA("CharacterMesh") then
			child:Destroy()
		end
	end

	-- Create and apply CharacterMesh
	local characterMesh = Instance.new("CharacterMesh")
	characterMesh.BodyPart = Enum.BodyPart[armType]
	characterMesh.MeshId = meshId
	characterMesh.Parent = viewModel

	-- Try to match the player's skin color
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()

	local playerChar = player.Character or player.CharacterAdded:Wait()
	local bodyColors = playerChar:FindFirstChild("Body Colors")

	if armType == "RightArm" then
		armPart.Color = bodyColors.RightArmColor.Color
	elseif armType == "LeftArm" then
		armPart.Color = bodyColors.LeftArmColor.Color
	end

	-- Fallback: try to get color from the actual character arm
	local charArm = character:FindFirstChild(armType == "RightArm" and "Right Arm" or "Left Arm")
	if charArm and charArm:IsA("BasePart") then
		armPart.Color = charArm.Color
	end
end
--[[
	Every weapon needs to have a viewModel because is not posible at all to find a magic formula which position every tool in a position where it fits, besides another tecnical problems. All the viewModels are in ReplicatedFirst.viewModels and has the name of each weapon, the desired weapon is called "Weapon"
]]
function ViewModelController.new(weapon: Tool, useCharacterArms: boolean?)
	-- Despite the weapon streaming mode being set to Atomic, objects outside of workspace are not streamed.
	-- This means we need to WaitForChild, since the weapon will be parented to the player's Backpack initially.
	local viewModelTemplate = viewModels[weapon.Name]

	local viewModel = viewModelTemplate:Clone()

	local rightArm = viewModel:FindFirstChild("Right Arm")
	local leftArm = viewModel:FindFirstChild("Left Arm")

	local muzzle = viewModel:FindFirstChild("MuzzleAttachment", true)
	assert(muzzle, `{viewModel} is missing MuzzleAttachment!`)

	local animator = viewModel.AnimationController.Animator
	local animationsFolder = viewModel.Animations

	-- The viewModel needs to be parented to the DataModel in order to load animations, otherwise it will throw an error
	viewModel.Parent = ReplicatedStorage

	local function findCharacterMeshByBodyPart(character: Model, bodyPart: Enum.BodyPart): CharacterMesh?
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("CharacterMesh") and descendant.BodyPart == bodyPart then
				return descendant
			end
		end
		return nil
	end

	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local rightArmMesh = findCharacterMeshByBodyPart(character, Enum.BodyPart.RightArm)
	local leftArmMesh = findCharacterMeshByBodyPart(character, Enum.BodyPart.LeftArm)

	local rightArmMeshId = rightArmMesh and rightArmMesh.MeshId or 0
	local leftArmMeshId = leftArmMesh and leftArmMesh.MeshId or 0

	applyCharacterMeshToArm(rightArm, "RightArm", viewModel, rightArmMeshId)
	applyCharacterMeshToArm(leftArm, "LeftArm", viewModel, leftArmMeshId)

	local animations = {}
	for _, animation in animationsFolder:GetChildren() do
		local animationTrack = animator:LoadAnimation(animation)
		animations[animation.Name] = animationTrack

		-- Sounds will all be driven by animation events
		-- bindSoundsToAnimationEvents(animationTrack, sounds, audioTarget)
	end

	-- Add this: find the AimPosition attachment
	local aimPosition = viewModel:FindFirstChild("AimPosition", true)
	assert(aimPosition, `{viewModel} is missing AimPosition attachment!`)

	local self = {
		enabled = false,
		player_char = character,
		model = viewModel,
		handle = viewModel:WaitForChild("Weapon").PrimaryPart,
		muzzle = muzzle,
		aimPosition = aimPosition,
		animations = animations,
		toolInstances = {},
		connections = {},
		stride = 0,
		bobbing = 0,
		_maid = Maid.new(),
	}
	setmetatable(self, ViewModelController)

	return self
end

function ViewModelController:getBobbing(deltaTime: number)
	-- View model bobbing animation
	local moveSpeed = (self.handle.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	local bobbingSpeed = moveSpeed * Constants.VIEW_MODEL_BOBBING_SPEED
	local bobbing = math.min(bobbingSpeed, 1)

	self.stride = (self.stride + bobbingSpeed * deltaTime) % (math.pi * 2)
	self.bobbing =
		mathUtils.lerp(self.bobbing, bobbing, math.min(deltaTime * Constants.VIEW_MODEL_BOBBING_TRANSITION_SPEED, 1))

	local x = math.sin(self.stride)
	local y = math.sin(self.stride * 2)
	local bobbingOffset = Vector3.new(x, y, 0) * Constants.VIEW_MODEL_BOBBING_AMOUNT * self.bobbing
	local bobbingCFrame = CFrame.new(bobbingOffset)
	return bobbingCFrame
end

function ViewModelController:update(deltaTime: number)
	for _, instance in self.toolInstances do
		instance.LocalTransparencyModifier = 1
	end

	local cameraRotation = camera.CFrame - camera.CFrame.Position
	local forwardPos = (camera.CFrame * CFrame.new(0, 0, Constants.VIEW_MODEL_OFFSET.Z)).Position
	local baseCF = CFrame.new(forwardPos) * cameraRotation

	-- The aimPosition attachment shifts each frame from animations, so pivot first,
	-- sample the attachment in camera-local space, then re-pivot with the Y delta
	-- that lands aimPosition on the camera's forward ray (camera-local Y = 0).
	self.model:PivotTo(baseCF)
	local aimLocal = camera.CFrame:PointToObjectSpace(self.aimPosition.WorldPosition)
	self.model:PivotTo(baseCF * CFrame.new(0, -aimLocal.Y, 0))
end
---26.534, 1.073, 4.688
function ViewModelController:checkForToolInstance(instance: Instance)
	if not (instance:IsA("BasePart") or instance:IsA("Decal")) then
		return
	end

	local tool = instance:FindFirstAncestorOfClass("Tool")
	if not tool then
		return
	end

	table.insert(self.toolInstances, instance)
end

function ViewModelController:hideToolInstances()
	local character = self.player_char

	self._maid:GiveTask(character.DescendantAdded:Connect(function(descendant: Instance)
		self:checkForToolInstance(descendant)
	end))

	self._maid:GiveTask(character.DescendantRemoving:Connect(function(descendant: Instance)
		local index = table.find(self.toolInstances, descendant)
		if index then
			table.remove(self.toolInstances, index)
		end
	end))

	for _, descendant in character:GetDescendants() do
		self:checkForToolInstance(descendant)
	end
end

function ViewModelController:stopHidingToolInstances()
	table.clear(self.toolInstances)
	self._maid:DoCleaning()
end

function ViewModelController:getMuzzlePosition(): Vector3
	return self.muzzle.WorldPosition
end

function ViewModelController:playShootAnimation()
	self.animations.Shoot:Play(0)
	self.muzzle.FlashEmitter:Emit(1)
	self.muzzle.CircleEmitter:Emit(1)
end

function ViewModelController:playReloadAnimation(reloadTime: number)
	self.animations.Shoot:Stop()
	local speed = self.animations.Reload.Length / reloadTime
	self.animations.Reload:Play(Constants.VIEW_MODEL_RELOAD_FADE_TIME, 1, speed)
end

function ViewModelController:enable()
	if self.enabled then
		return
	end
	self.enabled = true

	RunService:BindToRenderStep(
		Constants.VIEW_MODEL_BIND_NAME,
		Enum.RenderPriority.Camera.Value + 76, -- after the camera cframe is write
		function(deltaTime: number)
			self:update(deltaTime)
		end
	)
	self.model.Parent = Workspace
	self:hideToolInstances()

	-- Play equip and idle animations
	self.animations.Idle:Play()
	self.animations.Equip:Play(0)
end

function ViewModelController:disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	RunService:UnbindFromRenderStep(Constants.VIEW_MODEL_BIND_NAME)
	self.model.Parent = nil
	self:stopHidingToolInstances()

	for _, animation in self.animations do
		animation:Stop(0)
	end
end

function ViewModelController:Destroy()
	self._maid:DoCleaning()
	self:disable()
	self.model:Destroy()
end

return ViewModelController
