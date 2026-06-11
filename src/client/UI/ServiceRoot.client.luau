--||Services||--
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

--||Nevermore Shit||--
---------------------------getting servicebag and loader -----------------------------

--||Start Loading screen||--
local mountShit = require(script.Parent.LoadingScreen)
local Animate = require(script.Parent.Animate)

mountShit:Init()

mountShit:registryObserver("WeaponClient", "heavy")
 mountShit:registryObserver("AnimationHandler", "heavy")
 mountShit:registryObserver("NevermoreLoaded", "heavy")

mountShit:Start()

local NeverMorePackages = RS.Nevermore
local loader = NeverMorePackages:FindFirstChild("LoaderUtils", true).Parent
local Nevermore = require(loader).bootstrapGame(NeverMorePackages)

local ServiceBag = Nevermore("ServiceBag")
local serviceBag = ServiceBag.new()

local CameraMediator = require(script.Parent.cameraHandlers.camerasStates.CameraMediator)
--------------------------- Binders -----------------------------

local Binder = Nevermore("Binder")
local WeaponClient = Nevermore("WeaponClient") -- THIS IS NEW
local AnimationHandler = Nevermore("AnimationHandler")
local NPCClient = Nevermore("NPCClient")

local Binders = {
	["AnimationHandler"] = AnimationHandler,
	["Armed"] = WeaponClient,
	["NPC"] = NPCClient,
}

---------- USE BINDER PORVIDER ----------
local BinderProvider = Nevermore("BinderProvider")

local AttacksBinders = BinderProvider.new("Binders", function(self, serviceBag)
	for tag, contructor in pairs(Binders) do
		self:Add(Binder.new(tag, contructor), serviceBag, "test")
	end
end)

serviceBag:GetService(AttacksBinders)
--------------------------- END Binders -----------------------------
------------------ Other services ------------------
serviceBag:GetService(Nevermore("RagdollServiceClient"))
serviceBag:GetService(Nevermore("TimeSyncService"))
serviceBag:GetService(Nevermore("CooldownClient"))
local CameraService = serviceBag:GetService(Nevermore("CameraStackService"))
local cameraMediator = serviceBag:GetService(CameraMediator)
--------------------------- INIT -----------------------------

serviceBag:Init()

local PlayerBrio = Nevermore("PlayerBrio")

local BinderProviderInitialized = serviceBag:GetService(AttacksBinders)

local characterCtxUtils = require(ReplicatedStorage.Shared.Helpers.shared_services.characterCtxUtils)
local FadeText = require(ReplicatedStorage.Shared.utils.FadeText)

local player = Players.LocalPlayer
local player_character = player.Character or player.CharacterAdded:Wait()

local WeaponBinderStarted = BinderProviderInitialized:Get("Armed")

WeaponBinderStarted:GetClassAddedSignal():Connect(function(binder)
	local character = binder.Char

	-- If there are more shit that App depends to, we can use a bool instance, and listen to this att, when it's true we require it

	if player_character == character then
		mountShit:markObserver("WeaponClient", true)
	end
end)

local AnimBinder = BinderProviderInitialized:Get("AnimationHandler")
AnimBinder:GetClassAddedSignal():Connect(function(binder)
	local character: Model = binder.Char
	character:SetAttribute("binder-AnimationHandler-charged", true)
	mountShit:markObserver("AnimationHandler", true)
	if not binder:IsInitialized() then 
		binder:Init(character:WaitForChild("Humanoid"))
		
	end

	-- Drive the default character animations through this handler, but only for
	-- the local player's character (the binder also binds remote characters,
	-- whose animations replicate from their own client).
	if Players:GetPlayerFromCharacter(character) == Players.LocalPlayer then
		task.spawn(Animate, binder, character)
	end
end)

-- NPC brains: equip the rig's tool client-side and watch the brain-owner
-- attribute (only the elected client runs the state machine). Registered
-- BEFORE serviceBag:Start so pre-placed NPCs binding during Start are caught.
local NPCBinder = BinderProviderInitialized:Get("NPC")
NPCBinder:GetClassAddedSignal():Connect(function(npcBinder)
	task.spawn(function()
		npcBinder:Init()
		npcBinder:Start()
	end)
end)

-------------------------START SERVICEBAG -----------------------------

-- Must be set BEFORE cameraMediator:Start so it can resolve the "Armed"
-- binder via the standard _G.BinderProvider pattern used elsewhere
-- (BaseAbility, RangeAttack, etc).
_G.PlayerBrio = PlayerBrio.new() -- use the same instance for everything
_G.ServiceBag = serviceBag
_G.BinderProvider = AttacksBinders
_G.CameraService = CameraService
serviceBag:Start()

isServiceBagInitialized = true
------------- ONCE INITIALIZED -------------

do
	
	mountShit:registerFinishCB(function()
		local inputManager = require(script.Parent.InputManager)
		inputManager.Init({ serviceBag = serviceBag })

		UserInputService.MouseIconEnabled = false

		-- Ensures Roact App start after intializing service bag
		require(script.Parent.AttckInvockerClient)
		-- require(script.Parent.test.test)

		local weaponClient = WeaponBinderStarted:Get(player_character)
		local MainApp = require(script.Parent.RoactUI.MainApp)

		MainApp({
			weaponClient = weaponClient,
			cameraMediator = cameraMediator,
		})
	end)
	mountShit:markObserver("NevermoreLoaded", true)
end

-- local humanoid: Humanoid = player_character:WaitForChild("Humanoid")

-- Tool equip: a Tool becomes a child of the character. Tell the server,
-- then locally init anims + install the matching weapon strategy.
player_character.ChildAdded:Connect(function(a0: Instance)
	if a0:IsA("Tool") then
		ReplicatedStorage.Shared.RemoteEvents.Equipment:FireServer({
			tool = a0,
			has_to_equip = true,
		})

		characterCtxUtils:InitChar(player_character, tostring(a0.Name:lower()))

		local animHandler = AnimBinder:Get(player_character)
		animHandler:LoadAnimation(true, "Equip")
		
		animHandler:LoadAnimation(true, "Equiped") -- Equiped is priority core so it's ovewrited
	end
end)

-- Tool unequip: a Tool leaves the character (drop / swap to none).
-- Notify the server and locally destroy the current strategy via
-- `UnequipChar`, which calls `UnequiTool` on the "Armed" binder.
-- On a hot swap (Tool A removed -> Tool B added in the same frame),
-- this runs first; the subsequent `ChildAdded` then installs B cleanly.
player_character.ChildRemoved:Connect(function(child: Instance)
	if child:IsA("Tool") then
		ReplicatedStorage.Shared.RemoteEvents.Equipment:FireServer({
			tool = child,
			has_to_equip = false,
		})
		local animHandler = AnimBinder:Get(player_character)

		animHandler:LoadAnimation(false, "Equiped")
		characterCtxUtils:UnequipChar(player_character)
	end
end)

ReplicatedStorage.Shared.RemoteEvents.countDamage.OnClientEvent:Connect(function(data)
	local dmg = data.dmg
	local textColor = Color3.fromRGB(255, 255, 255)

	FadeText(data.src, dmg, textColor, UDim2.new(6, 0, 4, 0))
end)

-- player_character:GetAttributeChangedSignal("recoil"):Connect(function(recoil: number)
-- 	print("recoild ", recoil)
-- 	CameraRecoiler.recoil(recoil)
-- end)
