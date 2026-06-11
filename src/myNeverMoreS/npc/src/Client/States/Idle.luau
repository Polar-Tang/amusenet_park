local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Shared.StateMachine)

local Transitions = script.Parent.Parent.Transitions
local TargetFound = require(Transitions.TargetFound)
local StartPatrol = require(Transitions.StartPatrol)

local State = StateMachine.State

--[=[
	@class Idle

	Dwell on the reached goal for IDLE_DURATION, eyes still open (TargetFound
	can interrupt at any time). StartPatrol compares timer against lastIdleTime.
]=]
local Idle = State.new("Idle")
Idle.Transitions = {
	TargetFound,
	StartPatrol,
}

function Idle:OnEnter(data)
	data.lastIdleTime = data.timer
	data.MovementController:Stop()
end

function Idle:OnHeartbeat(data, deltaTime: number)
	data.timer += deltaTime
end

return Idle
