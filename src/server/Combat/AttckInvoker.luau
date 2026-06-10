local serviceBag = _G.ServiceBag
local BinderProvider = serviceBag:GetService(_G.BinderProvider)
local WeaponBinder = BinderProvider:Get("Armed")

------------------------------------------------------------------------------------------------------------------
local CombatServer = {}

CombatServer.swingEvent = function(plr, action, params)
	---------------------- CONSTANS ----------------------
	local CHAR = plr.Character
	-------	--------------- getting weapon stats ----------------------
	local Weapon = WeaponBinder:Get(CHAR)
	if not Weapon or not Weapon.tool_name then
		return warn("Weapon not found")
	end

	------------ EXECUTE COMMAND ------------
	-- Addintional checks sucha as cooldowns are up to the ability
	Weapon:Execute(action, params)
end

return CombatServer
