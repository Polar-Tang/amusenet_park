--[=[
	@class GameModeConstants
	Tuning + wiring constants for the game-mode framework. Shared because the
	damage check (client prediction + server validation) and the HUD both read
	the team attribute / match-over flag.
]=]

local GameModeConstants = {}

-- Mode picked when no lobby payload ever arrives (Studio playtests,
-- direct-join servers). Must be a key of GameModeConfig.
GameModeConstants.DEFAULT_MODE = "tdm"

-- String team name set on NPC rigs (players carry their team on player.Team;
-- a rig has no Player, so the attribute is its replicated team identity).
GameModeConstants.TEAM_ATTRIBUTE = "GameTeam"

-- Workspace attribute raised by GameModeService._endMatch. EffectService's
-- damage block early-returns on it — one choke point freezes all combat.
GameModeConstants.MATCH_OVER_ATTRIBUTE = "MatchOver"

-- MatchListener fallback: if no MessagingService/TeleportData trigger fired
-- after this many seconds, start DEFAULT_MODE with this many bots.
GameModeConstants.STUDIO_FALLBACK_SECONDS = 5
GameModeConstants.STUDIO_FALLBACK_BOT_COUNT = 4

-- Delay before a dead bot is replaced on the same team (TDM keeps teams full).
GameModeConstants.NPC_RESPAWN_DELAY = 5

return GameModeConstants
