local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbstractStrategy = require(script.Parent.WeaponBaseClient)

local CombatConfig = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.CombatConfig)

local WeaponStats = CombatConfig:getweapon("grenade")

local GrenadeClient = setmetatable({}, AbstractStrategy)
GrenadeClient.__index = GrenadeClient

function GrenadeClient.new(char, serviceBag)
	local weapon_stats = table.clone(WeaponStats)

	local self = setmetatable(AbstractStrategy.new(char, serviceBag, weapon_stats), GrenadeClient)
	return self
end

return GrenadeClient
