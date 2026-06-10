-- Services
local Players = game:GetService("Players")

-- Motor6D references (adjust paths to your rig)
local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
-- local head = character:WaitForChild("Head")

local torso = character:WaitForChild("Torso")
local rightArm = character:WaitForChild("Right Arm")

local neck: Motor6D = torso:WaitForChild("Neck") -- Motor6D in Head
local leftShoulder: Motor6D = torso:WaitForChild("Left Shoulder")
local rightShoulder: Motor6D = torso:WaitForChild("Right Shoulder")

-- Store the ORIGINAL C0 values so we apply look-at on TOP of them
-- These are the rest-pose offsets the rig defines
local neckC0Base: CFrame = neck.C0
local RC0Base = rightShoulder.C0
local LC0Base = leftShoulder.C0

local Mouse = Players.LocalPlayer:GetMouse()

-- Persistent yaw correction: vertical alignment already comes from lookPitch, so the
-- remaining residual is horizontal (muzzle laterally offset from camera centerline).
-- We accumulate across frames so the spring-like convergence is bounded by GAIN/LIMIT.
local aimYawCorrection = 0


return function(delta, weaponClient)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

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
