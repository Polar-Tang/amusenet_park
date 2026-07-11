local module = {}

module["RAY_EXCLUDE_TAG"] = "RayExclude"
module.NON_STATIC_TAG = "NonStatic"
-- Tag put on every player character part (CombatMediator.CharacterAdded) so the
-- grenade aimer raycasts can exclude all bodies via CollectionService:GetTagged.
module.peepholeExclude = "PeepholeExclude"
module.FIRE_MODE = {
	SEMI = "Semi",
	AUTO = "Auto",
}
module.AMMO_ATTRIBUTE = "_ammo"
module.RELOADING_ATTRIBUTE = "_reloading"
module.DAMAGE_ATTRIBUTE = "damage"
module.FIRE_MODE_ATTRIBUTE = "fireMode"
module.MAGAZINE_SIZE_ATTRIBUTE = "magazineSize"
module.RANGE_ATTRIBUTE = "range"
module.RATE_OF_FIRE_ATTRIBUTE = "rateOfFire"
module.RELOAD_TIME_ATTRIBUTE = "reloadTime"
module.RAYS_PER_SHOT_ATTRIBUTE = "raysPerShot"
module.RAY_RADIUS_ATTRIBUTE = "rayRadius"
module.SPREAD_ATTRIBUTE = "spread"
module.VIEW_MODEL_ATTRIBUTE = "viewModel"
module.RECOIL_MIN_ATTRIBUTE = "recoilMin"
module.RECOIL_MAX_ATTRIBUTE = "recoilMax"
module.UNANCHORED_IMPULSE_FORCE_ATTRIBUTE = "unanchoredImpulseForce"
module.AIM_ASSIST_RANGE_ATTRIBUTE = "aimAssistRange"
module.AIM_ASSIST_FOV_ATTRIBUTE = "aimAssistFov"
module.AIM_ASSIST_FRICTION_STRENGTH_ATTRIBUTE = "aimAssistFrictionStrength"
module.AIM_ASSIST_TRACKING_STRENGTH_ATTRIBUTE = "aimAssistTrackingStrength"
module.AIM_ASSIST_CENTERING_STRENGTH_ATTRIBUTE = "aimAssistCenteringStrength"

module.KEYBOARD_RELOAD_KEY_CODE = Enum.KeyCode.R
module.GAMEPAD_RELOAD_KEY_CODE = Enum.KeyCode.ButtonX

-- Pixel size under which a screen is considered 'small'. This is the same threshold used by the default touch UI.
module.UI_SMALL_SCREEN_THRESHOLD = 500
-- Amount to scale the UI when on a small screen
module.UI_SMALL_SCREEN_SCALE = 0.6

module.HITMARKER_SOUND_DELAY = 0.1

-- Aim assist
module.AIM_ASSIST_BIND_NAME_START = "AimAssistStart"
module.AIM_ASSIST_BIND_NAME_APPLY = "AimAssistApply"
module.AIM_ASSIST_TARGET_TAG = "Target"

