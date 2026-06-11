local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)

local serviceBag = _G.ServiceBag
local BinderProvider = serviceBag:GetService(_G.BinderProvider)
local WeaponBinder = BinderProvider:Get("Armed")

------------------------------------------------------------------------------------------------------------------
local CombatServer = {}

CombatServer.swingEvent = function(plr, action, params)
	---------------------- CONSTANS ----------------------
	local CHAR = plr.Character

	-- Client-driven NPC brain (see NPCClient): the owning client fires the
	-- NPC's shots, so the attack must execute on the NPC's Armed context, not
	-- the sender's. Only NPC-tagged models may be routed this way — still
	-- client-trusted, same trust level as the NPC state machine itself.
	local npcChar = params and params.npcChar
	if typeof(npcChar) == "Instance" and CollectionService:HasTag(npcChar, Constants.NPC_TAG) then
		CHAR = npcChar
	end
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
