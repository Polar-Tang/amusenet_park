--[=[
	Drives the local character's neck + shoulder (or torso) Motor6Ds so the rig
	visually points where the camera looks (pitch) and so the equipped weapon's
	muzzle tracks the camera centerline (yaw correction).

	Where the yaw correction lands depends on the camera mode, injected from the
	camera handler via `Init`:
	  - First person: yaw is applied to the shoulders (only the arms are visible).
	  - Third person: yaw is applied to the torso/RootJoint so the whole visible
	    upper body twists toward the aim, and the shoulders carry pitch only.

	The Motor6D references and their rest-pose C0 bases are character-scoped, so
	they are resolved once per character (lazily, on the first frame the rig has
	replicated) and re-resolved only after a respawn — never per frame. The
	caller's render loop keeps running across deaths, so a module-level capture
	would drive the destroyed rig forever; instead the instance re-resolves when
	`LocalPlayer.Character` changes.

	@class HandHeadCamera
]=]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local HandHeadCamera = {}
HandHeadCamera.__index = HandHeadCamera

-- Equip animation rotates the shoulder ~90° around Z in joint space;
-- Transform.UpVector.Y drops from 1 (rest/identity) toward 0. Threshold at
-- cos(60°)=0.5 stays above locomotion sway.
local EQUIP_THRESHOLD = 0.5
-- Persistent yaw correction is accumulated across frames so the spring-like
-- convergence is bounded by GAIN/LIMIT.
local AIM_CORRECTION_GAIN = 0.5
local AIM_CORRECTION_LIMIT = math.rad(60)

type Rig = {
	character: Model,
	neck: Motor6D, -- Motor6D in Head
	leftShoulder: Motor6D,
	rightShoulder: Motor6D,
	rootJoint: Motor6D, -- Motor6D in HumanoidRootPart (HRP -> Torso)
	-- C0 bases snapshotted on first resolve, before this class ever writes to
	-- the rig, so they are the rest-pose offsets.
	neckC0Base: CFrame,
	RC0Base: CFrame,
	LC0Base: CFrame,
	rootJointC0Base: CFrame,
}

-- Params bag for _applyShoulder. `yawCorrection` is optional: when nil the
-- shoulder gets pitch only (third person routes yaw to the torso instead).
type ShoulderParams = {
	shoulder: Motor6D,
	c0Base: CFrame,
	lookPitch: number,
	animated: boolean,
	yawCorrection: number?,
}

export type HandHeadCamera = typeof(setmetatable(
	{} :: {
		_maid: any,
		_rig: Rig?,
		-- Injected by the consumer; nil until a weapon is equipped. Owns the
		-- cached AimPosition attachment read by _updateAimYawCorrection.
		_weaponClient: any?,
		-- Camera handler, injected once via Init; its ObserveIsFirstPerson drives
		-- _isThirdPerson.
		_cameraService: any?,
		_isThirdPerson: boolean,
		-- Persistent horizontal aim correction (vertical alignment already comes
		-- from lookPitch). Accumulated across frames; reset whenever the rig is
		-- re-resolved or no shoulder is being driven.
		_aimYawCorrection: number,
	},
	HandHeadCamera
))

function HandHeadCamera.new(): HandHeadCamera
	local self = setmetatable({}, HandHeadCamera)
	self._maid = Maid.new()
	self._rig = nil
	self._weaponClient = nil
	self._cameraService = nil
	-- Mediator's _isFirstPerson defaults false (third person); the subscription
	-- in Init corrects this immediately on the first equip anyway.
	self._isThirdPerson = true
	self._aimYawCorrection = 0
	return self
end

--[=[
	Injects the WeaponClient (source of the cached AimPosition) and the camera
	handler (source of the first/third-person flag).

	The consumer calls this whenever it (re)resolves the WeaponClient — including
	once per respawn — so the camera subscription is guarded to run a single
	time; only the WeaponClient is refreshed on later calls.
]=]
function HandHeadCamera.Init(self: HandHeadCamera, weaponClient: any?, cameraService: any?)
	self._weaponClient = weaponClient

	if cameraService and not self._cameraService then
		self._cameraService = cameraService
		self._maid:GiveTask(cameraService:ObserveIsFirstPerson():Subscribe(function(isFirstPerson: boolean)
			self._isThirdPerson = not isFirstPerson
		end))
	end
