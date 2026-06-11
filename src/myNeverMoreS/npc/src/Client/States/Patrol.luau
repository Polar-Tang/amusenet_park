local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Shared.StateMachine)

local NpcConstants = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.NpcConstants)

local Transitions = script.Parent.Parent.Transitions
local TargetFound = require(Transitions.TargetFound)
local GoalReached = require(Transitions.GoalReached)

local State = StateMachine.State

--[=[
	@class Patrol

	Default state: walk towards the current `NPC_goals` part. The goal itself
	lives in GoalController so an Attacking detour resumes the same goal
	(EnsureGoal only re-rolls a reached/removed one).
]=]
local Patrol = State.new("Patrol")
Patrol.Transitions = {
	TargetFound,
	GoalReached,
}

-- Path to the in-flight goal (or a fresh one) and start walking it. Rejected
-- paths (unreachable goal) re-roll so the NPC never stands stuck forever.
local function moveTowardsGoal(data)
	local goal = data.GoalController:EnsureGoal()
	if not goal then
		return
	end

	data.GoalController
		:CalculatePath(goal.Position)
		:Then(function(path)
			data.MovementController:ForgotPath()
			data.MovementController:MoveTo(path)
		end)
		:Catch(function()
			data.GoalController:PickNewGoal()
		end)
end

function Patrol:OnEnter(data)
	data.lastRepathCheck = data.timer
	moveTowardsGoal(data)
end

function Patrol:OnHeartbeat(data, deltaTime: number)
	data.timer += deltaTime

	-- Stuck watchdog: an interrupted/failed move leaves isMoving false; kick
	-- the walk back off every REPATH_INTERVAL instead of every frame.
	if data.timer - data.lastRepathCheck < NpcConstants.REPATH_INTERVAL then
		return
	end
	data.lastRepathCheck = data.timer

	if not data.MovementController.isMoving then
		moveTowardsGoal(data)
	end
end

function Patrol:OnLeave(data)
	data.MovementController:Stop()
end

return Patrol
