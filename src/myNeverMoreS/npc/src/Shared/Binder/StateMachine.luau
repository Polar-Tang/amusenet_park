local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateMachine = require(ReplicatedStorage.StateMachine)
local setCTX = require(script.Parent.helpers.setCtx)
local StatesFolder = ReplicatedStorage.NPC.States

local StateMachineBinder = {}
StateMachineBinder.ServiceName = "StateMachine"
StateMachineBinder.__index = StateMachineBinder

function StateMachineBinder.new(char: Model, serviceBag)
	local self = setmetatable({}, StateMachineBinder)
	local proxPrompt = char:FindFirstAncestorOfClass("ProximityPrompt")
	self.id = HttpService:GenerateGUID()
	if not proxPrompt then
		local new_prompt: ProximityPrompt = Instance.new("ProximityPrompt")
		new_prompt.ObjectText = self.id
		new_prompt.MaxActivationDistance = 80
		new_prompt.Enabled = true
		new_prompt.Style = Enum.ProximityPromptStyle.Custom
		new_prompt.Parent = char
	end
	char:AddTag(self.id)
	self.char = char
	self.state = nil
	self._initialized = false
	self._players = {}
	self.serviceBag = serviceBag
	return self
end

-- this method is called on nearby players
function StateMachineBinder:Init(player)
	-- the state machine is like the npc's brain
	if self:IsInitialized() then
		table.insert(self._players, player)
		return
	end
	local state =
		StateMachine.new("Chasing", StateMachine:LoadDirectory(StatesFolder), setCTX(self.char, self.serviceBag))
	self.state = state
	table.insert(self._players, player, player.UserId)

	return self
end

function StateMachineBinder:IsInitialized()
	return next(self._players)
end

-- remove a player from the registry
function StateMachineBinder:OnRemove(player)
	-- the state machine is like the npc's brain

	table.remove(self._players, player.UserId)
	return self
end

function StateMachineBinder:Destroy()
	self.state:Destroy()
end
return StateMachineBinder