end

--[=[
	Drops a stale WeaponClient (respawn-safe). The render loop re-injects the
	fresh one via Init on the next frame.
]=]
function HandHeadCamera.SetWeaponClient(self: HandHeadCamera, weaponClient: any?)
	self._weaponClient = weaponClient
end

function HandHeadCamera._resolveRig(self: HandHeadCamera, character: Model): Rig?
	local torso = character:FindFirstChild("Torso")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (torso and hrp) then
		return nil
	end

	local neck = torso:FindFirstChild("Neck") -- Motor6D in Head
	local leftShoulder = torso:FindFirstChild("Left Shoulder")
	local rightShoulder = torso:FindFirstChild("Right Shoulder")
	local rootJoint = hrp:FindFirstChild("RootJoint") -- Motor6D HRP -> Torso

	if not (neck and leftShoulder and rightShoulder and rootJoint) then
		return nil
	end

	return {
		character = character,
		neck = neck :: Motor6D,
		leftShoulder = leftShoulder :: Motor6D,
		rightShoulder = rightShoulder :: Motor6D,
		rootJoint = rootJoint :: Motor6D,
		neckC0Base = (neck :: Motor6D).C0,
		RC0Base = (rightShoulder :: Motor6D).C0,
		LC0Base = (leftShoulder :: Motor6D).C0,
		rootJointC0Base = (rootJoint :: Motor6D).C0,
	}
end

--[=[
	Advances the persistent horizontal aim correction toward the camera
	centerline using the WeaponClient's cached AimPosition.

	`azimuth` is the horizontal *error* angle between the camera's forward ray
	and the direction to the aim point — not the rotation to apply. It is fed
	into the accumulator as a proportional error so the correction converges
	across frames (a P-controller) instead of oscillating. Only runs while a
	shoulder is actually animated; otherwise the aim attachment sits at hip
	height (arm hanging) and the azimuth read is meaningless, so the correction
	is frozen back to 0 to avoid a jolt when the equip gate flips on.

	@return number -- the updated, clamped yaw correction in radians
]=]
function HandHeadCamera._updateAimYawCorrection(
	self: HandHeadCamera,
	camera: Camera,
	anyArmAnimated: boolean,
	limit: number?
): number
	-- AimPosition is cached on the WeaponClient at EquiTool time, so this is an
	-- O(1) field read instead of a per-frame FindFirstChildOfClass("Tool") +
	-- FindFirstChild("AimPosition", true).
	local aim = self._weaponClient and self._weaponClient:GetAimPosition()

	if not (anyArmAnimated and aim) then
		self._aimYawCorrection = 0
		return 0
	end

	local aimLocal = camera.CFrame:PointToObjectSpace(aim.WorldPosition)
	-- azimuth > 0 when AimPosition sits to the right of camera center; +Y
	-- rotation in Roblox turns left, so we ADD the error to drive aim to center.
	local azimuth = math.atan2(aimLocal.X, -aimLocal.Z)

	local limitCorrection = limit or AIM_CORRECTION_LIMIT
	self._aimYawCorrection =
		math.clamp(self._aimYawCorrection + AIM_CORRECTION_GAIN * azimuth, -limitCorrection, limitCorrection)
	return self._aimYawCorrection
end

--[=[
	Writes one shoulder's C0: pitch about the joint-local X axis always (when the
	arm is animated), and yaw about the joint-local Y axis only if
	`params.yawCorrection` is present. An un-animated arm is left at its base so
	it never drifts; a present-but-zero yaw still rotates by zero (identity).
]=]
function HandHeadCamera._applyShoulder(self: HandHeadCamera, params: ShoulderParams)
	local shoulder = params.shoulder
	local c0Base = params.c0Base

	if not params.animated then
		shoulder.C0 = c0Base
		return
	end

	local pitchAxis = c0Base:VectorToObjectSpace(Vector3.xAxis)
	local result = c0Base * CFrame.fromAxisAngle(pitchAxis, params.lookPitch)

	if params.yawCorrection ~= nil then
		local yawAxis = c0Base:VectorToObjectSpace(Vector3.yAxis)
		result = result * CFrame.fromAxisAngle(yawAxis, params.yawCorrection)
	end

	shoulder.C0 = result
end

