local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local BaseAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Abilities.BaseAbility)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)

local MovementAbility = setmetatable({}, BaseAbility)
MovementAbility.__index = MovementAbility

type MovementAbility = weaponTypes.MovementAbility

function MovementAbility.new(config: weaponTypes.BaseAbilityConstructor): MovementAbility
	local self = setmetatable(BaseAbility.new(config), MovementAbility)

	self._lastAttackID = 0
	self.player = Players:GetPlayerFromCharacter(self.character)
	self._isActive = false

	return self
end

function MovementAbility:SetAttributes()
	local CHAR = self.character
	local HUM = self.humanoid

	CHAR:SetAttribute("Swing", true)
	HUM.JumpHeight = 0

	local setAttrs = (self.spec and self.spec.set_attributes) or self.set_attributes
	if setAttrs then
		setAttrs(self)
	end
end

function MovementAbility.Execute(self: weaponTypes.MovementAbility, params: weaponTypes.MovementAbilityParams)
	self:StartCD()
	self:_countAttack()

	if  self.effect then
		 self.effect(self, params)
	end

end

function MovementAbility:_cancel()
	self._isActive = false
	self:resetAtt()
	self.humanoid.WalkSpeed = 16
	self.humanoid.JumpHeight = 6.5
	self.character:SetAttribute("Swing", false)
end

return MovementAbility