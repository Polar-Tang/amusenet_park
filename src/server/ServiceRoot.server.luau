--||Services||--
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")
local PhysicsService = game:GetService("PhysicsService")
--||Nevermore Shit||--
----------------------------- getting servicebag and loader -----------------------------

local NeverMorePackages = RS.Nevermore
local loader = NeverMorePackages:FindFirstChild("LoaderUtils", true).Parent
local Nevermore = require(loader).bootstrapGame(NeverMorePackages)

-- Manual respawn: the engine must NOT auto-load characters. The first spawn
-- is issued in PlayerAdded below; every later one only happens when the dead
-- client clicks the Roact respawn button (RespawnRequest handler below).
Players.CharacterAutoLoads = false

local ServiceBag = Nevermore("ServiceBag")
local serviceBag = ServiceBag.new()

----------------------------- init process -----------------------------
_G.FistBag = serviceBag

---------- COLDOWNS ----------
local Cooldown = serviceBag:GetService(Nevermore("Cooldown"))
serviceBag:GetService(Nevermore("TimeSyncService"))
---------- OTHERS ----------
serviceBag:GetService(Nevermore("RagdollService"))
---------- BINDERS ----------
local Binder = Nevermore("Binder")
local WeaponBinder = Nevermore("Weapon")
local AnimationHandler = Nevermore("AnimationHandler")
local NPCServer = Nevermore("NPCServer")
-- CTF flag binder: a custom module (not a Nevermore package), tagged per the
-- shared constant so the CaptureTheFlag mode can look it up by the same name.
local GameModeConstants = require(RS.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local Constants = require(RS.Nevermore.Custom.abilities.src.Shared.Constanst)
local Flag = require(RS.Nevermore.Custom.gamemode.src.Server.Binders.Flag)

local Binders = {
	[Constants.ANIMATION_HANDLER_TAG] = AnimationHandler,
	[Constants.ARMED_TAG] = WeaponBinder,
	[Constants.NPC_TAG] = NPCServer,
	[GameModeConstants.CTF_FLAG_TAG] = Flag,
}
---------- USE BINDER PORVIDER ----------
local BinderProvider = Nevermore("BinderProvider")
local AttacksBinders
AttacksBinders = BinderProvider.new("Binders", function(self, serviceBag)
	for tag, contructor in pairs(Binders) do
		self:Add(Binder.new(tag, contructor, serviceBag, self))
	end
end)

---------- QUESTS ----------
local QuestHandler = require(SSS.Server.Quests.QuestHandler)
---------- GAME MODE ----------
local GameModeService = require(RS.Nevermore.Custom.gamemode.src.Server.GameModeService)
-- A ServiceBag service, NOT a free-standing Script: its require chain reaches
-- loader-dependent Quenty modules, which only load after bootstrapGame above.
local MatchListener = require(SSS.Server.NPC.MatchListener)

----- ------------------------ START SERVICEBAG -----------------------------
serviceBag:GetService(AttacksBinders)
serviceBag:GetService(QuestHandler)
serviceBag:GetService(GameModeService)
serviceBag:GetService(MatchListener)
serviceBag:Init()

serviceBag:Start()
print("starting service bag")

_G.FistBag = nil
_G.ServiceBag = serviceBag
_G.BinderProvider = AttacksBinders

-- Create collision groups
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:RegisterCollisionGroup("Weapons")
PhysicsService:CollisionGroupSetCollidable("Players", "Weapons", false)

------------------Once initilized-------------------------------
local BinderProviderStarted = serviceBag:GetService(_G.BinderProvider)

local WeaponBinderStarted = BinderProviderStarted:Get(Constants.ARMED_TAG)
-- Registered in the Binders table above, so a nil here is a wiring bug (typo'd
-- tag / missing registration), not a runtime state — fail loud, don't NPE later.
assert(WeaponBinderStarted, `ServiceRoot: no binder registered for tag "{Constants.ARMED_TAG}"`)
WeaponBinderStarted:GetClassAddedSignal():Connect(function(binder)
	local character = binder.Char
	character:SetAttribute("binder-Armed-charged", true)
end)
local AnimBinder = BinderProviderStarted:Get(Constants.ANIMATION_HANDLER_TAG)
assert(AnimBinder, `ServiceRoot: no binder registered for tag "{Constants.ANIMATION_HANDLER_TAG}"`)
AnimBinder:GetClassAddedSignal():Connect(function(binder)
	local character: Model = binder.Char
	if not binder:IsInitialized() then
		binder:Init(character:WaitForChild("Humanoid"))
	end
end)

local NPCBinderServer = BinderProviderStarted:Get(Constants.NPC_TAG)
assert(NPCBinderServer, `ServiceRoot: no binder registered for tag "{Constants.NPC_TAG}"`)
-- Start (brain election) must run at bind time, not from PlayerAdded: bots
-- spawned mid-match (GameModeService) bind long after every player joined,
-- so a PlayerAdded-driven start would never reach them. Election with zero
-- players is a safe no-op that re-elects from its own PlayerAdded hook.
local function setupNpc(npcBinder)
	task.spawn(function()
		npcBinder:Init()
		npcBinder:Start()
	end)
end
NPCBinderServer:GetClassAddedSignal():Connect(setupNpc)
-- Pre-placed NPCs bound during serviceBag:Start(), before the connection
-- above existed — sweep them (Init/Start self-guard against double calls).
for _, npcBinder in NPCBinderServer:GetAll() do
	setupNpc(npcBinder)
end

------------------Do binder stuff-------------------------------
--||PlayerAdded||--
local Ragdoll = Nevermore("Ragdoll")
local CombatMediator = require(SSS.Server.Combat.CombatMediator)
local characterCtxUtils = require(RS.Shared.Helpers.shared_services.characterCtxUtils)
local CollectionService = game:GetService("CollectionService")

------------------ Quests (live per-player state, saved on leave) ------------------
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local NpcSpawner = require(ServerScriptService.Server.NPC.NpcSpawner)
local QuestsData = require(RS.Shared.Quests.QuestsData)
local questTypes = require(RS.Shared.Quests.questTypes)
local QuestService = serviceBag:GetService(QuestHandler)

-- Client (QuestsList UI) asks for a resync on mount; the join-time
-- FireClient burst can land before the UI has connected OnClientEvent.
RS.Shared.RemoteEvents.QuestProgress.OnServerEvent:Connect(function(player)
	local playerQuests = QuestService:GetHandler(player)
	if playerQuests then
		playerQuests:Resync()
	end
end)

-- GetDataStore throws in Studio when API access is disabled; quests still run, they just don't persist
local questsStoreOk, questsStore = pcall(DataStoreService.GetDataStore, DataStoreService, "PlayerQuests_v1")
if not questsStoreOk then
	warn("[ServiceRoot] - DataStore unavailable, quests will not persist: ", questsStore)
	questsStore = nil
end
-- Match-aware quest load. A player teleported in from the lobby carries the
-- whole match's quest snapshot in TeleportData.questsByUserId (the lobby is
-- the only place that re-rolls/refreshes due quests — see PlayerQuests
-- docstring), so prefer that record and never RefreshDue here. Only a direct
-- join (no lobby payload) reads the persisted DataStore.
local function loadSavedQuests(player: Player): questTypes.QuestsSaveData?
	local joinOk, joinData = pcall(player.GetJoinData, player)
	if joinOk and type(joinData) == "table" then
		local teleportData = joinData.TeleportData
		if type(teleportData) == "table" and type(teleportData.questsByUserId) == "table" then
			local record = teleportData.questsByUserId[tostring(player.UserId)]
			if record then
				return record
			end
		end
	end

	if questsStore then
		local loadOk, loadResult = pcall(questsStore.GetAsync, questsStore, tostring(player.UserId))
		if loadOk then
			return loadResult
		end
		warn("[ServiceRoot] - Failed to load quests for player ", player.UserId, loadResult)
	end

	return nil
