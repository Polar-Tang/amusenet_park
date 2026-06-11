--[=[
	@class QuestsData
	Registry of every quest table under `Quests/`, keyed by `questId`.
	Use `GetQuest` for lookups that must succeed (throws on typos) and
	`FindQuest` when a stale save may reference a removed quest.

	Shared so both PlayerQuests (server) and the QuestsList UI (client)
	read the same pool.
]=]

local questTypes = require(script.Parent.questTypes)

local QuestsData = {}

local allQuests: { [string]: questTypes.Quest } = {}
for _, questModule in script.Parent.Quests:GetChildren() do
	local quest = require(questModule) :: questTypes.Quest
	assert(type(quest.questId) == "string", string.format("[QuestsData] - %q has no questId", questModule.Name))
	assert(type(quest.kind) == "string", string.format("[QuestsData] - %q has no kind", quest.questId))
	assert(type(quest.requiredAmount) == "number", string.format("[QuestsData] - %q has no requiredAmount", quest.questId))
	assert(allQuests[quest.questId] == nil, string.format("[QuestsData] - duplicated questId %q", quest.questId))
	allQuests[quest.questId] = quest
end

QuestsData.allQuests = allQuests

function QuestsData.FindQuest(questId: string): questTypes.Quest?
	return allQuests[questId]
end

function QuestsData.GetQuest(questId: string): questTypes.Quest
	local quest = allQuests[questId]
	assert(quest, string.format("[QuestsData] - No quest with id %q", tostring(questId)))
	return quest
end

return QuestsData
