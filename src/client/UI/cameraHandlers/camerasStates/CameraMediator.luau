local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shiftLockController = require(ReplicatedStorage.Shared.Animations.PlayerMovementReplica.shiftLockController)
local CameraStackService = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.CameraStackService)
local CameraState = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.CameraState)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local ServiceBag = require(ReplicatedStorage.Nevermore.Quenty.servicebag.Shared.ServiceBag)
local ValueObject = require(ReplicatedStorage.Nevermore.Quenty.valueobject.Shared.ValueObject)
local CameraHandlerBase = require(script.Parent.CameraHandlerBase)
local FirstPerson = require(script.Parent.FirstPerson)
local ThirdPerson = require(script.Parent.ThirdPerson)

--[=[
	@class CameraMediator

	Singleton service that owns the first/third-person camera mode and
	exposes a toggle plus an observable for UI/consumers. Registered with
	the client ServiceBag in ServiceRoot.client.luau; resolve via
	`serviceBag:GetService(CameraMediator)` rather than constructing.
]=]
local CameraMediator = setmetatable({}, CameraHandlerBase)
CameraMediator.__index = CameraMediator
CameraMediator.ServiceName = "CameraMediator"

export type CameraMediator = typeof(CameraMediator) & {
	player: Player,
	_maid: any,
	_serviceBag: ServiceBag.ServiceBag,
	_isFirstPerson: any,
}

local THIRDPERSON_CAMERA_DISTANCE = ThirdPerson.CAMERA_OFFSET.Magnitude

function CameraMediator:applyClassicCameraDistance()
	self.player.CameraMinZoomDistance = THIRDPERSON_CAMERA_DISTANCE
	self.player.CameraMaxZoomDistance = THIRDPERSON_CAMERA_DISTANCE
end


function CameraMediator:Init(serviceBag)
	self._maid = Maid.new()
	self.player = Players.LocalPlayer
	self._serviceBag = serviceBag

	self._isFirstPerson = self._maid:Add(ValueObject.new(false, "boolean"))
	self._manualFirstPerson = false
	return self
end

function CameraMediator:Start(AttacksBinders)
	local CameraService = self._serviceBag:GetService(CameraStackService)

	-- Resolve the local character's WeaponClient ("Armed" bound class) so we
	-- can inject it into shiftLockController. handHeadCamera reads the cached
	-- AimPosition off it every frame instead of walking the character tree.

	local armedBinder = self._serviceBag:GetService(_G.BinderProvider):Get("Armed")
	self._shiftLockControllerShit = shiftLockController.new(CameraService, armedBinder)

	-- Persistent camera state + effects: the mediator owns _cameraState and
	-- _recoilCombo/_lerpCombo for the lifetime of the session. Mode strategies
	-- (FirstPerson / ThirdPerson) below only own their render step, which
	-- writes into this shared _cameraState. This way an in-flight lerp or
	-- recoil keeps running across an FP↔TP toggle instead of being torn down
	-- with the old handler.
	self._cameraState = CameraState.new(Workspace.CurrentCamera)
	self:_initEffects(CameraService, self._cameraState)

	_G.CurrentCameraHandler = self

	self._maid:GiveTask(function()
		if self._activeMode then
			self._activeMode:Destroy()
			self._activeMode = nil
		end
	end)

	self._isFirstPerson:Observe():Subscribe(function(value)
		if self._activeMode then
			self._activeMode:Destroy()
			self._activeMode = nil
		end
		if value then
			self._activeMode = FirstPerson.new(self._cameraState)
		else
			self._shiftLockControllerShit:ToggleShiftLock(true)
			-- Pass the mediator so the strategy can read _aimTargetPosition (set by
			-- TrackAim) and anchor its position offset on the character->target
			-- direction while the auto-aim lock is active.
			self._activeMode = ThirdPerson.new(self._cameraState, self)
		end
	end)
end

function CameraMediator:ToggleFirstPerson()
	if self._isFirstPerson.Value then
		self.player.CameraMode = Enum.CameraMode.Classic
		self:applyClassicCameraDistance()
		self._isFirstPerson.Value = false
	else
		self.player.CameraMode = Enum.CameraMode.LockFirstPerson
		self._isFirstPerson.Value = true
	end
end

function CameraMediator:ObserveIsFirstPerson()
	return self._isFirstPerson:Observe()
end

return CameraMediator