end

local function setCharacterCollider(char: Model)
	for _, descendant in ipairs(char:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end
end

-- Character-scoped setup, re-run on EVERY spawn: CollectionService tags live
-- on the character Model, so a respawned character starts untagged and no
-- binder (Weapon/AnimationHandler/CD) would ever bind to it again.
local function onCharacterAdded(char: Model)
	setCharacterCollider(char)
	CollectionService:AddTag(char, Constants.ANIMATION_HANDLER_TAG)
	CollectionService:AddTag(char, Constants.ARMED_TAG)
	CollectionService:AddTag(char, Constants.CD_TAG)
	CombatMediator.CharacterAdded(char)

	-- Default loadout: a bare character never fires ChildAdded/Equipment,
	-- so equip the fist strategy once BOTH binders are up (the client
	-- equips its own side from its ServiceRoot). The AnimationHandler
	-- auto-Init can lag behind its bind, so ensure it ourselves — fist is
	-- melee and genuinely needs its animations.
	WeaponBinderStarted:Promise(char)
		:Then(function()
			return AnimBinder:Promise(char)
		end)
		:Then(function(animHandler)
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end
			if not animHandler:IsInitialized() then
				animHandler:Init(humanoid)
			end
			-- LMS seam: that mode spawns players empty-handed.
			if GameModeService:ShouldEquipDefaultWeapon() then
				characterCtxUtils:EquipDefaultWeapon(char)
			end
		end)

	local hum: Humanoid = char:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		Ragdoll:Tag(hum)
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	else
		-- CharacterAutoLoads is off, so the first spawn is ours to issue —
		-- after the CharacterAdded wiring above so it is never missed.
		player:LoadCharacter()
	end

	------------------ QUESTS ------------------
	-- Prefer the match snapshot from TeleportData; fall back to the DataStore
	-- only on a direct join. Either way we build PlayerQuests from the record
	-- and Resync — we never re-roll due quests in the shooter (lobby-only).
	local savedQuests = loadSavedQuests(player)
	QuestService:InitPlayer(player, player, savedQuests)
	local playerQuests = QuestHandler:GetHandler(player)
	playerQuests:Resync()
end)
-- Respawn gate: the client's DeathScreen fires this when the player clicks
-- the Roact respawn button. Only honored while actually dead — otherwise it
-- would be a free teleport-to-spawn exploit.
RS.Shared.RemoteEvents.RespawnRequest.OnServerEvent:Connect(function(player)
	-- Game-mode gate: LMS-style modes disable respawning entirely.
	if not GameModeService:CanRespawn(player) then
		return
	end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return
	end
	player:LoadCharacter()
end)

