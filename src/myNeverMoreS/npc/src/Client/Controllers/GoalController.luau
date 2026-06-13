--[=[
	@class GoalController

	Patrol-goal object domain. Owns which `workspace.goal_*` part (tagged
	`NPC_goals`) the NPC is heading to and the pathfinding towards it. The
	current goal lives here — not in the state — so an interrupted Patrol
	(Attacking) resumes towards the same goal instead of re-rolling.
]=]

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Nevermore.Quenty.promise.Shared.Promise)

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local NpcConstants = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.NpcConstants)

local GoalController = {}
GoalController.__index = GoalController

export type GoalController = typeof(setmetatable(
	{} :: {
		npc: Model,
		hrp: BasePart,
		_serviceBag: any,
		_currentGoal: BasePart?,
	},
	GoalController
))

local random = Random.new()

function GoalController.new(npc: Model, serviceBag: any): GoalController
	local self = setmetatable({}, GoalController)

	self.npc = npc
	self.hrp = npc:WaitForChild("HumanoidRootPart") :: BasePart
	self._serviceBag = serviceBag
	self._currentGoal = nil

	return self :: GoalController
end

function GoalController.GetGoal(self: GoalController): BasePart?
	local goal = self._currentGoal
	if goal and not goal.Parent then
		self._currentGoal = nil
		return nil
	end
	return self._currentGoal
end

function GoalController.IsGoalReached(self: GoalController): boolean
	local goal = self:GetGoal()
	if not goal then
		return false
	end
	-- Planar distance: goals sit on the floor while the hrp floats ~3 studs
	-- above it, so a 3D distance would never read "reached" on tall goals.
	local offset = goal.Position - self.hrp.Position
	local planarDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return planarDistance <= NpcConstants.GOAL_REACHED_DISTANCE
end

-- Keeps the goal an interruption left in flight; only a reached/removed goal
-- is re-rolled. This is what "resumes" Patrol after Attacking.
function GoalController.EnsureGoal(self: GoalController): BasePart?
	local current = self:GetGoal()
	if current and not self:IsGoalReached() then
		return current
	end
	return self:PickNewGoal()
end

function GoalController.PickNewGoal(self: GoalController): BasePart?
	local candidates = {}
	for _, goal in CollectionService:GetTagged(Constants.NPC_GOALS_TAG) do
		if goal:IsA("BasePart") and goal ~= self._currentGoal then
			table.insert(candidates, goal)
		end
	end

	if #candidates == 0 then
		-- A single-goal map keeps re-using it rather than going goalless.
		self._currentGoal = self:GetGoal()
		return self._currentGoal
	end

	self._currentGoal = candidates[random:NextInteger(1, #candidates)]
	return self._currentGoal
end

-- Resolves with a computed Path, rejects when the goal is unreachable.
-- Promise-wrapped because ComputeAsync yields and states must not.
function GoalController.CalculatePath(self: GoalController, goalPosition: Vector3)
	return Promise.spawn(function(resolve, reject)
		local path = PathfindingService:CreatePath()

		local ok, err = pcall(function()
			path:ComputeAsync(self.hrp.Position, goalPosition)
		end)
		if not ok then
			reject(err)
			return
		end
		if path.Status ~= Enum.PathStatus.Success then
			reject(path.Status)
			return
		end

		resolve(path)
	end)
end

function GoalController.Destroy(self: GoalController)
	self._currentGoal = nil
	setmetatable(self :: any, nil)
end

return GoalController
