local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Abilities.BaseAbility)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)

export type AttackBaseClient = weaponTypes.AttackBaseClient
export type construnctor = weaponTypes.AttackBaseAbilityConstructor

local swingEvent = ReplicatedStorage.Shared.RemoteEvents.Swing

--[=[
	@class AttackBaseClient

	Client mirror of AttackBaseAbility. The server still owns animation,
	hitbox-promise registration and damage application. This class only
	gates the local request (active-state attributes + local cooldown)
	and forwards the input to the server via the Swing remote, which is
	how the existing AttckInvocker / AttackBaseAbility pipeline expects
	to be triggered.
]=]
local AttackBaseClient = setmetatable({}, BaseAbility)
AttackBaseClient.__index = AttackBaseClient

function AttackBaseClient.new(config: construnctor)
	local self = setmetatable(BaseAbility.new(config), AttackBaseClient)
	self.attackType = config.attackType
	-- Fall back to `config.key` (a `{ Name = ... }` table) for abilities driven
	-- by a synthetic key rather than a physical input -- e.g. the grenade throw,
	-- which is fired from the trajectory aimer's click, not from InputManager.
	-- The server keys on the same `.Name`, so the round-trip stays consistent.
	self._keyCode = config.keyCode or config.key
	return self :: AttackBaseClient
end

function AttackBaseClient.Execute(self: AttackBaseClient, params)
	local CHAR = self.character

	if not self.special_attack then
		if CHAR:GetAttribute("Attacking") or CHAR:GetAttribute("Swing") or CHAR:GetAttribute("IsDefending") then
			return
		end
	end

	if self:GetCD() then
		return
	end

	self:StartCD()

	swingEvent:FireServer(self._keyCode, params)
end

return AttackBaseClient
