local require = require(script.Parent.loader).load(script)
local WeaponBase = require("WeaponBase")

local CombatConfig = require("CombatConfig")
local WeaponStats = CombatConfig:getweapon("ak-47")

local Ak_47 = setmetatable({}, WeaponBase)
Ak_47.__index = Ak_47
Ak_47.ClassName = "Ak_47"

function Ak_47.new(char, serviceBag)
	local data = table.clone(WeaponStats)
	local self = setmetatable(WeaponBase.new(char, serviceBag, data), Ak_47)
	self._dmgCount = 0

	return self
end

return Ak_47
