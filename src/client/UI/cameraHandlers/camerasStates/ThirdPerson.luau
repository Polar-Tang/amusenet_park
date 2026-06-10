local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

--[[
	Third-person mode strategy. No longer extends CameraHandlerBase: the
	mediator owns the persistent _cameraState + effects, and this class just
	binds a render step that writes the third-person CFrame into the shared
	state. Constructed/destroyed on each mode toggle; the effects survive.
]]
local ThirdPersonCamera = {}
ThirdPersonCamera.__index = ThirdPersonCamera

ThirdPersonCamera.CAMERA_OFFSET = Vector3.new(1.5, 1.5, 7)

-- Smoothing rate (per second) for the locked over-shoulder offset DIRECTION.
-- Matched to Constants.AIM_ASSIST_RESPONSIVENESS so the camera body and the look
-- chase the target at the same pace -- mismatched rates are themselves a source
-- of body/character drift while walking.
ThirdPersonCamera.AIM_OFFSET_RESPONSIVENESS = 16

function ThirdPersonCamera.new(cameraState, mediator)
	local self = setmetatable({}, ThirdPersonCamera)

	self._cameraState = cameraState
	-- Optional: the CameraMediator, read each frame for the live auto-aim target
	-- position (CameraHandlerBase._aimTargetPosition). See _resolveOffset.
	self._mediator = mediator
	-- Loop-break state for the locked offset: a horizontal aim direction we
	-- integrate ourselves each render frame (see _resolveOffset). nil when not
	-- locked, re-seeded on the next lock.
	self._smoothedAimDir = nil
	self._lastOffsetUpdate = os.clock()
	self._maid = Maid.new()
	self._key = HttpService:GenerateGUID(false)

	local stepName = "ThirdPersonShooter_" .. self._key
	RunService:BindToRenderStep(stepName, Enum.RenderPriority.Camera.Value, function()
		local currentCamera = Workspace.CurrentCamera
		local baseCFrame = currentCamera.CFrame
		local rotationOnly = baseCFrame - baseCFrame.Position
		local subjectPosition = ThirdPersonCamera.getCameraSubjectPosition(currentCamera)
		local offset = self:_resolveOffset(rotationOnly, subjectPosition)

		-- The rotation must stay `rotationOnly` (the live camera rotation): the
		-- LerpCamera delta is built as inv(thisRotation) * trackRotation, so the
		-- composition only resolves to the locked aim if the position state carries
		-- exactly this rotation. Only the POSITION (offset) is anchored differently.
		local desired = CFrame.new(subjectPosition + offset) * rotationOnly

		self._cameraState.CFrame = desired
	end)

	self._maid:GiveTask(function()
		RunService:UnbindFromRenderStep(stepName)
	end)

	return self
end

--[[
	Resolve the camera-position offset (subject -> camera).

	Unlocked: derive it from the full live camera rotation, so the camera orbits
	behind wherever the player aims (pitch included).

	Auto-aim locked: anchor the offset on the horizontal character -> target
	direction, NOT on the camera rotation. This is the loop-break. Deriving the
	offset from the lock rotation is circular -- camera = subject + R(lock)*OFFSET
	and the lock goal is lookAt(camera, target), so R depends on camera which
	depends on R; while the player walks the moving subject keeps that fixed point
	out of reach and the camera body drifts off the character. The character ->
	target direction is a physical quantity the lock rotation can't move, so the
	loop is cut.

	But targetPosition only refreshes at the slow aim-assist scan rate, so using it
	raw steps the offset between ticks (the "skip"). We fix that here, not by
	stepping back to a camera-derived offset, but by integrating the offset
	direction OURSELVES every render frame (exponential smoothing toward the latest
	known target direction). That bridges the scan ticks into a continuous glide
	while staying anchored on the (loop-free) target direction. Yaw-only, so the
	camera height is stable; the look still tracks the target fully via LerpCamera.
]]
function ThirdPersonCamera._resolveOffset(self, rotationOnly: CFrame, subjectPosition: Vector3): Vector3
	local targetPosition = self._mediator and self._mediator._aimTargetPosition
	if targetPosition then
		local horizontal = Vector3.new(targetPosition.X - subjectPosition.X, 0, targetPosition.Z - subjectPosition.Z)
		if horizontal.Magnitude > 1e-3 then
			local desiredDir = horizontal.Unit
			local now = os.clock()
			local dt = math.max(now - self._lastOffsetUpdate, 0)
			self._lastOffsetUpdate = now

			if self._smoothedAimDir == nil then
				-- Rising edge of the lock: seed from the current direction, no jump.
				self._smoothedAimDir = desiredDir
			else
				local alpha = 1 - math.exp(-ThirdPersonCamera.AIM_OFFSET_RESPONSIVENESS * dt)
				local blended = (self._smoothedAimDir :: Vector3):Lerp(desiredDir, alpha)
				-- Renormalise; fall back to the raw direction if the blend collapses
				-- near zero (near-opposite vectors), which can't happen for a target
				-- kept in front of the player but is cheap to guard.
				self._smoothedAimDir = blended.Magnitude > 1e-3 and blended.Unit or desiredDir
			end

			local yawRotation = CFrame.lookAt(Vector3.zero, self._smoothedAimDir)
			return yawRotation:VectorToWorldSpace(ThirdPersonCamera.CAMERA_OFFSET)
		end
	end

	-- Not locked (or degenerate direction): drop the integrator so the next lock
	-- re-seeds, and fall back to the live camera-rotation offset.
	self._smoothedAimDir = nil
	return rotationOnly:VectorToWorldSpace(ThirdPersonCamera.CAMERA_OFFSET)
end

--[[
	return the subject camera position
]]
function ThirdPersonCamera.getCameraSubjectPosition(currentCamera: Camera): Vector3
	local subject = currentCamera.CameraSubject
	if subject:IsA("BasePart") then
		return subject.Position
	end

	if subject:IsA("Humanoid") then
		local rootPart = subject.RootPart
		if rootPart then
			return rootPart.Position
		end

		local character = subject.Parent
		if character and character:IsA("Model") then
			local primaryPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
			if primaryPart and primaryPart:IsA("BasePart") then
				return primaryPart.Position
			end
		end
	end

	return currentCamera.CFrame.Position
end

function ThirdPersonCamera.Destroy(self)
	self._maid:DoCleaning()
end

return ThirdPersonCamera
