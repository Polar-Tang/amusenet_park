local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local Observable = require(ReplicatedStorage.Nevermore.Quenty.rx.Shared.Observable)
local SummedCamera = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.Effects.SummedCamera)
local LerpCamera = require(script.Parent.Parent.cameraEffects.LerpCamera)
local RecoilCamera = require(script.Parent.Parent.cameraEffects.RecoilCamera)

local CameraHandlerBase = {}
CameraHandlerBase.__index = CameraHandlerBase

function CameraHandlerBase.new()
	local self = setmetatable({}, CameraHandlerBase)
	self._cframe = nil
	self._maid = Maid.new()
	self._cameraStackService = nil
	self._recoilCamera = nil
	self._lerpCamera = nil
	self._recoilCombo = nil
	self._lerpCombo = nil
	self._recoilComboRemove = nil
	self._lerpRemove = nil
	return self
end

function CameraHandlerBase.ObserveIsFirstPerson(self): Observable.Observable<boolean>
	return self._isFirstPerson:Observe()
end

--[[
	Wires the camera composition. Recoil and lerp are mutually exclusive in time.
	recoilCombo (subclass _cameraState + recoil rotation delta) sits as the
	persistent stack top and contributes identity rotation when no recoil is
	active. LerpCamera swaps in as the new top while actively lerping and
	swaps back out on completion.
]]
function CameraHandlerBase:_initEffects(cameraStackService, cameraState)
	assert(cameraStackService, "cameraStackService is required")
	assert(cameraState, "cameraState is required")

	self._cameraStackService = cameraStackService
	self._recoilCamera = RecoilCamera.new()
	self._lerpCamera = LerpCamera.new()

	self._recoilCombo = SummedCamera.new(cameraState, self._recoilCamera):SetMode("Relative")
	-- LerpCamera is a rotation-only delta, so it has to compose with the
	-- subclass cameraState to pick up the live mode-specific position.
	-- Attached to the stack on demand via swapToLerp.
	self._lerpCombo = SummedCamera.new(cameraState, self._lerpCamera):SetMode("Relative")
	self._recoilComboRemove = cameraStackService:Add(self._recoilCombo)

	self._maid:GiveTask(function()
		if self._recoilComboRemove then
			self._recoilComboRemove()
			self._recoilComboRemove = nil
		end
		if self._lerpRemove then
			self._lerpRemove()
			self._lerpRemove = nil
		end
	end)
end

local function swapToLerp(self)
	if self._recoilComboRemove then
		self._recoilComboRemove()
		self._recoilComboRemove = nil
	end
	if not self._lerpRemove then
		self._lerpRemove = self._cameraStackService:Add(self._lerpCombo)
	end
end

local function swapToRecoil(self)
	if self._lerpRemove then
		self._lerpRemove()
		self._lerpRemove = nil
	end
	if not self._recoilComboRemove then
		self._recoilComboRemove = self._cameraStackService:Add(self._recoilCombo)
	end
end

function CameraHandlerBase:LerpCamera(targetCFrame: CFrame, timeToLerp: number)
	assert(self._recoilCamera, "_recoilCamera not initialized")
	assert(self._lerpCamera, "_lerpCamera not initialized")
	assert(self._cameraStackService, "_cameraStackService not initialized")

	-- reset recoil BEFORE snapshot so the lerp starts from a clean rotation
	self._recoilCamera:Reset()
	self._lerpCamera:StartLerp(targetCFrame, timeToLerp)
	self._lerpCamera:SetOnComplete(function()
		swapToRecoil(self)
	end)
	swapToLerp(self)
end

function CameraHandlerBase:StopLerpCamera()
	if self._lerpCamera then
		self._lerpCamera:StopLerp()
	end
	swapToRecoil(self)
end

-- Continuous auto-aim lock. Drives the LerpCamera in track mode toward a live
-- goal (call every frame from the aim-assist Heartbeat with the target's
-- current position). The lerp combo stays the stack top, so recoil is hidden —
-- this is the "hard lock" feel. `:resetRecoil` first clears any accumulated
-- kick so flipping back to the recoil combo on StopTrackAim doesn't snap.
function CameraHandlerBase:TrackAim(goalCFrame: CFrame, responsiveness: number, targetPosition: Vector3?)
	assert(self._lerpCamera, "_lerpCamera not initialized")
	assert(self._recoilCamera, "_recoilCamera not initialized")
	assert(self._cameraStackService, "_cameraStackService not initialized")

	-- The third-person mode strategy reads this to anchor its position offset on
	-- the character->target direction instead of the locked camera rotation. Nil
	-- while no lock is active, so the strategy falls back to its normal behavior.
	self._aimTargetPosition = targetPosition

	self._recoilCamera:Reset()
	self._lerpCamera:TrackTo(goalCFrame, responsiveness)
	swapToLerp(self)
end

function CameraHandlerBase:StopTrackAim()
	assert(self._cameraStackService, "_cameraStackService not initialized")

	-- Commit the tracked orientation into the REAL player aim before dropping the
	-- lock, so the camera stays exactly where tracking ended (no snap-back, no
	-- lingering offset). workspace.CurrentCamera currently holds the composed
	-- tracked rotation, and DefaultCamera keeps the player's aim in its own
	-- _cameraState that the stack composition never touches (see DefaultCamera's
	-- 198/200/202 render dance — the areClose guard preserves the pre-track base,
	-- which is precisely why a plain stop snaps back). Pushing the composed CFrame
	-- through SetRobloxCFrame also updates _lastCameraFrame, so the guard adopts it
	-- cleanly as the new base on the next frame.
	local rawDefaultCamera = self._cameraStackService:GetRawDefaultCamera()
	rawDefaultCamera:SetRobloxCFrame(Workspace.CurrentCamera.CFrame)
	if self._lerpCamera then
		self._lerpCamera:StopTracking()
	end
	-- Lock released: drop the target anchor so the third-person strategy reverts
	-- to deriving its position offset from the live camera rotation.
	self._aimTargetPosition = nil
	swapToRecoil(self)
end

--[[
	Returns the top composed camera state that CameraStackService will write
	to workspace.CurrentCamera each frame.
]]
function CameraHandlerBase:GetCurrentCFrame(): CFrame
	local topState = self._cameraStackService:GetTopState()
	local cameraQFrame = topState.CameraFrame.QFrame
	return cameraQFrame:toCFrame()
end

function CameraHandlerBase:recoil(recoilAmount: Vector2, rise: number?)
	assert(self._recoilCamera, "_recoilCamera not initialized")
	self._recoilCamera:Recoil(recoilAmount, rise)
end

-- Wind back ONLY this effect's contribution to zero. Safe regardless of
-- player movement during the burst — see RecoilCamera:Reset.
function CameraHandlerBase:resetRecoil()
	assert(self._recoilCamera, "_recoilCamera not initialized")
	self._recoilCamera:Reset()
end

function CameraHandlerBase:Destroy()
	self._maid:DoCleaning()
end

return CameraHandlerBase
