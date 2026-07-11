local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local NpcConstants = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.NpcConstants)
local ModerationServiceModule = require(ServerScriptService.Server.Moderation.ModerationService)

local serviceBag = _G.ServiceBag
local BinderProvider = serviceBag:GetService(_G.BinderProvider)
local WeaponBinder = BinderProvider:Get(Constants.ARMED_TAG)
local ModerationService = serviceBag:GetService(ModerationServiceModule)

------------------------------------------------------------------------------------------------------------------
local CombatServer = {}

CombatServer.swingEvent = function(plr, action, params)
	---------------------- CONSTANS ----------------------
	local CHAR = plr.Character
	local routedNpcChar: Model? = nil

	-- Client-driven NPC brain (see NPCClient): the owning client fires the
	-- NPC's shots, so the attack must execute on the NPC's Armed context, not
	-- the sender's. Only NPC-tagged models may be routed this way — still
	-- client-trusted, same trust level as the NPC state machine itself.
	local npcChar = params and params.npcChar
	if typeof(npcChar) == "Instance" and CollectionService:HasTag(npcChar, Constants.NPC_TAG) then
		-- Only the elected brain owner may puppeteer this NPC; anything else
		-- is a spoofing client or a Swing that raced a re-election — reject
		-- the shot either way and let ModerationService decide the escalation.
		-- (A nil attribute — no owner elected — fails the comparison too; the
		-- service's debounce keeps that harmless.)
		if npcChar:GetAttribute(NpcConstants.BRAIN_OWNER_ATTRIBUTE) ~= plr.UserId then
			ModerationService:ReportBrainSpoof(plr, npcChar)
			return
		end
		CHAR = npcChar
		routedNpcChar = npcChar
	end
	-------	--------------- getting weapon stats ----------------------
	local Weapon = WeaponBinder:Get(CHAR)
	if not Weapon or not Weapon.tool_name then
		return warn("Weapon not found")
	end

	------------ EXECUTE COMMAND ------------
	-- Addintional checks sucha as cooldowns are up to the ability. A
	-- CD-rejected NPC-routed shot means the brain owner fired faster than the
	-- weapon allows — damage was already denied, we only count the evidence.
	local rejectReason = Weapon:Execute(action, params)
	if routedNpcChar and rejectReason == Constants.REJECT_REASON_COOLDOWN then
		ModerationService:ReportFireRateViolation(plr, routedNpcChar)
	end
end

return CombatServer
