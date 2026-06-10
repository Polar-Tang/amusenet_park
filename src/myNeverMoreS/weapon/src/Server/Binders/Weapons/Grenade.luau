local require = require(script.Parent.loader).load(script)
local WeaponBase = require("WeaponBase")

local CombatConfig = require("CombatConfig")
local WeaponStats = CombatConfig:getweapon("grenade")

local Grenade = setmetatable({}, WeaponBase)
Grenade.__index = Grenade

function Grenade.new(char, serviceBag)
	local data = table.clone(WeaponStats)
	local self = setmetatable(WeaponBase.new(char, serviceBag, data), Grenade)
	self._dmgCount = 0

	return self
end

return Grenade
