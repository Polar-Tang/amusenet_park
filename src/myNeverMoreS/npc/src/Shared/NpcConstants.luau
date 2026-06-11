--[=[
	@class NpcConstants

	Tuning for the client-driven NPC brain (states, transitions, controllers).
	Tags shared with the combat pipeline (NPC_TAG / NPC_GOALS_TAG) live in
	`abilities/src/Shared/Constanst.luau` next to the other combat tags.
]=]

local NpcConstants = {}

-- Patrol
-- A goal closer than this (planar distance, studs) counts as reached.
NpcConstants.GOAL_REACHED_DISTANCE = 6
-- Seconds between Patrol's "did my move die without reaching the goal" checks.
NpcConstants.REPATH_INTERVAL = 2

-- Idle
-- Seconds spent idling on a reached goal before patrolling again.
NpcConstants.IDLE_DURATION = 20

-- Vision (TargetController)
NpcConstants.VISION_RANGE = 120
-- Half-angle (degrees) of the simulated camera's forward cone. Wider than the
-- player aim-assist cone: this is awareness, not aim snapping.
NpcConstants.VISION_FOV_DEG = 60
-- Line-of-sight raycasts are expensive; scans between these are cached.
NpcConstants.VISION_SCAN_INTERVAL = 0.2
-- Seconds a lost target stays remembered before Attacking gives up, so a
-- one-scan LoS flicker doesn't bounce Attacking <-> Patrol.
NpcConstants.TARGET_LOSS_GRACE = 1

-- Brain ownership. Exactly one client may run an NPC's state machine
-- (duplicate brains double-fire the weapon); the server elects the owner and
-- writes their UserId into this attribute (see NPCServer / NPCClient.Start).
NpcConstants.BRAIN_OWNER_ATTRIBUTE = "NpcBrainOwner"

return NpcConstants
