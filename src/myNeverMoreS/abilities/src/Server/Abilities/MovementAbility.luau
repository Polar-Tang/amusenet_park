local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local require = require(script.Parent.loader).load(script)

local BaseAbility = require("BaseAbility")
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Server.types.weaponTypes)

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

function MovementAbility:Execute(params: weaponTypes.MovementAbilityParams)
	local CHAR = self.character
	if CHAR:GetAttribute("Attacking") or CHAR:GetAttribute("Swing") or CHAR:GetAttribute("IsDefending") then
		return
	end

	if self:GetCD() then
		return
	end

	if params and params.cancel then
		self:_cancel()
		return
	end

	self:StartCD()
	self:SetAttributes()
	self:_countAttack()
	self._isActive = true

	-- "Movement" type = client-authoritative (slide, zipline).
	-- Server only manages state + animation, does NOT call effect.
	-- "Others" type = server-authoritative (dash with AlignPosition).
	if self.type ~= "Movement" then
		local effectFn = (params and params.effect) or (self.spec and self.spec.effect) or self.effect
		if effectFn then
			effectFn(self, params)
		end
	end

	local endFn = (params and params.endFx) or (self.spec and self.spec.endFx) or self.endFx
	if endFn then
		endFn(self)
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
