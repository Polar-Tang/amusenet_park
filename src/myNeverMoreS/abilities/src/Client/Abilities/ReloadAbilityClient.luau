local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Abilities.BaseAbility)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)

local swingEvent = ReplicatedStorage.Shared.RemoteEvents.Swing

--[=[
	@class ReloadAbilityClient

	Client mirror of ReloadAbility. The server owns the actual refill; this
	class only gates the local request on the replicated `_ammo` /
	`_reloading` Tool attributes (plus the local cooldown) and forwards the
	reload key to the server through the existing Swing remote — no
	reload-specific remote. Reached two ways: the input layer dispatching R
	(InputManager / MobileButtons) and RangeAttackClient's auto-reload on an
	empty magazine, both via `weapon:Execute(Enum.KeyCode.R)`.
]=]
local ReloadAbilityClient = setmetatable({}, BaseAbility)
ReloadAbilityClient.__index = ReloadAbilityClient

export type ReloadAbilityClient = weaponTypes.ReloadAbility

function ReloadAbilityClient.new(config: weaponTypes.BaseAbilityConstructor): ReloadAbilityClient
	local self = setmetatable(BaseAbility.new(config), ReloadAbilityClient)
	self._keyCode = config.keyCode or config.key
	-- nil for NPC rigs; mirrors RangeAttackClient's npcChar routing so the
	-- brain-owner client can reload its NPC's weapon through the same remote.
	self.player = Players:GetPlayerFromCharacter(self.character)
	return self :: ReloadAbilityClient
end

function ReloadAbilityClient.Execute(self: ReloadAbilityClient, params)
	local tool = self._tool
	if not tool then
		return
	end
	if self:GetCD() or tool:GetAttribute(Constants.RELOADING_ATTRIBUTE) then
		return
	end

	local magazineSize = self.weapon_stats.magazineSize
	local ammo = tool:GetAttribute(Constants.AMMO_ATTRIBUTE)
	if ammo ~= nil and ammo >= magazineSize then
		return
	end

	self:StartCD()

	-- Local feedback (reload anim / sound) is a CombatConfig hook, never
	-- owned by this generic class.
	local preAnimFx = (params and params.preAnimFx) or self.preAnimFx
	if preAnimFx then
		preAnimFx(self, params)
	end

	swingEvent:FireServer(self._keyCode, {
		npcChar = if self.player then nil else self.character,
	})
end

return ReloadAbilityClient
