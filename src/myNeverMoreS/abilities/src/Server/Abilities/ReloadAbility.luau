local ReplicatedStorage = game:GetService("ReplicatedStorage")
local require = require(script.Parent.loader).load(script)

local BaseAbility = require("BaseAbility")
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)

--[=[
	@class ReloadAbility

	Generic server reload (`type = "Reload"`). Thin by design: timing comes
	from `weapon_stats` (`reloadTime` / `magazineSize`) and weapon-specific
	feedback belongs in the CombatConfig table hooks, not here. The Tool's
	`_ammo` / `_reloading` attributes are the only contract with the m1
	ability (RangeAttack); the two abilities never reference each other.
]=]
local ReloadAbility = setmetatable({}, BaseAbility)
ReloadAbility.__index = ReloadAbility

export type ReloadAbility = weaponTypes.ReloadAbility

function ReloadAbility.new(config: weaponTypes.BaseAbilityConstructor): ReloadAbility
	local self = setmetatable(BaseAbility.new(config), ReloadAbility)
	return self :: ReloadAbility
end

function ReloadAbility.Execute(self: ReloadAbility, params)
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
	tool:SetAttribute(Constants.RELOADING_ATTRIBUTE, true)

	local preAnimFx = (params and params.preAnimFx) or self.preAnimFx
	if preAnimFx then
		preAnimFx(self, params)
	end

	-- Deliberately NOT registered in the maid: cancelling this thread on a
	-- mid-reload weapon swap would leave `_reloading` stuck true on the Tool
	-- (which survives in the Backpack) and brick the gun. Attributes stay
	-- writable even on a destroyed Tool, so letting it finish is always safe.
	task.delay(self.weapon_stats.reloadTime, function()
		tool:SetAttribute(Constants.AMMO_ATTRIBUTE, magazineSize)
		tool:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)
	end)
end

return ReloadAbility
