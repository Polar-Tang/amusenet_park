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

local Binders = {
	["AnimationHandler"] = AnimationHandler,
	["Armed"] = WeaponBinder,
}
---------- USE BINDER PORVIDER ----------
local BinderProvider = Nevermore("BinderProvider")
local AttacksBinders 
AttacksBinders = BinderProvider.new("Binders", function(self, serviceBag)
	for tag, contructor in pairs(Binders) do
		self:Add(Binder.new(tag, contructor, serviceBag, self))
	end
end)

----- ------------------------ START SERVICEBAG -----------------------------
serviceBag:GetService(AttacksBinders)
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
	binder:Init(character:WaitForChild("Humanoid"))
end)

------------------Do binder stuff-------------------------------
--||PlayerAdded||--
local Ragdoll = Nevermore("Ragdoll")
local CombatMediator = require(SSS.Server.Combat.CombatMediator)
local CollectionService = game:GetService("CollectionService")
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

	-- TODO: NEED TO USE PLAYERbrio
	local hum: Humanoid = char:WaitForChild("Humanoid")

	hum.Died:Connect(function()
		Ragdoll:Tag(hum)
	end)
end)
--||PlayerRemoving||--
Players.PlayerRemoving:Connect(function(player)
	-- PlayerAnimationHandler:RemovePlayer({ player = player })
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
