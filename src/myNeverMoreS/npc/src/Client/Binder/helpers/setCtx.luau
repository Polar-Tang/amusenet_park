-- Utility setting the npc context: builds the controllers (the object domains
-- the states delegate to) and the scratch fields every state/transition shares
-- through the state machine's data table.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = ReplicatedStorage.Nevermore.Custom.npc.src.Client.Controllers
local AttackController = require(Controllers.AttackController)
local GoalController = require(Controllers.GoalController)
local MovementController = require(Controllers.MovementController)
local TargetController = require(Controllers.TargetController)

------- We don't use the binders directly: they are reserved to the
------- controllers' object domains (AttackController wraps "Armed",
------- MovementController wraps "AnimationHandler").
return function(npc: Model, serviceBag: any, maid: any)
	local controllers = {
		GoalController = GoalController.new(npc, serviceBag),
		MovementController = MovementController.new(npc, serviceBag),
		TargetController = TargetController.new(npc, serviceBag),
		AttackController = AttackController.new(npc, serviceBag),
	}

	-- The binder maid owns every controller: untag (or brain handoff) tears
	-- the whole brain down in one DoCleaning.
	for _, controller in controllers do
		maid:GiveTask(controller)
	end

	local ctx = {
		npc = npc,
		humanoid = npc:WaitForChild("Humanoid") :: Humanoid,
		hrp = npc:WaitForChild("HumanoidRootPart") :: BasePart,

		-- State-machine scratch. Kept here (not per-state) so an interrupted
		-- state resumes from where it left off — e.g. Patrol's goal survives
		-- a detour through Attacking via GoalController.EnsureGoal.
		timer = 0,
		lastIdleTime = 0,
		lastShotTime = 0,
		lastRepathCheck = 0,
	}

	for name, controller in controllers do
		ctx[name] = controller
	end

	return ctx
end
