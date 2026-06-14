--||Services||--
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
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
mountShit:registryObserver("npcLoaded", "heavy")

mountShit:Start()

local NeverMorePackages = RS.Nevermore
local loader = NeverMorePackages:FindFirstChild("LoaderUtils", true).Parent
local Nevermore = require(loader).bootstrapGame(NeverMorePackages)

local ServiceBag = Nevermore("ServiceBag")
local serviceBag = ServiceBag.new()

local CameraMediator = require(script.Parent.cameraHandlers.camerasStates.CameraMediator)
--------------------------- Binders -----------------------------

local Binder = Nevermore("Binder")
local Maid = Nevermore("Maid")
local WeaponClient = Nevermore("WeaponClient") -- THIS IS NEW
local AnimationHandler = Nevermore("AnimationHandler")
local NPCClient = Nevermore("NPCClient")
local CarrierClient = require(RS.Nevermore.Custom.gamemode.src.Client.Binders.CarrierClient)

local Constants = require(RS.Nevermore.Custom.abilities.src.Shared.Constanst)
local GameModeConstants = require(RS.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)

local Binders = {
	[Constants.ANIMATION_HANDLER_TAG] = AnimationHandler,
	[Constants.ARMED_TAG] = WeaponClient,
	[Constants.NPC_TAG] = NPCClient,
	-- Observe the server-authored CTF_carrier tag client-side (replicated for
	-- free) instead of a remote duplicating the same fact — FlagBillboard +
	-- GroundPath drive off this binder's class-added/removing signals.
	[GameModeConstants.CTF_CARRIER_TAG] = CarrierClient,
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

local WeaponBinderStarted = BinderProviderInitialized:Get(Constants.ARMED_TAG)
-- Registered in the Binders table above, so a nil here is a wiring bug (typo'd
-- tag / missing registration), not a runtime state — fail loud, don't NPE later.
assert(WeaponBinderStarted, `ServiceRoot: no binder registered for tag "{Constants.ARMED_TAG}"`)

WeaponBinderStarted:GetClassAddedSignal():Connect(function(binder)
	local character = binder.Char

	-- If there are more shit that App depends to, we can use a bool instance, and listen to this att, when it's true we require it

	if Players:GetPlayerFromCharacter(character) == player then
		mountShit:markObserver("WeaponClient", true)
	end
end)

local AnimBinder = BinderProviderInitialized:Get(Constants.ANIMATION_HANDLER_TAG)
assert(AnimBinder, `ServiceRoot: no binder registered for tag "{Constants.ANIMATION_HANDLER_TAG}"`)
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
local NPCBinder = BinderProviderInitialized:Get(Constants.NPC_TAG)
assert(NPCBinder, `ServiceRoot: no binder registered for tag "{Constants.NPC_TAG}"`)
NPCBinder:GetClassAddedSignal():Connect(function(npcBinder)
	task.spawn(function()
		npcBinder:Init()
		npcBinder:Start()
	end)
	mountShit:markObserver("npcLoaded", true)
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

		local MainApp = require(script.Parent.RoactUI.MainApp)

		-- Pass the binder, not the bound class: the WeaponClient is
		-- character-scoped, so MainApp re-resolves it on every rebind
		-- (respawn) and updates the Roact tree's props.
		MainApp({
			weaponBinder = WeaponBinderStarted,
			cameraMediator = cameraMediator,
		})
	end)
	mountShit:markObserver("NevermoreLoaded", true)
end

-- Tool equip/unequip connections live on the character Model, so they must
-- be rebuilt on every respawn. The maid drops the previous character's
-- connections on re-entry (covers CharacterAdded firing before the old
-- Model is destroyed).
local characterMaid = Maid.new()

local function onCharacterAdded(character: Model)
	characterMaid:DoCleaning()

	-- Default loadout: a fresh character has no Tool, so no ChildAdded fires.
	-- Equip the local fist strategy once BOTH binders are up for this character
	-- (the server equips its own side from its ServiceRoot; no remote needed).
	-- Same AnimationHandler-lag guard as the server: fist is melee, its anims
	-- must resolve, so make sure the handler is initialized before InitChar.
	WeaponBinderStarted:Promise(character)
		:Then(function()
			return AnimBinder:Promise(character)
		end)
		:Then(function(animHandler)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end
			if not animHandler:IsInitialized() then
				animHandler:Init(humanoid)
			end
			characterCtxUtils:EquipDefaultWeapon(character)
		end)

	-- Tool equip: a Tool becomes a child of the character. Tell the server,
	-- then locally init anims + install the matching weapon strategy.
	characterMaid:GiveTask(character.ChildAdded:Connect(function(a0: Instance)
		if a0:IsA("Tool") then
			ReplicatedStorage.Shared.RemoteEvents.Equipment:FireServer({
				tool = a0,
				has_to_equip = true,
			})

			characterCtxUtils:InitChar(character, tostring(a0.Name:lower()))

			local animHandler = AnimBinder:Get(character)
			animHandler:LoadAnimation(true, "Equip")

			animHandler:LoadAnimation(true, "Equiped") -- Equiped is priority core so it's ovewrited
		end
	end))

	-- Tool unequip: a Tool leaves the character (drop / swap to none).
	-- Notify the server and locally destroy the current strategy via
	-- `UnequipChar`, which calls `UnequiTool` on the "Armed" binder.
	-- On a hot swap (Tool A removed -> Tool B added in the same frame),
	-- this runs first; the subsequent `ChildAdded` then installs B cleanly.
	characterMaid:GiveTask(character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") then
			ReplicatedStorage.Shared.RemoteEvents.Equipment:FireServer({
				tool = child,
				has_to_equip = false,
			})
			local animHandler = AnimBinder:Get(character)

			animHandler:LoadAnimation(false, "Equiped")
			characterCtxUtils:UnequipChar(character)
		end
	end))
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

ReplicatedStorage.Shared.RemoteEvents.countDamage.OnClientEvent:Connect(function(data)
	local dmg = data.dmg
	local textColor = Color3.fromRGB(255, 255, 255)

	FadeText(data.src, dmg, textColor, UDim2.new(6, 0, 4, 0))
end)

ReplicatedStorage.Shared.RemoteEvents.clientDebugConsole.OnClientEvent:Connect(function(message: string)
	print(message)
end)

-- player_character:GetAttributeChangedSignal("recoil"):Connect(function(recoil: number)
-- 	print("recoild ", recoil)
-- 	CameraRecoiler.recoil(recoil)
-- end)

ProximityPromptService.PromptShown:Connect(function(a0: ProximityPrompt, a1: Enum.ProximityPromptInputType)
	print("Showed pronpt", a0)
end)