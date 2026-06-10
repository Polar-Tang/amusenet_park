local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.CombatConfig)
local AbstractStrategy = require(script.Parent.WeaponBaseClient)

local WeaponStats = CombatConfig:getweapon("gun")
local GunClient = setmetatable({}, AbstractStrategy)
GunClient.ClassName = "GunClient"
GunClient.__index = GunClient

function GunClient.new(char, serviceBag)
	local damn_data = table.clone(WeaponStats)

	local self = setmetatable(AbstractStrategy.new(char, serviceBag, damn_data), GunClient)
	return self
end

return GunClient
