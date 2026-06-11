--[=[
	@class QuestHandler
	PlayerBinder of PlayerQuests handlers. Registered into the ServiceBag at
	ServiceRoot (before `serviceBag:Init()`), so any other service can progress
	quests without requiring quest internals:

		local questHandler = serviceBag:GetService(QuestHandler)
		local playerQuests = questHandler:GetHandler(player)
		if playerQuests then
			playerQuests:IncreaseProgress("kill", 1)
		end
]=]

local serverTypes = require(script.Parent.Parent.serverTypes)
local PlayerBinder = require(script.Parent.Parent.Utils.PlayerBinder)
local PlayerQuests = require(script.Parent.PlayerQuests)

local QuestHandler = PlayerBinder.new(PlayerQuests)
QuestHandler.ServiceName = "QuestHandler"

return QuestHandler :: serverTypes.PlayerBinder<PlayerQuests.PlayerQuests>
