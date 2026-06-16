game.StarterPlayer.EnableMouseLockOption = false

local SmoothShiftLock = {}
SmoothShiftLock.__index = SmoothShiftLock

-- [[ Variables ]]:

--// Services and requires
local Players = game:GetService("Players")
local WorkspaceService = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local handHeadCamera = require(script.Parent.handHeadCamera)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local Spring = require(ReplicatedStorage.Nevermore.Quenty.spring.Shared.Spring)

--// Instances
local LocalPlayer = Players.LocalPlayer

--// Bindables
local events = RS.Shared.RemoteEvents
local ToggleEvent: RemoteEvent = events.ToggleShiftLock
local EditConfig: RemoteEvent = events.EditConfig
--// Configuration
local config = {
	["CHARACTER_SMOOTH_ROTATION"] = true, --// If your character should rotate smoothly or not
	["MANUALLY_TOGGLEABLE"] = true, --// If the shift lock an be toggled manually by player
	["CHARACTER_ROTATION_SPEED"] = 3, --// How quickly character rotates smoothly
	["TRANSITION_SPRING_DAMPER"] = 0.7, --// Camera transition spring damper, test it out to see what works for you
	["CAMERA_TRANSITION_IN_SPEED"] = 10, --// How quickly locked camera moves to offset position
	["CAMERA_TRANSITION_OUT_SPEED"] = 14, --// How quickly locked camera moves back from offset position
	["LOCKED_CAMERA_OFFSET"] = Vector3.new(0, 1.25, 0), --// Locked camera offset
	--["LOCKED_CAMERA_OFFSET"]        = Vector3.new(1.75, 0.25, 0), --// Locked camera offset
	--// Locked mouse icon
	--// Shift lock keybinds
	["SHIFT_LOCK_KEYBINDS"] = { Enum.KeyCode.LeftShift },
	["CAMERA_OFFSET"] = Vector3.new(1.5, -1, 0), -- X = right, Y = up, Z = forward
}

local ENABLED = false

--// Setup
local maid = Maid.new()

-- [[ Functions ]]:

--// Setup smooth shift lock on client (Run once and on a LocalScript)
function SmoothShiftLock.new(CameraService, armedBinder)
	local self = setmetatable({}, SmoothShiftLock)
	self.CameraService = CameraService
	-- Injected by CameraMediator:Start. Held so handHeadCamera can read the
	-- cached AimPosition attachment without per-frame FindFirstChild calls.
	self._armedBinder = armedBinder

	-- Not yielding
	task.spawn(function()
		self:CharacterAdded()
	end)
	-- Session-lived connection (deliberately NOT in connectionsMaid, which is
	-- destroyed on death): re-acquire the rig on every respawn, otherwise the
	-- controller keeps driving the destroyed character forever.
	LocalPlayer.CharacterAdded:Connect(function()
		self:CharacterAdded()
	end)
	return self
end

--// Character added event function
function SmoothShiftLock:CharacterAdded()
	--// Instances
	self.Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	self.RootPart = self.Character:WaitForChild("HumanoidRootPart")
	self.Humanoid = self.Character:WaitForChild("Humanoid")
	self.Head = self.Character:WaitForChild("Head")
	-- Character-scoped: the render loop re-resolves it lazily from the
	-- "Armed" binder, so a stale (destroyed) WeaponClient must be dropped.
	self._weaponClient = nil
	--// Other
	self.Camera = WorkspaceService.CurrentCamera
	--// Setup
	self.connectionsMaid = Maid.new()
	

	--// Bindables
	self.connectionsMaid:GiveTask(ToggleEvent.OnClientEvent:Connect(function(toggle: boolean)
		if self.Humanoid and self.Humanoid.Health ~= 0 then
			self:ToggleShiftLock(toggle)
		end
	end))

	self.connectionsMaid:GiveTask(EditConfig.OnClientEvent:Connect(function(toChange, value)
		if config[toChange] ~= nil then
			config[toChange] = value
		end
	end))

	--// On death
	self.connectionsMaid:GiveTask(self.Humanoid.Died:Connect(function()
		self:CharacterDiedOrRemoved()
		return
	end))

	--// On character removing
	self.connectionsMaid:GiveTask(LocalPlayer.CharacterRemoving:Connect(function()
		self:CharacterDiedOrRemoved()
		return
	end))

	return self
end

--// Stop shiftlock upon character death or removal
function SmoothShiftLock:CharacterDiedOrRemoved()
	self:ToggleShiftLock(false)

	if self.connectionsMaid ~= nil then
		self.connectionsMaid:Destroy()
	end

	maid:DoCleaning()
end

--// Return shiftlock enabled state
function SmoothShiftLock:IsEnabled(): boolean
	return ENABLED
end

--// Set Enum.MouseBehavior to LockCenter or Default depending on shiftlock enabled
function SmoothShiftLock:SetMouseState(enable: boolean)
	UserInputService.MouseBehavior = (enable and Enum.MouseBehavior.LockCenter) or Enum.MouseBehavior.Default
end

--// Change mouse icon depending on shiftlock enabled
function SmoothShiftLock:SetMouseIcon(enable: boolean)
	UserInputService.MouseIcon = (enable and config.LOCKED_MOUSE_ICON :: string) or ""
end

--// Toggle shift lock
function SmoothShiftLock:ToggleShiftLock(enable: boolean)
	assert(typeof(enable) == typeof(false), "Enable value is not a boolean.")
	ENABLED = enable

	self:SetMouseState(ENABLED)
	self:SetMouseIcon(ENABLED)

	local cameraService = self.CameraService

	--// Start
	-- This should happen in a replicated storage to replicating it to all the other players

	if ENABLED then
		RunService:BindToRenderStep("PlayerSpin", Enum.RenderPriority.Camera.Value + 76, function(delta)
			if self.Humanoid and self.RootPart then
				self.Humanoid.AutoRotate = not ENABLED
			end			

			--// Rotate character
			if ENABLED then
				-- WATCH THIS CHANGE
				local camera = cameraService:GetTopState().CFrame

				if not self.Humanoid.Sit and config.CHARACTER_SMOOTH_ROTATION then
					local _x, y, _z = camera:ToOrientation()
					self.RootPart.CFrame = self.RootPart.CFrame:Lerp(
						CFrame.new(self.RootPart.Position) * CFrame.Angles(0, y, 0),
						delta * 5 * config.CHARACTER_ROTATION_SPEED
					)
				elseif not self.Humanoid.Sit then
					local _x, y, _z = camera:ToOrientation()
					self.RootPart.CFrame = CFrame.new(self.RootPart.Position) * CFrame.Angles(0, y, 0)
				end
			end
			if not self._weaponClient then 
				self._weaponClient = self._armedBinder:Get(self.Character)
			end
			handHeadCamera(delta, self._weaponClient)

			--// Stop
			if not ENABLED then
				maid:Destroy()
			end
		
			
		end)
	end
	return self
end

return SmoothShiftLock
