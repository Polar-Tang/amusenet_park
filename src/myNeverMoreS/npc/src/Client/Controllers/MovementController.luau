--[=[
	@class MovementController (NPC)

	Drives the NPC humanoid along computed Paths. Owns only move state — what
	to move to is the GoalController's domain, when to move is the states'.

	Maids: `self.maid` is a private move-scratch maid (cleaned on every new
	move / Stop) and `self.maid_waypoints` holds the per-waypoint race
	(MoveToFinished vs timeout). Neither is the binder maid: the binder maid
	owns this controller, and cleaning a binder-level maid from inside a move
	would tear down the sibling controllers mid-move.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local Promise = require(ReplicatedStorage.Nevermore.Quenty.promise.Shared.Promise)

local MovementController = {}
MovementController.__index = MovementController

export type MovementController = typeof(setmetatable(
	{} :: {
		npc: Model,
		humanoid: Humanoid,
		hrp: BasePart,
		isMoving: boolean,
		maid: any,
		maid_waypoints: any,
		_serviceBag: any,
		_currentMovePromise: any,
		_walkAnimBroken: boolean,
	},
	MovementController
))

local GRAVITY = Vector3.new(0, -workspace.Gravity, 0)
-- Fixed flight time of the ballistic unstuck jump (see _jumpToWaypoint).
local JUMP_TIME = 0.5
-- Humanoid:MoveTo's built-in 8s timeout is way too slow for a combat NPC;
-- a waypoint taking longer than this counts as stuck.
local WAYPOINT_TIMEOUT = 1
local LOOK_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function MovementController.new(npc: Model, serviceBag: any): MovementController
	local self = setmetatable({}, MovementController)

	self.npc = npc
	self._serviceBag = serviceBag
	self.humanoid = npc:WaitForChild("Humanoid") :: Humanoid
	self.hrp = npc:WaitForChild("HumanoidRootPart") :: BasePart
	self.isMoving = false
	self._currentMovePromise = nil
	self._walkAnimBroken = false

	self.maid = Maid.new()
	self.maid_waypoints = Maid.new()
	self.maid:GiveTask(self.maid_waypoints)

	return self :: MovementController
end

-- Best-effort walk animation. NPCs only have an AnimationHandler when the
-- server bound one, and the gun set ships no "Walk" — so this silently
-- disables itself on the first failure instead of erroring every waypoint.
function MovementController._setWalkAnim(self: MovementController, playing: boolean)
	if self._walkAnimBroken then
		return
	end

	local BinderProvider = self._serviceBag:GetService(_G.BinderProvider)
	local animBinder = BinderProvider:Get("AnimationHandler")
	local animHandler = animBinder and animBinder:Get(self.npc)
	if not animHandler then
		return
	end

	local ok = pcall(function()
		animHandler:LoadAnimation(playing, "Walk")
	end)
	if not ok then
		self._walkAnimBroken = true
	end
end

function MovementController.ForgotPath(self: MovementController)
	if self._currentMovePromise then
		self._currentMovePromise:Destroy()
		self._currentMovePromise = nil
	end
end

function MovementController.MoveTo(self: MovementController, path: Path)
	self.maid:DoCleaning()

	self._currentMovePromise = Promise.new(function(resolve, reject)
		local waypoints = path:GetWaypoints()
		if #waypoints == 0 then
			resolve()
			return
		end

		self.isMoving = true
		self:_setWalkAnim(true)

		local currentIndex = 1
		local function moveNext()
			-- Stop() flips isMoving; the in-flight callback chain ends here.
			if not self.isMoving then
				resolve()
				return
			end
			if currentIndex > #waypoints then
				self.isMoving = false
				self:_setWalkAnim(false)
				self.maid_waypoints:DoCleaning()
				resolve()
				return
			end

			local waypoint = waypoints[currentIndex]
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				self.humanoid.Jump = true
			end

			self:_moveToWaypoint(waypoint.Position, function(reached)
				if reached then
					currentIndex += 1
					moveNext()
				else
					-- Stuck on geometry the walk couldn't clear: ballistic
					-- fallback to the same waypoint, then continue.
					self:_jumpToWaypoint(waypoint.Position, function()
						currentIndex += 1
						moveNext()
					end)
				end
			end)
		end
		moveNext()
	end)

	self._currentMovePromise:Catch(function()
		-- Destroyed by ForgotPath (or a rejected leg): make sure no anim and
		-- no waypoint race outlives the move.
		self:Stop()
	end)

	return self._currentMovePromise
end

function MovementController._moveToWaypoint(
	self: MovementController,
	targetPosition: Vector3,
	onComplete: (boolean) -> ()
)
	self.maid_waypoints:DoCleaning()

	-- MoveToFinished and the stuck-timeout race; only the first outcome counts.
	local finished = false
	local function complete(reached: boolean)
		if finished then
			return
		end
		finished = true
		onComplete(reached)
	end

	self.maid_waypoints:GiveTask(self.humanoid.MoveToFinished:Connect(function(reached)
		complete(reached)
	end))
	self.maid_waypoints:GiveTask(task.delay(WAYPOINT_TIMEOUT, function()
		complete(false)
	end))

	self.humanoid:MoveTo(targetPosition)
end

-- Ballistic unstuck: arcs the model to the waypoint over JUMP_TIME with the
-- kinematic v0 = (p1 - p0 - 0.5*g*T^2) / T, stepping Model:MoveTo each frame.
function MovementController._jumpToWaypoint(
	self: MovementController,
	targetPosition: Vector3,
	onComplete: (boolean) -> ()
)
	self.maid_waypoints:DoCleaning()

	local startPosition = self.hrp.Position
	local initialVelocity = (targetPosition - startPosition - 0.5 * GRAVITY * JUMP_TIME ^ 2) / JUMP_TIME
	local t = 0

	local moveConnection
	moveConnection = RunService.Heartbeat:Connect(function(deltaTime)
		t += deltaTime
		if t > JUMP_TIME then
			moveConnection:Disconnect()
			onComplete(true)
			return
		end

		-- s = s0 + v0*t + 0.5*g*t^2
		local newPosition = startPosition + initialVelocity * t + 0.5 * GRAVITY * t ^ 2
		self.npc:MoveTo(newPosition)
	end)
	self.maid_waypoints:GiveTask(moveConnection)
end

-- Cancels the in-flight move without touching anything else. Safe to call
-- when not moving.
function MovementController.Stop(self: MovementController)
	self.maid:DoCleaning()
	self.isMoving = false
	self:_setWalkAnim(false)
end

-- Smoothly face a world position (Y is the caller's problem: pass a position
-- at hrp height to avoid pitching the whole rig).
function MovementController.LookTo(self: MovementController, to: Vector3)
	local currentCFrame = self.hrp.CFrame
	if (to - currentCFrame.Position).Magnitude < 0.001 then
		return nil
	end

	local tween = TweenService:Create(self.hrp, LOOK_TWEEN_INFO, {
		CFrame = CFrame.lookAt(currentCFrame.Position, to),
	})
	self.maid._lookTween = tween
	tween:Play()

	return tween
end

function MovementController.Destroy(self: MovementController)
	-- No setmetatable(nil) here: ForgotPath rejects the move promise, whose
	-- Catch calls self:Stop() and may land a tick later.
	self:ForgotPath()
	self.maid:DoCleaning()
	self.isMoving = false
end

return MovementController
