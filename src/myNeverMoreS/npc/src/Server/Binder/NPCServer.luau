--[=[
	@class NPCServer

	The "NPC" binder, server side. The brain runs on a client (NPCClient);
	this side only makes the rig a valid combatant and decides *which* client:
	  * `new` tags AnimationHandler/CD/Armed (the same set players get in
	    ServiceRoot.PlayerAdded) and mirrors CombatMediator.CharacterAdded's
	    combat attributes, so the server hit pipeline treats the NPC exactly
	    like a player character.
	  * `Init` equips the rig's first Tool child through characterCtxUtils so
	    the server Weapon strategy (the one AttckInvoker executes on Swing)
	    exists. Binders are passed explicitly — `_G.ServiceBag` is still nil
	    while serviceBag:Start() is binding pre-placed NPCs.
	  * `Start` elects the brain-owner client via the BRAIN_OWNER_ATTRIBUTE
	    and re-elects on join/leave; NPCClient boots/tears the machine on the
	    attribute change.
]=]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local characterCtxUtils = require(ReplicatedStorage.Shared.Helpers.shared_services.characterCtxUtils)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local NpcConstants = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.NpcConstants)

-- Mirror of CombatMediator.CharacterAdded: abilities and AttckInvoker gate on
-- these attributes, an NPC without them can neither swing nor be stunned.
local COMBAT_ATTRIBUTES: { [string]: any } = {
	Combo = 1,
	Stunned = false,
	Swing = false,
	Attacking = false,
	IsRagdoll = false,
	Iframes = false,
	IsBlocking = false,
	Blocking = 0,
	Parrying = false,
}

local NPCServer = {}
NPCServer.__index = NPCServer

export type NPCServer = typeof(setmetatable(
	{} :: {
		char: Model,
		_serviceBag: any,
		_binderProvider: any,
		_maid: any,
		_initialized: boolean,
		_started: boolean,
	},
	NPCServer
))

function NPCServer.new(char: Model, serviceBag: any, binderProvider: any): NPCServer
	local self = setmetatable({}, NPCServer)

	self.char = char
	self._serviceBag = serviceBag
	self._binderProvider = binderProvider
	self._maid = Maid.new()
	self._initialized = false
	self._started = false

	for attribute, value in COMBAT_ATTRIBUTES do
		char:SetAttribute(attribute, value)
	end

	-- Same body-part tagging players get: keeps the grenade aimer raycasts
	-- treating NPC rigs like characters.
	local function tagIfPart(descendant: Instance)
		if descendant:IsA("BasePart") then
			CollectionService:AddTag(descendant, Constants.peepholeExclude)
		end
	end
	for _, descendant in char:GetDescendants() do
		tagIfPart(descendant)
	end
	self._maid:GiveTask(char.DescendantAdded:Connect(tagIfPart))

	CollectionService:AddTag(char, "AnimationHandler")
	CollectionService:AddTag(char, "CD")
	CollectionService:AddTag(char, "Armed")

	return self :: NPCServer
end

--[=[
	Equips the NPC's first Tool child server-side so the server Weapon
	strategy exists for AttckInvoker's npcChar routing.
]=]
function NPCServer.Init(self: NPCServer)
	if self._initialized then
		return
	end

	local tool = self.char:FindFirstChildOfClass("Tool")
	if not tool then
		warn(`[NPCServer] {self.char:GetFullName()} has no Tool child to equip`)
		return
	end
	-- Flag up-front: ServiceRoot reaches Init through both the class-added
	-- signal and the pre-placed GetAll sweep, which can overlap.
	self._initialized = true
	local toolName = tool.Name:lower()

	local animBinder = self._binderProvider:Get("AnimationHandler")

	self._maid:GivePromise(animBinder:Promise(self.char)):Then(function(weaponContext)
		local animHandler = animBinder and animBinder:Get(self.char)
		self._animHandler = animHandler
		-- ServiceRoot's AnimationHandler class-added connection may have already
		-- inited this handler (the runtime tag fires both paths); Init asserts on
		-- a double call, so check first instead of assuming it's uninitialized.
		if not animHandler:IsInitialized() then
			animHandler:Init(self.char:WaitForChild("Humanoid"))
		end
		characterCtxUtils:InitCharAnim(self.char, toolName, animHandler)
		
		local weaponBinder = self._binderProvider:Get("Armed")
		self._maid:GivePromise(weaponBinder:Promise(self.char)):Then(function(weaponContext)
			characterCtxUtils:InitCharWeapon(self.char, toolName, weaponContext)
		end)
	end)
end

--[=[
	Brain-owner election: exactly one client may run this NPC's state machine.
]=]
function NPCServer.Start(self: NPCServer)
	if self._started then
		return
	end
	self._started = true

	self._maid:GiveTask(Players.PlayerAdded:Connect(function()
		self:_electBrainOwner()
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_electBrainOwner(player)
	end))
	self:_electBrainOwner()
end

-- The brain runs on the owner client, which drives the rig with
-- Humanoid:MoveTo. That only simulates if the client owns the rig's
-- assembly, so network ownership must follow the elected brain — otherwise
-- the server keeps simulating the NPC standing still (MoveToFinished never
-- fires on the client and it stays put). `player == nil` reverts to server.
function NPCServer._setNetworkOwner(self: NPCServer, player: Player?)
	local hrp = self.char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or hrp.Anchored then
		return
	end
	-- Errors if any assembly part is anchored or the rig is mid-despawn.
	pcall(function()
		hrp:SetNetworkOwner(player)
	end)
end

-- Keeps the current owner when still valid; otherwise picks a random player
-- (random spreads the brains of many NPCs across the connected clients).
function NPCServer._electBrainOwner(self: NPCServer, leaving: Player?)
	local currentOwner = self.char:GetAttribute(NpcConstants.BRAIN_OWNER_ATTRIBUTE)
	print("currentOwner ", currentOwner)

	local candidates = {}
	for _, player in Players:GetPlayers() do
		if player ~= leaving then
			if player.UserId == currentOwner then
				return
			end
			table.insert(candidates, player)
		end
	end

	if #candidates == 0 then
		self.char:SetAttribute(NpcConstants.BRAIN_OWNER_ATTRIBUTE, nil)
		self:_setNetworkOwner(nil)
		return
	end

	local elected = candidates[math.random(#candidates)]
	self.char:SetAttribute(NpcConstants.BRAIN_OWNER_ATTRIBUTE, elected.UserId)
	self:_setNetworkOwner(elected)
end

function NPCServer.Destroy(self: NPCServer)
	self._maid:DoCleaning()
	self.char:SetAttribute(NpcConstants.BRAIN_OWNER_ATTRIBUTE, nil)
	-- Untag so the Weapon/AnimationHandler binders run their own Destroy.
	CollectionService:RemoveTag(self.char, "Armed")
	CollectionService:RemoveTag(self.char, "AnimationHandler")
	CollectionService:RemoveTag(self.char, "CD")
end

return NPCServer
