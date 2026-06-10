local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbstractStrategy = require(script.Parent.WeaponBaseClient)

local CombatConfig = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.CombatConfig)

local WeaponStats = CombatConfig:getweapon("fist")

local FistClient = setmetatable({}, AbstractStrategy)
FistClient.__index = FistClient

function FistClient.new(char, serviceBag)
	local weapon_stats = table.clone(WeaponStats)

	local self = setmetatable(AbstractStrategy.new(char, serviceBag, weapon_stats), FistClient)
	return self
end

return FistClient
