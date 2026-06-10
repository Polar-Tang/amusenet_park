local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedWeaponBase = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.Binders.Weapons.SharedWeaponBase)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)


local WeaponBase = setmetatable({}, SharedWeaponBase)
WeaponBase.__index = WeaponBase

type AbilityTable = { [string]: any }

type WeaponBase = {
	char: Model,
	_serviceBag: any,
	_weapon: any,
	maid: any,
	weapon_name: string,
	weapon_stats: weaponTypes.WeaponStatsBase,
	attacks: AbilityTable,
	skills: AbilityTable,
	_initialized: boolean,
	Init: (self: WeaponBase) -> (),
	createAbilitiesFromKey: (self: WeaponBase, attacks: AbilityTable) -> AbilityTable,
	Execute: (self: WeaponBase, action: EnumItem | { Name: string }, params: any) -> (),
}


function WeaponBase.new(char: Model, serviceBag, data): WeaponBase
	local self = setmetatable(SharedWeaponBase.new(data), WeaponBase)
	self.character = char
	self._serviceBag = serviceBag

	-- self.attacks = {}
	-- Table.deepOverwrite(self.attacks, data.attacks)

	self._maid = Maid.new()

	local fck_tool: Tool = self.character:FindFirstChildWhichIsA("Tool")

	self.tool = fck_tool
	self._initialized = false

	return self
end
function WeaponBase:Init()
	self.attacks = self:createAbilitiesFromKey("attacks")
	self.skills = self:createAbilitiesFromKey("skills")
	self._initialized = true
end

function WeaponBase:_increaseDmgCount(dmg)
	if self.isTransformed then
		return
	end
	self._dmgCount += dmg
end

function WeaponBase:_resetDmgCount()
	local countDamage = ReplicatedStorage.Shared.RemoteEvents.countDamage
	self._dmgCount = 0

	local char_player = Players:GetPlayerFromWeapon(self.Weapon)
	countDamage:FireClient(char_player, 0)
end

function WeaponBase:_setIsTransformed(value: boolean)
	self.isTransformed = value
	self.Weapon:SetAttribute("IsTransformed", value)

	if self.Weapon:GetAttribute("char_name") == "utlimate_" .. self.char_name then
		self.Weapon:SetAttribute("char_name", self.char_name)
	elseif self.Weapon:GetAttribute("char_name") == self.char_name then
		self.Weapon:SetAttribute("char_name", "utlimate_" .. self.char_name)
	end
end

function WeaponBase:createAbilitiesFromKey(key)
	-- HERE
	local fucking_data = self[key]

	local attackData = assert(fucking_data, "no key registered")
	return self:_createAbilities(attackData)
end

-- Tear down every ability owned by this strategy. The abilities themselves
-- were registered into `_maid` by `SharedWeaponBase._createAbilities`, so
-- `DoCleaning` walks them via `MaidTaskUtils` and invokes their `Destroy`.
function WeaponBase:Destroy()
	-- Backstop: an in-flight ability anim torn down by this teardown won't fire
	-- its EndedCon, so force stuck combat attributes back to neutral.
	self:resetCombatAttributes()
	self._maid:DoCleaning()
	setmetatable(self, nil)
end

function WeaponBase:Execute(action: EnumItem | { Name: string }, params)
	if not action.Name then
		return
	end

	local key = action.Name

	local command = self.attacks[key] or self.skills[key]
	if not command then
		return
	end

	-- `command` already carries its spec via createAbilitiesFromKey
	command:Execute(params)
end

function WeaponBase:GetAction(action: string)
	return self.attacks[action] or self.skills[action]
end

return WeaponBase
