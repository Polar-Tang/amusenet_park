local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Shared.StateMachine)

local Transitions = script.Parent.Parent.Transitions
local TargetLost = require(Transitions.TargetLost)

local State = StateMachine.State

--[=[
	@class Attacking

	Stand still, face the target and pull the trigger between shoot intervals
	(the ability's own cooldown is the real fire-rate gate; the interval check
	just avoids hammering Execute every heartbeat). TargetLost sends the NPC
	back to Patrol, which resumes the goal the interruption left in flight.
]=]
local Attacking = State.new("Attacking")
Attacking.Transitions = {
	TargetLost,
}

function Attacking:OnEnter(data)
	data.MovementController:ForgotPath()
	data.MovementController:Stop()
end

function Attacking:OnHeartbeat(data, deltaTime: number)
	data.timer += deltaTime

	local target = data.TargetController:Scan()
	if not target then
		return
	end

	if data.timer - data.lastShotTime < data.AttackController:GetShootInterval() then
		return
	end
	data.lastShotTime = data.timer

	-- Face at hrp height so the rig yaws without pitching; the simulated
	-- camera inside AttackController handles the actual vertical aim.
	if data.TargetController:isCloserEnough() then
		data.MovementController:LookTo(Vector3.new(target.Position.X, data.hrp.Position.Y, target.Position.Z))
		data.AttackController:Shoot(target.Position)
	end
end

return Attacking