module.AIM_ASSIST_DEADZONE = 0.1
module.AIM_ASSIST_INACTIVITY = 0.1
module.AIM_ASSIST_MIN_RANGE = 10
-- Half-angle (degrees) of the forward cone the mobile/gamepad auto-aim scans
-- for targets. Only humanoids within this cone of the camera look vector are
-- considered; used by findAimAssistTarget.
module.AIM_ASSIST_CONE_DEG = 25
-- Exponential follow rate of the continuous auto-aim lock (higher = snappier;
-- camera lag onto a moving target is ~1/this seconds). Decoupled from fire rate.
module.AIM_ASSIST_RESPONSIVENESS = 12
-- Fallback scan range when a weapon has no `weapon_stats.range` (studs).
module.AIM_ASSIST_RANGE_DEFAULT = 250
-- Grace window (seconds) the auto-aim lock is held after the scan stops
-- finding a target. Target scans flicker (a one-frame missing PrimaryPart),
-- and releasing instantly snaps the camera back to the player's manual aim, so
-- we only release once the target has been gone continuously for this long.
module.AIM_ASSIST_LOSS_GRACE = 0.2
-- Radius of the line-of-sight probes in the auto-aim scan. A single thin raycast
-- rejects a target the instant a sliver grazes the dead-centre line, but the fat
-- magnetism radius the bullet uses (~2) is too WIDE for a LoS test: it can't fit
-- through a window/doorway the target is plainly visible through, so it snags the
-- frame and reports no sight. The scan instead casts one THIN ray per body part
-- (see findAimAssistTarget.hasLineOfSight) — thin enough to thread an opening,
-- and the per-part coverage handles the grazing case the single ray missed. Keep
-- this small (well under the narrowest opening the target can be seen through).
-- Shared across every weapon: auto-aim range/feel is uniform, no per-weapon stat.
module.AIM_ASSIST_RAY_RADIUS = 0.25
-- How often the always-on auto-aim scan re-raycasts for a target (seconds). The
-- scan runs from weapon equip (RangeAttackClient:Start) rather than per render
-- frame: target acquisition drives both the camera lock and continuous fire, and
-- the line-of-sight raycasts are too costly to run every frame. The LerpCamera
-- effect still smooths the lock every frame between scans, so a coarse scan rate
-- only affects how quickly a *newly appeared* target is picked up, not aim feel.
module.AIM_ASSIST_SCAN_INTERVAL = 0.05

-- View model
module.VIEW_MODEL_BIND_NAME = "BlasterViewModel"
module.VIEW_MODEL_OFFSET = CFrame.new(0, -0.5, -1)
module.VIEW_MODEL_BOBBING_SPEED = 0.4
module.VIEW_MODEL_BOBBING_AMOUNT = 0.05
module.VIEW_MODEL_BOBBING_TRANSITION_SPEED = 10
module.VIEW_MODEL_RELOAD_FADE_TIME = 0.1
-- Recoil
module.RECOIL_BIND_NAME = "Recoiler"
module.RECOIL_STOP_SPEED = 10
module.RECOIL_ZOOM_RETURN_SPEED = 20
module.RECOIL_DEFAULT_FOV = 70
-- VFX
module.LASER_BEAM_VISUAL_SPEED = 200

module.recoil_offset = Vector3.new(0, 1.25, 0)

module.dashTime = 3
module.dashDistance = 20
module.slideInitialSpeed = 55

-- Binder tags (CollectionService). The single source of truth for the tag →
-- binder mapping both ServiceRoots register and for the AddTag calls that bind a
-- character into the combat loop. Keep these in sync with the `Binders` table in
-- src/server/ServiceRoot.server.luau and src/client/UI/ServiceRoot.client.luau.
module.ARMED_TAG = "Armed" -- the weapon context binder (Weapon server / WeaponClient)
module.ANIMATION_HANDLER_TAG = "AnimationHandler" -- the per-character AnimationHandler binder
module.CD_TAG = "CD" -- Quenty Cooldown binder

-- NPC
-- Tag carried by every NPC character model; binds the NPC binders (client
-- brain / server Armed mirroring) and marks the model as a valid client-driven
-- shooter for AttckInvoker's npcChar routing.
module.NPC_TAG = "NPC"
-- Tag carried by the workspace.goal_* parts NPCs patrol between.
module.NPC_GOALS_TAG = "NPC_goals"
module.MATCH_FOUND_TOPIC= "MatchFound"
module.LOBBY_PLACEID = 82965737458659

-- Server ability Execute rejection reasons, propagated up through
-- WeaponBase:Execute -> Weapon.Execute so AttckInvoker can report cheat
-- evidence (a CD-rejected NPC-routed shot = the brain owner fired faster
-- than the weapon allows).
module.REJECT_REASON_COOLDOWN = "cooldown"

return module
