--[=[
	@class teamConstants
	Per-team CLIENT visual identity, keyed by the team id (the Team instance's
	Name, i.e. the TEAM_ATTRIBUTE / resolveTeam result — "Crimson" / "Azure",
	see GameModeConfig). Kept separate from each Team's `TeamColor` so the carry
	visuals can use a deliberate, tuned palette (crimson / dark blue) instead of
	the raw BrickColor the gameplay teams ship with.

	Consumed by the CTF carry visuals: GroundPath tints its navigation arrows by
	`TEAM_COLORS[team]`, FlagBillboard picks the overhead icon (icons live in
	`assets`, not here — only colors belong in this file).
]=]

local teamConstants = {}

-- Arrow / accent colour per team id. Add an entry when you add a team.
teamConstants.TEAM_COLORS = {
	Crimson = Color3.fromRGB(220, 20, 60), -- crimson
	Azure = Color3.fromRGB(0, 0, 139), -- dark blue
} :: { [string]: Color3 }

-- Fallback for a teamless carrier or a team with no entry above (a
-- misconfiguration, not a crash) so the visuals still render something neutral.
teamConstants.DEFAULT_COLOR = Color3.fromRGB(200, 200, 200)

return teamConstants