--||PlayerRemoving||--
Players.PlayerRemoving:Connect(function(player)
	-- PlayerAnimationHandler:RemovePlayer({ player = player })
	local playerQuests = QuestService:GetHandler(player)
	if not playerQuests then
		return
	end

	if questsStore then
		local saveOk, saveErr =
			pcall(questsStore.SetAsync, questsStore, tostring(player.UserId), playerQuests:GetSaveData())
		if not saveOk then
			warn("[ServiceRoot] - Failed to save quests for player ", player.UserId, saveErr)
		end
	end

	QuestService:RemovePlayer(player)
end)

------------------ Roulette ------------------
local WeightedRandom = require(RS.Shared.RNG.WeightedRandom)
local RouletteItems = require(RS.Shared.items.roulleteItems)

RS.Shared.RemoteEvents.RouletteSpinRemote.OnServerEvent:Connect(function(player)
	local rarety = WeightedRandom.Pick({
		{ value = "Common", weight = 200 },
		{ value = "Uncommon", weight = 80 },
		{ value = "Epic", weight = 12 },
	})

	-- Collect all rewards matching the drawn rarity.
	local pool = {}
	for _, entry in ipairs(RouletteItems) do
		if entry.rarety == rarety then
			table.insert(pool, entry)
		end
	end

	local reward = pool[math.random(1, #pool)]
	RS.Shared.RemoteEvents.RouletteSpinRemote:FireClient(player, {
		angle = reward.angle,
		reward = reward.name,
	})
end)
