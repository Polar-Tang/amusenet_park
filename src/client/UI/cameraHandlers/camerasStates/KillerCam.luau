local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

--[[
	Death-cam mode strategy: over-the-shoulder view of the character that
	killed the local player, alive until the player clicks respawn.

	Why the killer's Head and not their "camera": a remote player's Camera is
	never replicated, and the NPC brain's eye is an unparented
	`Instance.new("Camera")` that only exists on the brain-owner client. But
	the NPC fabricates that eye FROM its Head (`AttackController.Shoot` does
	`CFrame.lookAt(head.Position, target)`), so rebuilding the view from the
	replicated Head CFrame is exactly as faithful — and it unifies player and
	NPC killers with zero extra remotes.

	Same shape as ThirdPerson/FirstPerson: constructed/destroyed by the
	mediator, owns only a render step that writes into the mediator's shared
	_cameraState (so the recoil/lerp combos on the camera stack keep working).
]]
local KillerCam = {}
KillerCam.__index = KillerCam

-- Over-shoulder offset in the killer's head space (X right, Y up, Z back).
KillerCam.CAMERA_OFFSET = Vector3.new(1.5, 1.5, 7)

-- Exponential smoothing rate (per second) for the fly-to-killer transition
-- and for tracking the killer while they keep moving.
KillerCam.FOLLOW_RESPONSIVENESS = 6

function KillerCam.new(cameraState, killerCharacter: Model?)
	local self = setmetatable({}, KillerCam)

	self._cameraState = cameraState
	self._killerCharacter = killerCharacter
	self._maid = Maid.new()
	self._key = HttpService:GenerateGUID(false)
	-- Seed from the live camera so the death cut glides instead of snapping.
	self._currentCFrame = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame or cameraState.CFrame

	local stepName = "KillerCam_" .. self._key
	RunService:BindToRenderStep(stepName, Enum.RenderPriority.Camera.Value, function(deltaTime)
		local desired = self:_resolveDesiredCFrame()
		if desired then
			local alpha = 1 - math.exp(-KillerCam.FOLLOW_RESPONSIVENESS * deltaTime)
			self._currentCFrame = self._currentCFrame:Lerp(desired, alpha)
		end
		-- No desired CFrame (no killer / killer despawned): hold the last
		-- frame instead of writing garbage — the camera freezes in place.
		self._cameraState.CFrame = self._currentCFrame
	end)

	self._maid:GiveTask(function()
		RunService:UnbindFromRenderStep(stepName)
	end)

	return self
end

--[[
	Behind-the-head CFrame fabricated from the killer's replicated rig.
	Resolved every frame (never cached): the killer may despawn, die or
	respawn into a new Model while we spectate.
]]
function KillerCam._resolveDesiredCFrame(self): CFrame?
	local killer = self._killerCharacter
	if not killer or killer.Parent == nil then
		return nil
	end

	local head = killer:FindFirstChild("Head") or killer:FindFirstChild("HumanoidRootPart")
	if not head or not head:IsA("BasePart") then
		return nil
	end

	local headCFrame = head.CFrame
	local rotationOnly = headCFrame - headCFrame.Position
	local offset = rotationOnly:VectorToWorldSpace(KillerCam.CAMERA_OFFSET)
	return CFrame.new(headCFrame.Position + offset) * rotationOnly
end

function KillerCam.Destroy(self)
	self._maid:DoCleaning()
	self._killerCharacter = nil
end

return KillerCam
