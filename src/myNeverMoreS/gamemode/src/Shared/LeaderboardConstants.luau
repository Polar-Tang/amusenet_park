--[=[
	@class LeaderboardConstants
	Wiring constants for the per-player leaderboard. Shared because the server
	(LeaderboardService) builds the folder of IntValues and the client observes
	the very same folder — both sides must agree on the folder name and the stat
	keys, so neither hardcodes the literal.

	Folder shape (under ReplicatedStorage), built by LeaderboardService:

		<FOLDER_NAME> (Folder)
		  [tostring(player.UserId)] (Folder = one PlayerRegistry)
		    kills      (IntValue)  -- always present
		    deaths     (IntValue)  -- always present
		    damage     (IntValue)  -- always present
		    flags      (IntValue?) -- CTF only, created lazily on first capture
		    hill_time  (IntValue?) -- KOTH only, created lazily on first tick in the hill

	The base three (KILLS/DEATHS/DAMAGE) are seeded for every player at register
	time; the optional fields appear only in the mode that tracks them (a mode
	calls LeaderboardService:AddStat with its own key, which creates the IntValue
	on first use). A client observer can therefore mirror the whole registry by
	just iterating its children — no per-mode branching.
]=]

local LeaderboardConstants = {}

-- The single ReplicatedStorage folder every PlayerRegistry lives under.
LeaderboardConstants.FOLDER_NAME = "Leaderboard"

-- Base stats, seeded for every player at register time.
LeaderboardConstants.STAT_KILLS = "kills"
LeaderboardConstants.STAT_DEATHS = "deaths"
LeaderboardConstants.STAT_DAMAGE = "damage"

-- Mode-specific stats, created lazily by the owning mode (CTF / KOTH).
LeaderboardConstants.STAT_FLAGS = "flags"
LeaderboardConstants.STAT_HILL_TIME = "hill_time"

return LeaderboardConstants
