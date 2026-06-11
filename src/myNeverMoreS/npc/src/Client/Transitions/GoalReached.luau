local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Shared.StateMachine)

local Transition = StateMachine.Transition

-- Patrol -> Idle once the NPC stands on its goal part.
local GoalReached = Transition.new("Idle")
GoalReached.Name = "GoalReached"

function GoalReached:OnDataChanged(data)
	return data.GoalController:IsGoalReached()
end

return GoalReached
