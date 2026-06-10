--[=[
	@class Weapon (server)

	The "Armed" binder, server side. One instance per tagged character; it
	owns the *context* (defense system, hitbox-promise registry, character
	state lock) and delegates per-weapon behavior to the currently-equipped
	`WeaponStrategy` stored in `self._weapon`.

	Lifecycle:
	  * `Binder._add` -> `Weapon.new(char, serviceBag)` once per character.
	  * `EquiTool(name)` swaps in a new strategy. If a strategy is already
	    equipped, it is destroyed first so its abilities (and their maids)
	    are torn down before the new strategy is installed.
	  * `UnequiTool()` destroys the current strategy and clears `_weapon`.
	    Safe to call when no strategy is equipped.
	  * `Destroy()` runs when the character is untagged (player despawn).
	    It also tears down the current strategy and cancels every in-flight
	    hitbox promise.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Server.types.weaponTypes)
local require = require(script.Parent.loader).load(script)
local CombatConfig = require("CombatConfig")
local EffectService = require("EffectService")
local Maid = require("Maid")
local MovementLock = require("MovementLock")
local PromiseRegistry = require("PromiseRegistry")
local WeaponDefenseSystem = require("WeaponDefenseSystem")

local BaseObject = require("BaseObject")
local Weapon = {}
Weapon.__index = Weapon

local Strategies = {
	["fist"] = require("Fist"),
	["gun"] = require("Gun"),
	["ak-47"] = require("Ak_47"),
	grenade = require("Grenade"),
}

function Weapon.new(char: Model, serviceBag, binders): weaponTypes.WeaponContext
	local self = setmetatable(BaseObject.new(char), Weapon)
	self._maid = Maid.new()
	self.Char = char
	self._weapon = nil
	self._serviceBag = serviceBag
	self.Humanoid = char:WaitForChild("Humanoid")

	self._hitboxPromiseRegistry = PromiseRegistry.new()

	self._animHandler = binders:Get("AnimationHandler"):Get(char)

	self._character_state = MovementLock.new(char, serviceBag)
	self._weaponDefense = WeaponDefenseSystem.new(self)

	self._defenseChain = {}
	self._contexts = {}

	if self.Humanoid.RigType == Enum.HumanoidRigType.R15 then
		self.armName = "RightLowerArm"
		self.torso = self.Char:FindFirstChild("UpperTorso")
	else
		self.armName = "Right Arm"
		self.torso = self.Char:FindFirstChild("Torso")
	end
	return (self :: any) :: weaponTypes.WeaponContext
end

function Weapon.Execute(self: weaponTypes.WeaponContext, action, params)
	if not self._weapon then
		return
	end
	self._weapon:Execute(action, params)
end

function Weapon.RegisterAttackEffect(self: weaponTypes.WeaponContext, attackId, ctx)
	self._contexts[attackId] = ctx
end

function Weapon.GetAttackEffect(self: weaponTypes.WeaponContext, attackId)
	return self._contexts[attackId]
end

function Weapon.TakeHit(self: weaponTypes.WeaponContext, context)
	context.anchorState = self._character_state
	-- all the effect that the ability can cause happens here
	EffectService:Apply(context)
end

function Weapon.increaseDmgCount(self: weaponTypes.WeaponContext, increase: number)
	assert(typeof(increase) == "number", "increase value must be a number")
	if self._weapon then
		self._weapon:_increaseDmgCount(increase)
	else
		print("call increase dmg cound on unarmed pal")
	end
end

-- The attack sends hitData to the defender's Weapon binder; the defender
-- checks if a defense mechanism is already active by routing through here.
function Weapon.OnIncomingAttack(self: weaponTypes.WeaponContext, hitData)
	task.spawn(function()
		self._weaponDefense:ProcessAttack(hitData)
	end)
end

function Weapon.GetStrategy(self: weaponTypes.WeaponContext)
	return self._weapon
end

function Weapon.SetActiveDefense(self: weaponTypes.WeaponContext, ctx)
	self._weaponDefense:SetActiveDefense(ctx)
end

function Weapon.ClearActiveDefense(self: weaponTypes.WeaponContext, priority)
	self._weaponDefense:DeactivateDefense(priority)
end

function Weapon.EquiTool(self: weaponTypes.WeaponContext, toolName: string)
	if not toolName or typeof(toolName) ~= "string" then
		warn("invalid toolname ", toolName)
		return
	end
	if not Strategies[toolName] then
		warn("There's no such strategy as " .. toolName)
		return
	end

	-- Swap: tear down the previous strategy before installing the new one,
	-- otherwise every previous ability + its connections leaks until the
	-- character is untagged.
	if self._weapon then
		self._weapon:Destroy()
		self._weapon = nil
	end

	-- Run the previous weapon's equip-cleanup before installing the next one.
	if self._onEquipCleanup then
		self._onEquipCleanup()
		self._onEquipCleanup = nil
	end

	self.tool_name = toolName
	self._weapon = Strategies[toolName].new(self.Char, self._serviceBag)
	if self._weapon and self._weapon.Init then
		self._weapon:Init()
	end

	local tool: Tool? = self.Char:FindFirstChildOfClass("Tool")
	if tool then
		local handle = assert(tool:FindFirstChild("Handle"), "tool is missing a Handle") :: BasePart

		local arm = assert(self.Char:FindFirstChild("Right Arm"), "character is missing " .. self.armName) :: BasePart

		-- Motor6D route: keep both joints animatable. Roblox's auto "RightGrip"
		-- weld re-derives the Handle from the hand every physics step and would
		-- fight a Motor6D on the same parts, so drop it (and RequiresHandle so it
		-- isn't recreated) and drive the grip ourselves.
		tool.RequiresHandle = false
		local rightGrip = arm:FindFirstChild("RightGrip")
		if rightGrip then
			rightGrip:Destroy()
		end
		
		-- arm -> Handle. C0/C1 place Handle at the per-weapon grip point on the arm;
		-- each weapon defines its own gripC0/gripC1 in CombatConfig.
		local weaponConfig = CombatConfig:getweapon(toolName)
		local gripMotor = Instance.new("Motor6D")
		gripMotor.Name = "Handle"
		gripMotor.Part0 = arm
		gripMotor.Part1 = handle
		gripMotor.C0 = weaponConfig.gripC0
		gripMotor.C1 = weaponConfig.gripC1
		gripMotor.Parent = arm
		self._maid.GripMotor = gripMotor

	end

	-- Per-weapon server equip hook (CombatConfig.onEquipCB). May return a
	-- teardown closure that we run on the next swap / unequip / destroy.
	local config = CombatConfig:getweapon(toolName)
	if config and config.onEquipCB then
		self._onEquipCleanup = config.onEquipCB(self)
	end
end

function Weapon.UnequiTool(self: weaponTypes.WeaponContext)
	if self._onEquipCleanup then
		self._onEquipCleanup()
		self._onEquipCleanup = nil
	end
	if not self._weapon then
		return
	end
	self._weapon:Destroy()
	self._weapon = nil
	self.tool_name = nil
end

function Weapon.GetAction(self: weaponTypes.WeaponContext, action)
	if not self._weapon then
		return nil
	end
	return self._weapon:GetAction(action)
end

function Weapon.registryTool(self: weaponTypes.WeaponContext, toolName: string)
	self.tool_name = toolName
end

-- If the sound thing causes issues we move it to a facade.
-- NOTE: this assumes a `self.Folder` was set somewhere upstream; it is not.
-- Left in place for the existing callers; do not introduce new callers until
-- the sound folder wiring is sorted.
function Weapon.PlaySound(self: weaponTypes.WeaponContext, lifeTime: number?, nameSound: string)
	local dur = lifeTime or 2
	local folder = (self :: any).Folder
	if not folder then
		warn("Weapon.PlaySound: no sound folder configured for ", self.tool_name)
		return
	end
	local Sound = folder[nameSound]:Clone()
	Sound.Parent = self.Char:WaitForChild("HumanoidRootPart")
	Sound:Play()
	Debris:AddItem(Sound, dur)
end

function Weapon.ResolveHitboxPromise(self: weaponTypes.WeaponContext, attackID, hitTargets, hitPart)
	return self._hitboxPromiseRegistry:Resolve(attackID, hitTargets, hitPart)
end

function Weapon.AddHitToPromise(self: weaponTypes.WeaponContext, attackID, hitTarget, hitPart)
	return self._hitboxPromiseRegistry:AddHit(attackID, hitTarget, hitPart)
end

function Weapon.RejectHitboxPromise(self: weaponTypes.WeaponContext, attackID, ...)
	return self._hitboxPromiseRegistry:Reject(attackID, ...)
end

function Weapon.RegisterHitboxPromise(self: weaponTypes.WeaponContext, data)
	self._hitboxPromiseRegistry:Register(data)
end

-- Called by the binder when the character is untagged. Cleans the current
-- strategy + all server-side context. `MaidTaskUtils.doTask` in the binder
-- invokes this automatically; do not call it manually for a tool swap —
-- use `UnequiTool` instead.
function Weapon.Destroy(self: weaponTypes.WeaponContext)
	if self._onEquipCleanup then
		self._onEquipCleanup()
		self._onEquipCleanup = nil
	end
	self._hitboxPromiseRegistry:CancelAll()
	if self._weapon then
		self._weapon:Destroy()
		self._weapon = nil
	end
	if self._weaponDefense and self._weaponDefense.Destroy then
		self._weaponDefense:Destroy()
	end
	self._maid:DoCleaning()
end

return Weapon