--[=[
	Twists the whole upper body toward the aim by rotating the RootJoint C0 about
	its joint-local Y. A zero correction restores the rest-pose base (used in
	first person so the torso never carries leftover twist).
]=]
function HandHeadCamera._applyTorso(self: HandHeadCamera, rootJoint: Motor6D, c0Base: CFrame, yawCorrection: number)
	if yawCorrection == 0 then
		rootJoint.C0 = c0Base
		return
	end

	local yawAxis = c0Base:VectorToObjectSpace(Vector3.yAxis)
	rootJoint.C0 = c0Base * CFrame.fromAxisAngle(yawAxis, yawCorrection)
end

function HandHeadCamera._applyHandle(self: HandHeadCamera, handleJOint: Motor6D, c0Base: CFrame, yawCorrection: number)
	if yawCorrection == 0 then
		handleJOint.C0 = c0Base
		return
	end

	local yawAxis = c0Base:VectorToObjectSpace(Vector3.yAxis)
	handleJOint.C0 = c0Base * CFrame.fromAxisAngle(yawAxis, yawCorrection)
end

function HandHeadCamera.Update(self: HandHeadCamera, _delta: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local character = Players.LocalPlayer.Character
	if not character then
		return
	end

	local rig = self._rig
	if rig == nil or rig.character ~= character then
		rig = self:_resolveRig(character)
		self._rig = rig
		self._aimYawCorrection = 0
		if rig == nil then
			-- Rig parts not replicated yet (early spawn frames); retry next frame.
			return
		end
	end

	local lookPitch = math.asin(camera.CFrame.LookVector.Y) -- the camera's center angle

	-- The pitch/yaw math assumes the arm's pre-pose points FORWARD (the equip
	-- animation rotated it to the 90° pose). For a hanging-down rest arm, the
	-- same rotation about local X swings the arm through the back hemisphere as
	-- the camera looks down — visibly wrong. Per-arm pose is set by the "Equip"
	-- animation marker; only animated arms get the correction.
	local rightArmAnimated = rig.rightShoulder.Transform.UpVector.Y < EQUIP_THRESHOLD
	local leftArmAnimated = rig.leftShoulder.Transform.UpVector.Y < EQUIP_THRESHOLD
	local anyArmAnimated = rightArmAnimated or leftArmAnimated

	if self._isThirdPerson then
		local yawCorrection = self:_updateAimYawCorrection(camera, anyArmAnimated, math.rad(15))

		-- Yaw twists the visible upper body; shoulders carry pitch only (no
		-- yawCorrection field, so _applyShoulder skips the yaw rotation).
		local handle, HandleC0 = self._weaponClient:GetHandle()
		if handle then
			self:_applyHandle(handle, HandleC0, yawCorrection)
		end

		self:_applyTorso(rig.rootJoint, rig.rootJointC0Base, 0)
		self:_applyShoulder({
			shoulder = rig.rightShoulder,
			c0Base = rig.RC0Base,
			lookPitch = lookPitch,
			animated = rightArmAnimated,
			yawCorrection = yawCorrection,
		})
		self:_applyShoulder({
			shoulder = rig.leftShoulder,
			c0Base = rig.LC0Base,
			lookPitch = lookPitch,
			animated = leftArmAnimated,
			yawCorrection = yawCorrection,
		})
	else
		local yawCorrection = self:_updateAimYawCorrection(camera, anyArmAnimated)

		-- First person: only the arms are visible, so yaw rides the shoulders and
		-- the torso is held at its base.
		self:_applyTorso(rig.rootJoint, rig.rootJointC0Base, 0)
		self:_applyShoulder({
			shoulder = rig.rightShoulder,
			c0Base = rig.RC0Base,
			lookPitch = lookPitch,
			animated = rightArmAnimated,
			yawCorrection = yawCorrection,
		})
		self:_applyShoulder({
			shoulder = rig.leftShoulder,
			c0Base = rig.LC0Base,
			lookPitch = lookPitch,
			animated = leftArmAnimated,
			yawCorrection = yawCorrection,
		})
	end

	rig.neck.C0 = rig.neckC0Base * CFrame.fromAxisAngle(rig.neckC0Base:VectorToObjectSpace(Vector3.xAxis), lookPitch)
end

function HandHeadCamera.Destroy(self: HandHeadCamera)
	self._maid:DoCleaning()
end

return HandHeadCamera
