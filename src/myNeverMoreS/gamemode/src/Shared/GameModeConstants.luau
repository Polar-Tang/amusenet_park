--[=[
	@class GameModeConstants
	Tuning + wiring constants for the game-mode framework. Shared because the
	damage check (client prediction + server validation) and the HUD both read
	the team attribute / match-over flag.
]=]

local GameModeConstants = {}

-- Mode picked when no lobby payload ever arrives (Studio playtests,
-- direct-join servers). Must be a key of GameModeConfig.
GameModeConstants.DEFAULT_MODE = "ctf"--"tdm"

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

-- KOTH: the hill. Tag exactly one BasePart in the map with this; the mode
-- scans whoever stands inside its bounding box (ZoneController).
GameModeConstants.KOTH_ZONE_TAG = "KOTH_zone"
-- How often the hill re-scans its occupants (seconds). Throttled INSIDE
-- ZoneController like TargetController.Scan gates VISION_SCAN_INTERVAL, so a
-- mode ticking every Heartbeat is still cheap.
GameModeConstants.KOTH_SCAN_INTERVAL = 0.5
-- How often a controlling team banks points, and how many per bank. With
-- POINTS_PER_TICK=1 and TICK_INTERVAL=1, a held hill scores 1pt/sec.
GameModeConstants.KOTH_TICK_INTERVAL = 1
GameModeConstants.KOTH_POINTS_PER_TICK = 1
-- Attribute the mode writes on the zone part so HUD/visuals can read the live
-- controller ("" = contested or empty).
GameModeConstants.KOTH_CONTROLLER_ATTRIBUTE = "ControllingTeam"

-- CTF: flags, carriers and home zones, all authored in the map.
--   * Tag one BasePart per team with CTF_FLAG_TAG, each carrying the
--     TEAM_ATTRIBUTE of the team that OWNS/defends it (enemies steal it).
--   * Tag one BasePart per team with CTF_HOME_ZONE_TAG (same TEAM_ATTRIBUTE) as
--     that team's capture zone — bring the enemy flag here to score.
GameModeConstants.CTF_FLAG_TAG = "CTF_flag"
GameModeConstants.CTF_HOME_ZONE_TAG = "CTF_home"
-- Server-authored tag on the character currently carrying a flag. THE ONLY place
-- this string is hardcoded: the Flag binder (server) sets/clears it, while
-- FlagBillboard (client) and the capture ZoneController read it. Never duplicate
-- the literal — always reference this constant.
GameModeConstants.CTF_CARRIER_TAG = "CTF_carrier"
-- The Flag binder re-validates the prompt grab against this radius (studs): the
-- client-side ProximityPrompt distance is enforced only on the triggering
-- client and is therefore spoofable.
GameModeConstants.CTF_GRAB_DISTANCE = 12
GameModeConstants.CTF_POINTS_PER_CAPTURE = 1
-- Capture-zone scan + tick cadence (seconds). The scan throttles itself inside
-- ZoneController just like KOTH, so the Heartbeat tick is cheap.
GameModeConstants.CTF_SCAN_INTERVAL = 0.5
GameModeConstants.CTF_TICK_INTERVAL = 0.5
-- FlagBillboard placeholder art — swap for the real "carrying the flag" icon.
GameModeConstants.CTF_BILLBOARD_IMAGE = "rbxassetid://0"

return GameModeConstants
