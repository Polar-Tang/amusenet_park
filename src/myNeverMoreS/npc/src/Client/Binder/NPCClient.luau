--[=[
	@class NPCClient

	The "NPC" binder, client side. The NPC's *brain* lives here: a
	RobloxStateMachine (Patrol / Idle / Attacking) running on the client for
	performance, while the server NPC binder only tags the rig and elects which
	client owns the brain.

	Lifecycle:
	  * `new` tags the rig "Armed" (idempotent with the server tag) and builds
	    the maid + fields. No yields — binder constructors race the untag signal.
	  * `Init` finds the first Tool child and equips it through the same
	    characterCtxUtils surface players use (waiting on the Armed binder via
	    `Promise`, since binder start order is not guaranteed).
	  * `Start` watches the brain-owner attribute: exactly one client runs each
	    NPC's machine, otherwise every client would fire the weapon and the
	    server would apply duplicated damage.
	  * `Destroy` runs automatically on untag (MaidTaskUtils.doTask).
]=]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(ReplicatedStorage.Shared.StateMachine)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local characterCtxUtils = require(ReplicatedStorage.Shared.Helpers.shared_services.characterCtxUtils)
local OtherAnims = require(ReplicatedStorage.Shared.Animations.OtherAnims)
local NpcConstants = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.NpcConstants)
local setCtx = require(script.Parent.helpers.setCtx)

local StatesFolder = ReplicatedStorage.Nevermore.Custom.npc.src.Client.States

local NPCClient = {}
NPCClient.__index = NPCClient

export type NPCClient = typeof(setmetatable(
	{} :: {
		char: Model,
		state: any?,
		_serviceBag: any,
		_maid: any,
		_initialized: boolean,
	},
	NPCClient
))

function NPCClient.new(char: Model, serviceBag: any): NPCClient
	local self = setmetatable({}, NPCClient)

	self.char = char
	self.state = nil
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._initialized = false

	-- Armed context for this rig. The server tags too (for the server Weapon);
	-- AddTag is idempotent so double-tagging is harmless.
	CollectionService:AddTag(char, "Armed")
	CollectionService:AddTag(char, "AnimationHandler")

	return self :: NPCClient
end

--[=[
	Equips the NPC's Tool through the player equip surface. Waits on the
	Armed binder promise because the NPC binder may construct before the
	Armed class exists for this rig.
]=]
function NPCClient.Init(self: NPCClient)
	if self._initialized then
		return
	end

	local tool = self.char:FindFirstChildOfClass("Tool")
	if not tool then
		warn(`[NPCClient] {self.char:GetFullName()} has no Tool child to equip`)
		return
	end
	self._initialized = true
	local toolName = tool.Name:lower()

	local BinderProvider = self._serviceBag:GetService(_G.BinderProvider)

	local animBinder = BinderProvider:Get("AnimationHandler")

	self._maid:GivePromise(animBinder:Promise(self.char)):Then(function(weaponContext)
		local animHandler = animBinder and animBinder:Get(self.char)
		self._animHandler = animHandler
		animHandler:Init(self.char:WaitForChild("Humanoid"))
		-- NPCs don't run the Animate module (which is what registers the
		-- OtherAnims defaults for player characters), so register the default
		-- poses here. Without this, MovementController's LoadAnimation(.., "Walk")
		-- hits an unregistered name and errors in _initDescriptior.
		animHandler:AddAnimations(OtherAnims)
		characterCtxUtils:InitCharAnim(self.char, toolName, animHandler)
		
		local weaponBinder = BinderProvider:Get("Armed")
		self._maid:GivePromise(weaponBinder:Promise(self.char)):Then(function(weaponContext)
			characterCtxUtils:InitCharWeapon(self.char, toolName, weaponContext)
		end)
	end)
end

--[=[
	Boots/tears down the brain whenever the server re-elects the owning
	client (player left, NPC streamed, ...).
]=]
function NPCClient.Start(self: NPCClient)
	self._maid:GiveTask(
		self.char:GetAttributeChangedSignal(NpcConstants.BRAIN_OWNER_ATTRIBUTE):Connect(function()
			self:_updateBrainOwnership()
		end)
	)
	self:_updateBrainOwnership()
end

function NPCClient._updateBrainOwnership(self: NPCClient)
	local owner = self.char:GetAttribute(NpcConstants.BRAIN_OWNER_ATTRIBUTE)
	local isOwner = owner == Players.LocalPlayer.UserId

	if isOwner and not self.state then
		self:_startMachine()
	elseif not isOwner and self.state then
		self:_stopMachine()
	end
end

function NPCClient._startMachine(self: NPCClient)
	-- Brain-scoped maid: controllers + machine die together on handoff or
	-- untag, without touching the equip/ownership watch on the binder maid.
	local brainMaid = Maid.new()
	self._maid._brain = brainMaid

	self.state = StateMachine.new(
		"Patrol",
		StateMachine:LoadDirectory(StatesFolder),
		setCtx(self.char, self._serviceBag, brainMaid)
	)
	brainMaid:GiveTask(self.state)
end

function NPCClient._stopMachine(self: NPCClient)
	self.state = nil
	self._maid._brain = nil
end

function NPCClient.Destroy(self: NPCClient)
	self:_stopMachine()
	self._maid:DoCleaning()
	CollectionService:RemoveTag(self.char, "Armed")
end

return NPCClient
