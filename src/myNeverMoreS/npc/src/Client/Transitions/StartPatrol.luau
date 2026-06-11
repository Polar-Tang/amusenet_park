local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Shared.StateMachine)
local NpcConstants = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.NpcConstants)

local Transition = StateMachine.Transition

-- Idle -> Patrol after the idle dwell time runs out.
local StartPatrol = Transition.new("Patrol")
StartPatrol.Name = "StartPatrol"

function StartPatrol:OnDataChanged(data)
	return data.timer - data.lastIdleTime >= NpcConstants.IDLE_DURATION
end

return StartPatrol
