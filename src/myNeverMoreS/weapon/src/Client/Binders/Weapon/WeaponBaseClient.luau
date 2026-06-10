local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedWeaponBase = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.Binders.Weapons.SharedWeaponBase)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local Signal = require(ReplicatedStorage.Nevermore.Quenty.signal.Shared.Signal)

export type ClientAbilityTable = { [string]: any }
export type WeaponBaseClient = {
	character: Model,
	_serviceBag: any,
	weapon_name: string,
	weapon_stats: weaponTypes.WeaponStatsBase,
	maid: any,
	attacks: ClientAbilityTable,
	skills: ClientAbilityTable,

	Init: (self: WeaponBaseClient) -> (),
	createAbilitiesFromKey: (self: WeaponBaseClient, attacks: ClientAbilityTable) -> ClientAbilityTable,
	Execute: (self: WeaponBaseClient, action: string, params: any) -> (),
}

local AbstractStrategy = setmetatable({}, SharedWeaponBase)
AbstractStrategy.__index = AbstractStrategy

function AbstractStrategy.new(char, serviceBag, data)
	local self = setmetatable(SharedWeaponBase.new(data), AbstractStrategy)
	self._maid = Maid.new()
	self.character = char
	self._serviceBag = serviceBag

	self.AbilityExecuted = Signal.new()
	self._maid:GiveTask(self.AbilityExecuted)
	self.weapon_name = data.weapon_name
	self.weapon_stats = table.clone(data.weapon_stats)
	return self
end

function AbstractStrategy:createAbilitiesFromKey(key: string)
	local abilitySet = assert(self[key], "no key registered: " .. key)
	return self:_createAbilities(abilitySet)
end

function AbstractStrategy:Init()
	self.attacks = self:createAbilitiesFromKey("attacks")
	self.skills = self:createAbilitiesFromKey("skills")
	return self
end

-- Post-init activation pass. `Init` only *constructs* the abilities; `Start`
-- kicks off any always-on per-ability runtime an ability opts into (e.g. the
-- gun's continuous auto-aim scan in `RangeAttackClient:Start`). Kept separate
-- from `Init` so construction stays side-effect-free and the "running" phase is
-- explicit — see WeaponClient.EquiTool, which calls this right after `Init`.
-- Abilities that don't define `Start` are simply skipped.
function AbstractStrategy:Start()
	for _, ability in pairs(self.attacks) do
		if ability.Start then
			ability:Start()
		end
	end
	for _, ability in pairs(self.skills) do
		if ability.Start then
			ability:Start()
		end
	end
	return self
end

function AbstractStrategy:GetAction(action: string)
	return self.attacks[action] or self.skills[action]
end

function AbstractStrategy.Execute(self: WeaponBaseClient, action: EnumItem | { Name: string }, params: any)
	if not action then
		return
	end

	local key: string?
	if typeof(action) == "string" then
		key = action
	elseif typeof(action) == "EnumItem" or (typeof(action) == "table" and action.Name) then
		key = action.Name
	end

	if not key then
		return
	end

	local command = self.attacks[key] or self.skills[key]
	if not command then
		return
	end

	command:Execute(params)
end

-- Tear down every ability owned by this strategy. Each ability is
-- registered into `_maid` by `SharedWeaponBase._createAbilities`, so
-- `DoCleaning` walks them via `MaidTaskUtils` and invokes each ability's
-- own `Destroy` (which clears their `_maid`, killing input connections,
-- m1-hold listeners, recoil controllers, etc.).
function AbstractStrategy:Destroy()
	-- Backstop: an in-flight ability anim torn down by this teardown won't fire
	-- its EndedCon, so force stuck combat attributes back to neutral.
	self:resetCombatAttributes()
	self._maid:DoCleaning()
	setmetatable(self, nil)
end

return AbstractStrategy
