local require = require(script.Parent.loader).load(script)
local WeaponBase = require("WeaponBase")

local CombatConfig = require("CombatConfig")
local WeaponStats = CombatConfig:getweapon("gun")

local Gun = setmetatable({}, WeaponBase)
Gun.__index = Gun
Gun.ClassName = "gun"

function Gun.new(char, serviceBag)
	local data = table.clone(WeaponStats)
	local self = setmetatable(WeaponBase.new(char, serviceBag, data), Gun)
	self._dmgCount = 0

	return self
end

return Gun
