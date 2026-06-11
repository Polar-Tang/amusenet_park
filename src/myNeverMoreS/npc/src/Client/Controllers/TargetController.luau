--[=[
	@class TargetController

	The NPC's eyes. Simulates a camera at the NPC's head (facing where the rig
	faces) and runs the same `findAimAssistTarget` scan players' auto-aim uses,
	filtered to real player characters so NPCs never hunt each other.

	Scans are throttled to VISION_SCAN_INTERVAL (the LoS raycasts are the
	expensive part) and a found target is remembered through TARGET_LOSS_GRACE
	so one flickering scan doesn't bounce the state machine out of Attacking.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local findAimAssistTarget = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.findAimAssistTarget)
local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local NpcConstants = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.NpcConstants)

local TargetController = {}
TargetController.__index = TargetController

export type TargetController = typeof(setmetatable(
	{} :: {
		npc: Model,
		head: BasePart,
		hrp: BasePart,
		_serviceBag: any,
		_visionCamera: Camera,
		_target: BasePart?,
		_lastScanAt: number,
		_lastSeenAt: number,
	},
	TargetController
))

-- The candidate pool (everything tagged "Armed") includes other NPCs.
local function isPlayerCharacter(character: Model): boolean
	return Players:GetPlayerFromCharacter(character) ~= nil
end

function TargetController.new(npc: Model, serviceBag: any): TargetController
	local self = setmetatable({}, TargetController)

	self.npc = npc
	self._serviceBag = serviceBag
	self.hrp = npc:WaitForChild("HumanoidRootPart") :: BasePart
	self.head = (npc:FindFirstChild("Head") or self.hrp) :: BasePart

	-- findAimAssistTarget wants a Camera; an unparented instance is just a
	-- world-space CFrame holder we re-pose before every scan.
	self._visionCamera = Instance.new("Camera")
	self._target = nil
	self._lastScanAt = 0
	self._lastSeenAt = 0

	return self :: TargetController
end

-- One throttled scan tick. Returns the current target (cached between
-- scans / through the loss grace) or nil once it is really gone. Transitions
-- call this every heartbeat, so the throttle lives here, not in the states.
function TargetController.Scan(self: TargetController): BasePart?
	local now = os.clock()
	if now - self._lastScanAt < NpcConstants.VISION_SCAN_INTERVAL then
		return self:GetTarget()
	end
	self._lastScanAt = now

	-- Eye position from the head, facing from the rig: the NPC sees where it
	-- is turned, and Attacking keeps it turned at the target via LookTo.
	local facing = self.hrp.CFrame.Rotation
	self._visionCamera.CFrame = CFrame.new(self.head.Position) * facing

	local target = findAimAssistTarget(
		getCharacterActor(self.npc),
		self._visionCamera,
		NpcConstants.VISION_RANGE,
		NpcConstants.VISION_FOV_DEG,
		isPlayerCharacter
	)

	if target then
		self._target = target
		self._lastSeenAt = now
	elseif self._target and now - self._lastSeenAt >= NpcConstants.TARGET_LOSS_GRACE then
		self._target = nil
	end

	return self:GetTarget()
end

-- Cached target with a cheap validity re-check (despawned/dead between scans).
function TargetController.GetTarget(self: TargetController): BasePart?
	local target = self._target
	if not target then
		return nil
	end
	if not target:IsDescendantOf(workspace) then
		self._target = nil
		return nil
	end
	return target
end

function TargetController.Destroy(self: TargetController)
	self._visionCamera:Destroy()
	self._target = nil
end

return TargetController
