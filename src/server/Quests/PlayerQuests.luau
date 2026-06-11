--[=[
	@class PlayerQuests
	Live per-player quest state, constructed by QuestHandler (a PlayerBinder)
	on PlayerAdded. `questsList` is the live table that gets SetAsync'd back to
	the DataStore on PlayerRemoving (`GetSaveData`).

	Progress is driven by kind: many quests can react to the same event
	(`IncreaseProgress("kill", 1)` bumps every active kill quest), so other
	services never talk to a quest table directly — they only report kinds.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestsData = require(ReplicatedStorage.Shared.Quests.QuestsData)
local questTypes = require(ReplicatedStorage.Shared.Quests.questTypes)

local QuestProgressRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.QuestProgress

local PlayerQuests = {}
PlayerQuests.__index = PlayerQuests

type self = {
	_player: Player,
	_byKind: { [questTypes.QuestKind]: { questTypes.QuestProgress } },
	questsList: questTypes.QuestsSaveData,
}
export type PlayerQuests = typeof(setmetatable({} :: self, PlayerQuests))

function PlayerQuests.new(player: Player, savedQuests: questTypes.QuestsSaveData?): PlayerQuests
	local self = setmetatable({} :: self, PlayerQuests)
	self._player = player
	self._byKind = {}
	self.questsList = savedQuests or {}

	-- Drop stale saves whose quest left the pool, index the rest by kind
	for questId, progress in pairs(self.questsList) do
		if QuestsData.FindQuest(questId) then
			self:_indexByKind(progress)
		else
			warn(string.format("[PlayerQuests] - Dropping saved progress for unknown quest %q", questId))
			self.questsList[questId] = nil
		end
	end

	return self
end

function PlayerQuests.AcceptQuest(self: PlayerQuests, questId: string): questTypes.QuestProgress
	local existing = self.questsList[questId]
	if existing then
		-- Retake: just resync the client with the saved progress
		QuestProgressRemote:FireClient(self._player, existing)
		return existing
	end

	local quest = QuestsData.GetQuest(questId)
	local progress: questTypes.QuestProgress = {
		questId = quest.questId,
		kind = quest.kind,
		progress = 0,
		requiredAmount = quest.requiredAmount,
		completed = false,
		delivered = false,
	}

	self.questsList[questId] = progress
	self:_indexByKind(progress)

	if quest.onAccept then
		quest.onAccept(self._player, progress)
	end
	QuestProgressRemote:FireClient(self._player, progress)

	return progress
end

function PlayerQuests.IncreaseProgress(self: PlayerQuests, kind: questTypes.QuestKind, amount: number?)
	local kindList = self._byKind[kind]
	if not kindList then
		return
	end

	for _, progress in ipairs(kindList) do
		if progress.completed then
			continue
		end

		progress.progress = math.min(progress.progress + (amount or 1), progress.requiredAmount)

		local quest = QuestsData.GetQuest(progress.questId)
		if progress.progress >= progress.requiredAmount then
			progress.completed = true
			if quest.onCompleted then
				quest.onCompleted(self._player, progress)
			end
		elseif quest.onProgress then
			quest.onProgress(self._player, progress)
		end

		QuestProgressRemote:FireClient(self._player, progress)
	end
end

--[=[
	Replays every progress entry to the client. The join-time AcceptQuest
	burst can fire before the client UI has connected OnClientEvent (those
	events are lost), so QuestsList fires the remote back once on mount and
	the server answers with this.
]=]
function PlayerQuests.Resync(self: PlayerQuests)
	for _, progress in pairs(self.questsList) do
		QuestProgressRemote:FireClient(self._player, progress)
	end
end

function PlayerQuests.GetSaveData(self: PlayerQuests): questTypes.QuestsSaveData
	return self.questsList
end

function PlayerQuests._indexByKind(self: PlayerQuests, progress: questTypes.QuestProgress)
	local kindList = self._byKind[progress.kind]
	if not kindList then
		kindList = {}
		self._byKind[progress.kind] = kindList
	end
	table.insert(kindList, progress)
end

return PlayerQuests
