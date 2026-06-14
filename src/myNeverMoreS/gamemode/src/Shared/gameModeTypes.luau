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
	equipDefaultWeapon: boolean, -- false => no fist on spawn
	-- true => clone ServerStorage.weapons into every real player's Backpack on
	-- spawn (replaces StarterPack). LMS sets this false: survivors carry only the
	-- default fist (equipDefaultWeapon stays true), never the gun loadout.
	giveLoadout: boolean,
}

-- The FULL broadcast the lobby publishes over MATCH_FOUND_TOPIC and mirrors
-- into the teleported players' TeleportData. Every field is optional: it crosses
-- a codebase boundary (the lobby is a separate place) so MatchListener validates
-- each one at runtime before trusting it. Field-by-field consumption:
--   matchId         -> narrowed into MatchPayload, forwarded to StartMatch
--   botCount, mode  -> read by fill() into MatchPayload
--   privateServerId -> isForThisServer primary identity check (== game.PrivateServerId)
--   userIds         -> isForThisServer fallback identity check
--   accessCode      -> teleport credential ONLY; a reserved server can't read its
--                      own accessCode back, so MatchListener never touches it
export type MatchFoundPayload = {
	matchId: string?,
	accessCode: string?,
	userIds: { number }?,
	botCount: number?,
	mode: string?,
	privateServerId: string?,
}

-- The narrowed subset GameModeService:StartMatch actually consumes. MatchListener
-- distills a MatchFoundPayload (or its TeleportData mirror) down to this.
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

-- The strategy surface GameModeService drives AND the shape every mode shares:
-- BaseMode implements it whole, and each concrete mode `&`-extends it with its
-- own fields (TeamMode adds `_npc`, LastManStanding adds its alive set, …). The
-- service only calls the hooks; `config`/`_deps`/`_maid` are the protected
-- context the modes themselves read, declared here so an extending mode inherits
-- the fields its overrides touch without redeclaring them.
export type GameMode = {
	config: ModeConfig,
	_deps: GameModeDeps?,
	_maid: any,

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

-- The class-table side of a mode strategy. GameModeService.MODE_REGISTRY maps a
-- mode id to one of these and `.new(config)` is the only member it calls; `T` is
-- the concrete mode the class builds (defaults to the base interface).
export type GameModeClass<T = GameMode> = {
	new: (config: ModeConfig) -> T,
}

--[=[
	The persistent game-mode context, generic over the GameMode strategy `T` it
	runs (defaults to the base interface; a caller that knows which mode it
	launched can specialize). The service owns ScoreState, the Team instances,
	the timer, win checks and replication — the generic documents that all of its
	hooks drive one `T`-shaped strategy at a time (`MODE_REGISTRY: { [string]:
	GameModeClass<T> }`).
]=]
export type GameModeService<T = GameMode> = {
	ServiceName: string,
	StartMatch: (self: GameModeService<T>, payload: MatchPayload) -> (),
	CanRespawn: (self: GameModeService<T>, player: Player) -> boolean,
	ShouldEquipDefaultWeapon: (self: GameModeService<T>) -> boolean,
	GetScoreState: (self: GameModeService<T>) -> ScoreState,
	Init: (self: GameModeService<T>, bag: any) -> (),
	Start: (self: GameModeService<T>) -> (),
}

return {}
