local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Shared.StateMachine)

local Transition = StateMachine.Transition

-- Leaves Attacking once the target has been gone for the full loss grace
-- (Scan keeps reporting the remembered target until then). Goes back to
-- Patrol; if the interrupted goal was already reached, Patrol's GoalReached
-- transition forwards straight to Idle.
local TargetLost = Transition.new("Patrol")
TargetLost.Name = "TargetLost"

function TargetLost:OnDataChanged(data)
	return not (data.TargetController:Scan() and data.TargetController:isCloserEnough())
end

return TargetLost
