local require = require(script.Parent.loader).load(script)
local WeaponBase = require("WeaponBase")

local CombatConfig = require("CombatConfig")
local WeaponStats = CombatConfig:getweapon("fist")

local Fist = setmetatable({}, WeaponBase)
Fist.__index = Fist

function Fist.new(char, serviceBag)
	local data = table.clone(WeaponStats)
	local self = setmetatable(WeaponBase.new(char, serviceBag, data), Fist)
	self._dmgCount = 0

	return self
end

return Fist
