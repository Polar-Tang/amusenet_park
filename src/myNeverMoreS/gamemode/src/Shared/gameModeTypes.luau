--[=[
	@class gameModeTypes
	Types for the game-mode framework: the data-driven ModeConfig (one entry
	per mode in GameModeConfig.luau), the replicated ScoreState snapshot, and
	the GameMode strategy surface every mode class implements.

	Division of labor (mirrors CameraMediator owning `_cameraState` while the
	FP/TP strategies stay thin): GameModeService owns ScoreState, the Team
	instances, the timer, win checks, replication and the end-of-match freeze;
	a strategy owns team-assignment policy, kill→score mapping, bot lifecycle
	and any per-mode world objects (future zone/flag binders).
]=]

export type TeamId = string

export type TeamSpec = {
	id: TeamId,
	displayName: string,
	color: BrickColor,
}

-- Data-driven mode declaration; GameModeConfig.luau holds one per mode id.
export type ModeConfig = {
	id: string,
	displayName: string,
	targetScore: number, -- kills (TDM) / points (KOTH) / captures (CTF)
	timeLimitSeconds: number,
	teams: { TeamSpec }?, -- nil => non-team mode (LMS)
	respawnEnabled: boolean, -- false => ServiceRoot denies RespawnRequest (LMS)
	equipDefaultWeapon: boolean, -- false => no fist on spawn (LMS)
}

-- What the lobby sends (MessagingService "MatchFound" payload / TeleportData).
-- accessCode / userIds / privateServerId pass through MatchListener untouched.
export type MatchPayload = {
	mode: string?,
	botCount: number?,
	matchId: string?,
}

export type MatchPhase = "waiting" | "active" | "ended"

-- The single source of truth, replicated whole over the MatchState remote
-- (server owns it, client upserts the snapshot — QuestProgress shape).
export type ScoreState = {
	phase: MatchPhase,
	modeId: string,
	scores: { [TeamId]: number },
	targetScore: number,
	matchEndTime: number?, -- workspace:GetServerTimeNow() epoch; client derives countdown
	winner: TeamId?, -- set when phase == "ended"; "draw" on tie
}

-- Handed to every strategy at Init. The strategy never touches the remote,
-- the timer or the win check — it only reports score (or, for modes whose win
-- isn't score-shaped, calls endMatch directly: LMS last-alive).
export type GameModeDeps = {
	serviceBag: any,
	addScore: (teamId: TeamId, amount: number) -> (),
	getScoreState: () -> ScoreState,
	endMatch: (winner: TeamId?) -> (),
}

export type GameMode = {
	config: ModeConfig,
	Init: (self: GameMode, deps: GameModeDeps) -> (),
	Start: (self: GameMode, payload: MatchPayload) -> (),
	Stop: (self: GameMode) -> (),
	-- MUST be idempotent: the match-start Players:GetPlayers() sweep and the
	-- PlayerAdded signal can overlap (same lesson as the NPC binder sweep).
	onPlayerAdded: (self: GameMode, player: Player) -> (),
	onPlayerRemoving: (self: GameMode, player: Player) -> (),
	onCharacterAdded: (self: GameMode, char: Model, player: Player?) -> (),
	onKill: (self: GameMode, attackerChar: Model, defenderChar: Model) -> (),
	Destroy: (self: GameMode) -> (),
}

return {}
