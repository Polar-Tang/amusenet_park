--[=[
	@class questTypes
	Shared shape every quest table must follow. Quests are pure data tables
	living in `Quests/`; the generic PlayerQuests handler dispatches into the
	lifecycle callbacks, mirroring how CombatConfig drives the ability classes.
	Anything unique to one quest (rewards, custom notifications) belongs in its
	table, never in the handler.
]=]

export type QuestKind = "kill" | "damage" | "catch"

-- Per-player live progress for one quest. This is exactly what gets
-- SetAsync'd to the DataStore on PlayerRemoving, so it must stay
-- JSON-serializable (no Instances, no functions).
export type QuestProgress = {
	questId: string,
	kind: QuestKind,
	progress: number,
	requiredAmount: number,
	completed: boolean,
	delivered: boolean,
}

export type Quest = {
	questId: string,
	kind: QuestKind,
	title: string,
	description: string,
	requiredAmount: number,

	onAccept: ((player: Player, progress: QuestProgress) -> ())?,
	onProgress: ((player: Player, progress: QuestProgress) -> ())?,
	onCompleted: ((player: Player, progress: QuestProgress) -> ())?,
}

export type QuestsSaveData = { [string]: QuestProgress }

return {}
