-- Utility setting the npc context
local RS = game:GetService("ReplicatedStorage")
local Controllers = RS.NPC.Controllers
local AttackerController = require(Controllers.AttackerController.AttackerController)
local TargetingController = require(Controllers.TargetingController.TargetingController)
local SoundController = require(Controllers.SoundController.SoundController)
local MovementController = require(Controllers.MovementController.MovementController)

return function(parent: Model, serviceBag: any)
	------- We don use directly the binders, they are reserved to the controllers object domain
	-- local BinderProvider = serviceBag:GetService(_G.BinderProvider)

	-- local WeaponBinder = BinderProvider:Get("Armed")
	-- local AnimationBinder = BinderProvider:Get("AnimationHandler")
	return {
		npc = parent,
		timer = 0,
		lastTriggerTime = 0,
		-------- Binders --------
		-- WeaponHandler = WeaponBinder:Get(parent),
		-- AnimationHandler = AnimationBinder:Get(parent),

		-------- Controlles --------
		SoundController = SoundController.new(parent, serviceBag),
		MovementController = MovementController.new(parent, serviceBag),
		TargetingController = TargetingController.new(parent, serviceBag),
		AttackerController = AttackerController.new(parent, serviceBag),
	}
end
