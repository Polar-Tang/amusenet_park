local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Shared.StateMachine)

local Transition = StateMachine.Transition

-- Interrupts Patrol/Idle the moment the NPC's eyes lock a player.
-- OnDataChanged runs every heartbeat; Scan throttles itself internally.
local TargetFound = Transition.new("Attacking")
TargetFound.Name = "TargetFound"

function TargetFound:OnDataChanged(data)
	return data.TargetController:Scan() and data.TargetController:isCloserEnough()
end

return TargetFound
