--[[
    LerpCamera is a rotation-only delta camera effect. It has two modes:

    * Timed lerp (`StartLerp`): eases the camera rotation toward a goal CFrame
      over a fixed duration and then completes. Used for the recoil-restore
      path.
    * Continuous track (`TrackTo`): follows a *live* goal that is refreshed
      every frame (a moving auto-aim target). It never completes; each frame it
      moves a frame-rate-independent fraction toward the current goal
      (exponential smoothing, `1 - exp(-responsiveness * dt)`), so the follow
      lag is a function of `responsiveness` only, not the weapon's fire rate.

      Track mode keeps its OWN integrated rotation (`_trackRotation`) and emits
      a delta that forces the composed rotation onto it (`base⁻¹ * _trackRotation`),
      so `base * delta == _trackRotation`. This is deliberate: in third person
      the player's camera controller re-asserts its rotation into
      workspace.CurrentCamera every frame, so a lerp that re-reads that base each
      frame would restart from the player's aim and only ever apply a single
      fractional step — it would tremble one step short of the target and never
      reach it. Integrating our own rotation and cancelling the base makes the
      smoothing accumulate across frames (a true hard lock) regardless of what
      the player's controller writes underneath.

    In both modes only the goal's rotation is used; position keeps coming from
    the subclass _cameraState through SummedCamera composition, which lets the
    goal survive a FirstPerson <-> ThirdPerson swap (per-mode camera geometry
    only affects position, not aim).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CameraState = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.CameraState)
local SummedCamera = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.Effects.SummedCamera)

local LerpCamera = {}
LerpCamera.__index = LerpCamera

export type LerpCamera = typeof(setmetatable(
	{} :: {
		CameraState: CameraState.CameraState,
		_startRotation: CFrame,
		_goalRotation: CFrame,
		_trackRotation: CFrame?,
		_timeToLerp: number,
		_lerpTimer: number,
		_lastUpdate: number,
		_isLerping: boolean,
		_isTracking: boolean,
		_responsiveness: number,
		_onComplete: (() -> ())?,
	},
	{} :: typeof({ __index = LerpCamera })
))

function LerpCamera.new(): LerpCamera
	local self: LerpCamera = setmetatable({} :: any, LerpCamera)

	self._isLerping = false
	self._isTracking = false
	self._responsiveness = 0
	self._startRotation = CFrame.identity
	self._goalRotation = CFrame.identity
	self._trackRotation = nil
	self._timeToLerp = 0
	self._lerpTimer = 0
	self._lastUpdate = os.clock()

	return self
end

function LerpCamera.StartLerp(self: LerpCamera, goal: CFrame, time: number)
	self._isLerping = true
	self._isTracking = false
	-- Strip translation: we lerp orientation only so the subclass keeps
	-- driving position. This is what lets the lerp goal stay valid across
	-- FP↔TP swaps (position differs per mode, rotation does not).
	local current = Workspace.CurrentCamera.CFrame
	self._startRotation = current - current.Position
	self._goalRotation = goal - goal.Position
	self._timeToLerp = math.max(time, 0)
	self._lerpTimer = 0
	self._lastUpdate = os.clock()
end

-- Continuous follow toward a live goal (refresh every frame to track a moving
-- target). Unlike StartLerp this never completes; `responsiveness` is the
-- exponential smoothing rate (higher = snappier, lag ≈ 1 / responsiveness).
function LerpCamera.TrackTo(self: LerpCamera, goal: CFrame, responsiveness: number)
	-- Only the goal/responsiveness refresh every frame. `_trackRotation` (the
	-- integrated lock rotation) and `_lastUpdate` (the dt clock) are owned by the
	-- render branch and must NOT be stomped on every Heartbeat call, or the
	-- smoothing would restart from scratch each frame and never converge. They
	-- are (re)initialised lazily in __index on the rising edge of tracking.
	if not self._isTracking then
		self._isTracking = true
		self._trackRotation = nil
	end
	self._isLerping = false
	self._goalRotation = goal - goal.Position
	self._responsiveness = responsiveness
end

-- Stop following the live goal and drop back to an identity delta. No snap-back
-- happens because CameraHandlerBase:StopTrackAim commits the tracked orientation
-- into the Roblox default-camera base (the real player aim) right before this,
-- so once the delta goes identity the player simply continues aiming from where
-- the lock ended.
function LerpCamera.StopTracking(self: LerpCamera)
	self._isTracking = false
	self._trackRotation = nil
end

function LerpCamera.StopLerp(self: LerpCamera)
	self._isLerping = false
	self._lerpTimer = 0
	if self._onComplete then
		local cb = self._onComplete
		self._onComplete = nil
		coroutine.wrap(cb)()
	end
end

function LerpCamera.SetOnComplete(self: LerpCamera, cb: (() -> ())?)
	self._onComplete = cb
end

function LerpCamera.__add(self: LerpCamera, other)
	return SummedCamera.new(self, other):SetMode("Relative")
end

function LerpCamera.__index(self: LerpCamera, index)
	if index == "CameraState" then
		local state = CameraState.new()
		state.FieldOfView = 0

		-- Continuous track: integrate our OWN rotation (`_trackRotation`) a
		-- frame-rate-independent fraction toward the live goal, then force the
		-- composed rotation onto it. SummedCamera (Relative) composes base * delta,
		-- so emitting
		--   delta = inv(baseRotation) * _trackRotation
		-- makes the composed rotation exactly `_trackRotation`, cancelling the
		-- base the player's camera controller re-asserts into
		-- workspace.CurrentCamera every frame. Re-reading that base as the lerp
		-- start (the old behaviour) restarted the smoothing each frame and parked
		-- one step short of the target — the "tremble that never reaches" bug.
		if self._isTracking then
			local now = os.clock()
			local currentCam = Workspace.CurrentCamera.CFrame
			local baseRotation = currentCam - currentCam.Position

			-- Rising edge: ease in from wherever the camera is aiming right now so
			-- the lock doesn't snap. No delta on the seeding frame.
			if self._trackRotation == nil then
				self._trackRotation = baseRotation
				self._lastUpdate = now
				state.CFrame = CFrame.identity
				return state
			end

			local dt = math.max(now - self._lastUpdate, 0)
			self._lastUpdate = now

			local alpha = 1 - math.exp(-(self._responsiveness) * dt)
			self._trackRotation = (self._trackRotation :: CFrame):Lerp(self._goalRotation, alpha)
			state.CFrame = baseRotation:Inverse() * self._trackRotation
			return state
		end

		if not self._isLerping or self._timeToLerp <= 0 then
			-- Defensive: when not lerping we should be off the stack. Return
			-- identity delta so a stray sample is a no-op rather than a jump.
			state.CFrame = CFrame.identity
			return state
		end

		local now = os.clock()
		local dt = math.max(now - self._lastUpdate, 0)
		self._lastUpdate = now
		self._lerpTimer += dt

		local t = math.clamp(self._lerpTimer / self._timeToLerp, 0, 1)
		local targetRotation = self._startRotation:Lerp(self._goalRotation, t)
		-- See the track branch above for the delta = inv(base) * target reasoning.
		local currentCam = Workspace.CurrentCamera.CFrame
		local currentRotation = currentCam - currentCam.Position
		state.CFrame = currentRotation:Inverse() * targetRotation

		if t >= 1 then
			self._isLerping = false
			self._lerpTimer = 0
			if self._onComplete then
				local cb = self._onComplete
				self._onComplete = nil
				coroutine.wrap(cb)()
			end
		end

		return state
	else
		return LerpCamera[index]
	end
end

return LerpCamera
