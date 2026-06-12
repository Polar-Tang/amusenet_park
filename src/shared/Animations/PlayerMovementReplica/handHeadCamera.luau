-- Services
local Players = game:GetService("Players")

-- Motor6D references are character-scoped, so they are resolved lazily per
-- character and re-resolved after a respawn (the caller's render loop keeps
-- running across deaths; module-level capture would drive the destroyed rig
-- forever). The C0 bases are snapshotted on first resolve, before this
-- function ever writes to that rig, so they are the rest-pose offsets.
local rig = nil

local function resolveRig(character: Model)
	local torso = character:FindFirstChild("Torso")
	if not torso then
		return nil
	end

	local neck = torso:FindFirstChild("Neck") -- Motor6D in Head
	local leftShoulder = torso:FindFirstChild("Left Shoulder")
	local rightShoulder = torso:FindFirstChild("Right Shoulder")
	if not (neck and leftShoulder and rightShoulder) then
		return nil
	end

	return {
		character = character,
		neck = neck :: Motor6D,
		leftShoulder = leftShoulder :: Motor6D,
		rightShoulder = rightShoulder :: Motor6D,
		neckC0Base = (neck :: Motor6D).C0,
		RC0Base = (rightShoulder :: Motor6D).C0,
		LC0Base = (leftShoulder :: Motor6D).C0,
	}
end

-- Persistent yaw correction: vertical alignment already comes from lookPitch, so the
-- remaining residual is horizontal (muzzle laterally offset from camera centerline).
-- We accumulate across frames so the spring-like convergence is bounded by GAIN/LIMIT.
local aimYawCorrection = 0


return function(delta, weaponClient)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	if rig == nil or rig.character ~= character then
		rig = resolveRig(character)
		aimYawCorrection = 0
		if rig == nil then
			-- Rig parts not replicated yet (early spawn frames); retry next frame.
			return
		end
	end

	local neck: Motor6D = rig.neck
	local leftShoulder: Motor6D = rig.leftShoulder
	local rightShoulder: Motor6D = rig.rightShoulder
	local neckC0Base: CFrame = rig.neckC0Base
	local RC0Base: CFrame = rig.RC0Base
	local LC0Base: CFrame = rig.LC0Base

	local lookPitch = math.asin(camera.CFrame.LookVector.Y) -- the camera's center angle

	-- The pitch/yaw math assumes the arm's pre-pose points FORWARD (the equip
	-- animation rotated it to the 90° pose). For a hanging-down rest arm, the
	-- same rotation about local X swings the arm through the back hemisphere
	-- as the camera looks down — visibly wrong. Per-arm attribute is set by
	-- the "Equip" animation marker (see ServiceRoot.client.luau) and cleared
	-- on unequip; only animated arms get the correction.
	-- Equip animation rotates the shoulder ~90° around Z in joint space; Transform.UpVector.Y
	-- drops from 1 (rest/identity) toward 0. Threshold at cos(60°)=0.5 stays above locomotion sway.
	local EQUIP_THRESHOLD = 0.5
	local rightArmAnimated = rightShoulder.Transform.UpVector.Y < EQUIP_THRESHOLD
	local leftArmAnimated = leftShoulder.Transform.UpVector.Y < EQUIP_THRESHOLD
	local anyArmAnimated = rightArmAnimated or leftArmAnimated

	local AIM_CORRECTION_GAIN = 0.5
	local AIM_CORRECTION_LIMIT = math.rad(60)

	-- AimPosition is cached on the WeaponClient at EquiTool time, so this
	-- is an O(1) field read instead of the prior per-frame
	-- FindFirstChildOfClass("Tool") + FindFirstChild("AimPosition", true).
	local aim = weaponClient and weaponClient:GetAimPosition()
	-- Only accumulate while a shoulder is actually being driven — otherwise
	-- the aim attachment sits at hip height (arm hanging) and the azimuth
	-- read is meaningless. Freezing at 0 prevents drift that would jolt the
	-- arms when the Equip marker eventually flips the gate on.

	if anyArmAnimated and aim then
		local aimLocal = camera.CFrame:PointToObjectSpace(aim.WorldPosition)
		-- azimuth > 0 when AimPosition sits to the right of camera center;
		-- +Y rotation in Roblox turns left, so we ADD the error to drive aim back to center.
		local azimuth = math.atan2(aimLocal.X, -aimLocal.Z)
		aimYawCorrection =
			math.clamp(aimYawCorrection + AIM_CORRECTION_GAIN * azimuth, -AIM_CORRECTION_LIMIT, AIM_CORRECTION_LIMIT)
	else
		aimYawCorrection = 0
	end

	if rightArmAnimated then
		local pitchAxis = RC0Base:VectorToObjectSpace(Vector3.xAxis)
		local yawAxis = RC0Base:VectorToObjectSpace(Vector3.yAxis)
		rightShoulder.C0 = RC0Base
			* CFrame.fromAxisAngle(pitchAxis, lookPitch)
			* CFrame.fromAxisAngle(yawAxis, aimYawCorrection)
	else
		rightShoulder.C0 = RC0Base
	end

	if leftArmAnimated then
		local leftPitchAxis = LC0Base:VectorToObjectSpace(Vector3.xAxis)
		local leftYawAxis = LC0Base:VectorToObjectSpace(Vector3.yAxis)
		leftShoulder.C0 = LC0Base
			* CFrame.fromAxisAngle(leftPitchAxis, lookPitch)
			* CFrame.fromAxisAngle(leftYawAxis, aimYawCorrection)
	else
		leftShoulder.C0 = LC0Base
	end

	neck.C0 = neckC0Base * CFrame.fromAxisAngle(neckC0Base:VectorToObjectSpace(Vector3.xAxis), lookPitch)

	-- if rightArmAnimated and weaponClient and weaponClient:GetCenterAimToCamera() then
	-- 	-- Same pattern as the shoulder: start from the rest C0 (no position change) and
	-- 	-- apply a pure yaw rotation on top via CFrame.fromAxisAngle. Pitch is already
	-- 	-- handled by the shoulder block above so only the horizontal offset needs correcting.
	-- 	-- Direct calculation (no accumulator): barrel snaps to camera direction every frame.
	-- 	-- armCFrame is last physics step's value (Motor6Ds resolve post-physics) but at
	-- 	-- 60 fps the lag is imperceptible.
	-- 	local rightGrip: Motor6D? = rightArm:FindFirstChild("Handle") :: Motor6D?
	-- 	if rightGrip then
	-- 		local gripC0Base: CFrame = weaponClient:GetGripC0()
	-- 		local camLookLocal = rightArm.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)
	-- 		local yaw = math.atan2(camLookLocal.X, -camLookLocal.Z)
	-- 		local yawAxis = gripC0Base:VectorToObjectSpace(Vector3.yAxis)
	-- 		rightGrip.C0 = gripC0Base * CFrame.fromAxisAngle(yawAxis, yaw)
	-- 	end
	-- end
end
