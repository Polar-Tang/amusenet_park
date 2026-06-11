--[=[
	@class AttackController

	The NPC's trigger finger: simulates the "armed player" half of the client
	shot pipeline. Owns an unparented Camera that stands in for
	workspace.CurrentCamera (see RangeAttackClient.SetCustomCamera), aims it at
	the target and pulls the trigger through the same `Weapon:Execute(m1)`
	surface the InputManager uses for players.

	The ability's own cooldown (GetCD/StartCD) is the real fire-rate gate;
	GetShootInterval just lets the Attacking state avoid hammering Execute
	every heartbeat.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local AttackController = {}
AttackController.__index = AttackController

export type AttackController = typeof(setmetatable(
	{} :: {
		npc: Model,
		head: BasePart,
		_serviceBag: any,
		_camera: Camera,
		_maid: any,
		_weaponContext: any,
		_m1: any,
	},
	AttackController
))

local M1_KEY = Enum.UserInputType.MouseButton1.Name
local DEFAULT_SHOOT_INTERVAL = 1.5

function AttackController.new(npc: Model, serviceBag: any): AttackController
	local self = setmetatable({}, AttackController)

	self.npc = npc
	self._serviceBag = serviceBag
	self.head = (npc:FindFirstChild("Head") or npc:WaitForChild("HumanoidRootPart")) :: BasePart

	self._camera = Instance.new("Camera")
	self._maid = Maid.new()
	self._maid:GiveTask(self._camera)
	self._weaponContext = nil
	self._m1 = nil

	return self :: AttackController
end

function AttackController._getWeaponContext(self: AttackController)
	if self._weaponContext then
		return self._weaponContext
	end

	local BinderProvider = self._serviceBag:GetService(_G.BinderProvider)
	local WeaponBinder = BinderProvider:Get("Armed")
	self._weaponContext = WeaponBinder and WeaponBinder:Get(self.npc)
	return self._weaponContext
end

-- The m1 ability of the currently equipped strategy, re-wired to our
-- simulated camera whenever a swap recreated it. Nil until the NPC binder's
-- equip promise resolves.
function AttackController._getM1(self: AttackController)
	local weaponContext = self:_getWeaponContext()
	if not weaponContext then
		return nil
	end

	local ability = weaponContext:GetAction(M1_KEY)
	if ability and ability ~= self._m1 then
		self._m1 = ability
		if ability.SetCustomCamera then
			ability:SetCustomCamera(self._camera)
		end
	end
	return ability
end

function AttackController.GetShootInterval(self: AttackController): number
	return DEFAULT_SHOOT_INTERVAL
end

function AttackController.Shoot(self: AttackController, targetPosition: Vector3)
	local ability = self:_getM1()
	if not ability then
		return
	end

	-- Aim the simulated camera, then fire through the normal Execute surface
	-- so cooldowns / attribute gates behave exactly like a player shot.
	self._camera.CFrame = CFrame.lookAt(self.head.Position, targetPosition)

	local weaponContext = self:_getWeaponContext()
	weaponContext:Execute(M1_KEY)
end

function AttackController.Destroy(self: AttackController)
	self._maid:DoCleaning()
	self._weaponContext = nil
	self._m1 = nil
end

return AttackController
