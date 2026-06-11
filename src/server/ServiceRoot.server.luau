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

local Binders = {
	["AnimationHandler"] = AnimationHandler,
	["Armed"] = WeaponBinder,
	["NPC"] = NPCServer,
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

----- ------------------------ START SERVICEBAG -----------------------------
serviceBag:GetService(AttacksBinders)
serviceBag:GetService(QuestHandler)
serviceBag:Init()

serviceBag:Start()

_G.FistBag = nil
_G.ServiceBag = serviceBag
_G.BinderProvider = AttacksBinders

-- Create collision groups
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:RegisterCollisionGroup("Weapons")
PhysicsService:CollisionGroupSetCollidable("Players", "Weapons", false)

------------------Once initilized-------------------------------
local BinderProviderStarted = serviceBag:GetService(_G.BinderProvider)

local WeaponBinderStarted = BinderProviderStarted:Get("Armed")
WeaponBinderStarted:GetClassAddedSignal():Connect(function(binder)
	local character = binder.Char
	character:SetAttribute("binder-Armed-charged", true)
end)
local AnimBinder = BinderProviderStarted:Get("AnimationHandler")
AnimBinder:GetClassAddedSignal():Connect(function(binder)
	local character: Model = binder.Char
	if not binder:IsInitialized() then 
		binder:Init(character:WaitForChild("Humanoid"))
	end
end)

local NPCBinderServer = BinderProviderStarted:Get("NPC")
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
local CollectionService = game:GetService("CollectionService")

------------------ Quests (live per-player state, saved on leave) ------------------
local DataStoreService = game:GetService("DataStoreService")
local QuestsData = require(RS.Shared.Quests.QuestsData)
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
Players.PlayerAdded:Connect(function(player)
	local char = player.Character or player.CharacterAdded:Wait()
	-- Set collision groups for all descendants
	local function setCollisionGroup(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end

	for _, descendant in ipairs(char:GetDescendants()) do
		setCollisionGroup(descendant)
	end

	CollectionService:AddTag(char, "AnimationHandler")
	CollectionService:AddTag(char, "Armed")
	CollectionService:AddTag(char, "CD")
	------------------ TEST ------------------
	CombatMediator.PlayerAdded(player)

	------------------ QUESTS ------------------
	local savedQuests = nil
	if questsStore then
		local loadOk, loadResult = pcall(questsStore.GetAsync, questsStore, tostring(player.UserId))
		if loadOk then
			savedQuests = loadResult
		else
			warn("[ServiceRoot] - Failed to load quests for player ", player.UserId, loadResult)
		end
	end

	QuestService:InitPlayer(player, player, savedQuests)
	local playerQuests = QuestService:GetHandler(player)
	-- Pool the quests: hand every registered quest to the player (no-op resync when it came from the save)
	for questId in pairs(QuestsData.allQuests) do
		playerQuests:AcceptQuest(questId)
	end

	-- TODO: NEED TO USE PLAYERbrio
	local hum: Humanoid = char:WaitForChild("Humanoid")

	hum.Died:Connect(function()
		Ragdoll:Tag(hum)
	end)
end)
--||PlayerRemoving||--
Players.PlayerRemoving:Connect(function(player)
	-- PlayerAnimationHandler:RemovePlayer({ player = player })
	local playerQuests = QuestService:GetHandler(player)
	if not playerQuests then
		return
	end

	if questsStore then
		local saveOk, saveErr = pcall(questsStore.SetAsync, questsStore, tostring(player.UserId), playerQuests:GetSaveData())
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
		{ value = "Common",   weight = 200 },
		{ value = "Uncommon", weight = 80  },
		{ value = "Epic",     weight = 12  },
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
