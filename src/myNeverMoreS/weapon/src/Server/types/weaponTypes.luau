local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EffectTypes = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectTypes)
local AnimationHandler = require(ReplicatedStorage.Nevermore.Custom.animations.src.Binder.AnimationHandler)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
type WeaponStatsBase = weaponTypes.WeaponStatsBase
type WeaponStatsRange = weaponTypes.WeaponStatsRange
type AnimationHandler = AnimationHandler.AnimationHandlerType
--== CLASSES ==--

-- NEW ARGS
export type BaseAbilityConstructor = {
	keyCode: EnumItem?,
	key: { Name: string }?,
	animNames: { string },
	life_time: number?, -- This may be useful for not resolving the promise until the time us fulfil, meanwhile should live the hitbox effect (hitbox already live that long in the client, but the server resolve in the first target)
	type: string,
	cooldown: number?,
	attackType: string?,
	special_attack: boolean?,
	character: Model,
	weapon_stats: WeaponStatsBase,
	tool: Tool,
}

--[=[
	Server-side weapon context. Extends the shared `WeaponContextBase` with
	all the server-only state (defense system, hitbox promise registry,
	rig geometry helpers) and methods.

	The shared `EquiTool` / `UnequiTool` / `Destroy` contract is inherited
	verbatim, so `characterCtxUtils` can call it without branching.
]=]
export type WeaponContext = weaponTypes.WeaponContextBase & {
	-- Server-only properties
	_hitboxPromiseRegistry: any,
	_character_state: any,
	_weaponDefense: any,
	_defenseChain: { any },
	_contexts: { [string]: any },
	armName: string,
	torso: BasePart?,

	_animHandler: AnimationHandler,
	_weapon: any,--weaponTypes.WeaponStrategy?,
	-- Server-only methods
	RegisterAttackEffect: (self: WeaponContext, attackId: string, ctx: any) -> (),
	GetAttackEffect: (self: WeaponContext, attackId: string) -> any,
	TakeHit: (self: WeaponContext, context: any) -> (),
	increaseDmgCount: (self: WeaponContext, increase: number) -> (),
	OnIncomingAttack: (self: WeaponContext, hitData: any) -> (),
	SetActiveDefense: (self: WeaponContext, ctx: any) -> (),
	ClearActiveDefense: (self: WeaponContext, priority: any) -> (),
	PlaySound: (self: WeaponContext, lifeTime: number?, nameSound: string) -> (),
	ResolveHitboxPromise: (self: WeaponContext, attackID: string, hitTargets: any, hitPart: any) -> any,
	AddHitToPromise: (self: WeaponContext, attackID: string, hitTarget: any, hitPart: any) -> any,
	RejectHitboxPromise: (self: WeaponContext, attackID: string, ...any) -> any,
	RegisterHitboxPromise: (self: WeaponContext, data: any) -> (),
}

export type BaseAbility = {
	-- Core state

	character: Model,
	humanoid: Humanoid,
	hrp: BasePart,
	weapon_stats: WeaponStatsBase,
	type: "Attack" | "Defense" | "Others" | string,
	player: Player,
	_tool: Tool,

	life_time: number?,
	walk_speed_blocking: number,

	-- Cooldown
	CD: boolean,
	_cooldown: number,
	_comboController: any,

	-- Services / controllers
	_serviceBag: any,
	RagdollService: any,
	_weaponHandler: any,
	_animHandler: any,

	-- Animation data
	animNames: { string },
	_animName: string,
	_endFx: ((ability: BaseAbility) -> ())?,

	-- Sound
	sound_folder: Folder,

	-- Internals
	_lastAttackID: number,
	_maid: Maid.Maid,

	-- ===== Methods =====
	--[[
        new: (constructor: BaseAbilityConstructor) -> BaseAbility
        
        Creates a new BaseAbility instance from the provided constructor.
        
        @param constructor BaseAbilityConstructor -- The constructor configuration for the ability
        @return BaseAbility -- The newly created ability instance
    ]]
	new: (constructor: BaseAbilityConstructor) -> { self: BaseAbility },
	Init: (self: BaseAbility, params: { endFx: ((ability: BaseAbility) -> ())? }) -> (),
	PlaySound: (self: BaseAbility, nameSound: string, lifeTime: number?) -> (),

	resetAtt: (self: BaseAbility) -> (),
	StartCD: (self: BaseAbility) -> (),
	InitCDInst: (self: BaseAbility) -> (),

	_countAttack: (self: BaseAbility) -> (),
	_GenerateAttackID: (self: BaseAbility) -> string,

	GetCD: (self: BaseAbility) -> boolean,

	-- Must be overridden
	Execute: (self: BaseAbility, char: Model) -> (),

	Destroy: (self: BaseAbility) -> (),
}

-- || HITBOX TYPE || --

export type DotProductFilter = {
	dotProduct: number,
	referenceVector: Vector3,
	sourcePosition: Vector3,
}

export type HixboxDataConfig = {
	Time: number,
	Size: Vector3,
	CFrame: Vector3,
	Shape: "Box" | "Ball" | "TimedBox",
	HitMode: "Strong" | "Weak",
	strikes_hit: boolean?,
}

export type HitboxConfig = {
	attackId: string,
	Weapon: BasePart,
	referenceVector: Vector3,
	sourcePosition: Vector3,
	Attacker: Model,
} & HixboxDataConfig

export type VFX = EffectTypes.VFX
export type HitEffectContract = EffectTypes.HitEffectContract

export type hitDetection = {
	attackID: string,
	Attacker: Model,
	hitboxes: { HitboxConfig },
	VFXS: { VFX }?,
	lifetime: number?,
	delay_cb: ((any) -> any)?,
	delay_cb_number: number?,
}

export type AttackBaseAbilityConstructor = BaseAbilityConstructor & {
	attackType: string,
}

export type AttackBaseAbility = BaseAbility & weaponTypes.MeleeSpec &  {
	-- ===== Attack-specific state =====
	attackType: string,
	player: Player,
	special_attack: boolean?,

	attackId: string,

	-- ===== Overridden / new methods =====
	new: (constructor: AttackBaseAbilityConstructor) -> { self: AttackBaseAbility },

	_resolveWeaponGrip: (
		self: AttackBaseAbility,
		strategyName: string,
		methodName: string,
		model: Model
	) -> BasePart,

	_createScopedPromise: (self: AttackBaseAbility, detectionInfo: hitDetection) -> (any, any), -- Promise<any?>, Maid

	SetAttributes: (self: AttackBaseAbility) -> (),

	PromiseHit: (
		self: AttackBaseAbility,
		hitDetection: hitDetection,
		hitEffect: HitEffectContract,
		params: {
			after_hit: ((self: AttackBaseAbility, vfxs: { VFX }?) -> ())?,
			delay_cb_number: number?,
		}?
	) -> (),

	-- Override
	Execute: (
		self: AttackBaseAbility,
		params: {
			preAnimFx: ((self: AttackBaseAbility) -> ())?,
			get_anim_name: ((self: AttackBaseAbility) -> string)?,

			createHitboxes: (
				self: AttackBaseAbility
			) -> {
				hitboxes: any,
				hit_effect_data: HitEffectContract,
				vfxs: { VFX }?,
			},

			delay_cb: ((self: AttackBaseAbility, vfxs: { VFX }?) -> () -> ())?,
			delay_cb_number: number?,

			custom_anim: ((self: AttackBaseAbility) -> ())?,
		}
	) -> (),
	UnsetAttributes: (self: AttackBaseAbility) -> (),
}

export type AttackDistanceAbility = BaseAbility & {
	-- ===== Attack-specific state =====
	-- Narrow `weapon_stats` to the ranged shape so gun-only fields
	-- (spread, recoil, raysPerShot, ...) type-check on this subclass.
	weapon_stats: WeaponStatsRange,
	attackType: string,
	player: Player,
	special_attack: boolean?,
	attackId: string,
	weaponBinder: any,
	ammo: number,
	_lastShotTimestamp: number,
	_recoilRestoreCFrame: CFrame?,
	_recoilTimeoutThreshold: number,
	_recoilCooldownController: any,
	_recoilResetConnection: RBXScriptConnection?,
	preAnimFx: ((self: AttackDistanceAbility, params: any?) -> ())?,
	get_anim_name: ((self: AttackDistanceAbility) -> string)?,
	post_anim: ((self: AttackDistanceAbility) -> ())?,

	-- ===== Overridden / new methods =====
	new: (constructor: AttackBaseAbilityConstructor) -> { self: AttackDistanceAbility },
	SetAttributes: (self: AttackDistanceAbility) -> (),
	_validateShot: (self: AttackDistanceAbility, timestamp: number, origin: CFrame) -> boolean,
	_resolveWeaponGrip: (
		self: AttackDistanceAbility,
		strategyName: string,
		methodName: string,
		model: Model
	) -> BasePart,
	_isContinuousShot: (self: AttackDistanceAbility, timestamp: number) -> boolean,
	_scheduleRecoilReset: (self: AttackDistanceAbility) -> (),
	_restoreRecoil: (self: AttackDistanceAbility) -> (),

	-- Override
	Execute: (
		self: AttackDistanceAbility,
		params: {
			preAnimFx: ((self: AttackDistanceAbility) -> ())?,
			get_anim_name: ((self: AttackDistanceAbility) -> string)?,

			createHitboxes: (
				self: AttackDistanceAbility
			) -> {
				hitboxes: any,
				hit_effect_data: HitEffectContract,
				vfxs: { VFX }?,
			},

			delay_cb: ((self: AttackDistanceAbility, vfxs: { VFX }?) -> () -> ())?,
			delay_cb_number: number?,

			custom_anim: ((self: AttackDistanceAbility) -> ())?,
		}
	) -> (),
	UnsetAttributes: (self: AttackDistanceAbility) -> (),

	_shot: (self: AttackDistanceAbility) -> (),
	_getBinder: (self: AttackDistanceAbility) -> (),
}

export type AttackDistanceAbilityCLient = BaseAbility & {
	-- ===== Attack-specific state =====
	-- Narrow `weapon_stats` to the ranged shape so gun-only fields
	-- (spread, recoil, raysPerShot, ...) type-check on this subclass.
	weapon_stats: WeaponStatsRange,
	attackType: string,
	player: Player,
	special_attack: boolean?,
	attackId: string,
	weaponBinder: any,
	ammo: number,
	_playerMoved: boolean,
	_lastPlayerCFrame: CFrame,
	_currentTween: Tween?,
	_restoreRecoilTween: RBXScriptConnection?,
	_inputConnection: RBXScriptConnection?,
	_lastShotTimestamp: number,
	_recoilRestoreCFrame: CFrame?,
	_recoilTimeoutThreshold: number,
	_recoilCooldownController: any,
	_recoilResetConnection: RBXScriptConnection?,
	_movementBeganConnection: RBXScriptConnection?,
	_movementEndedConnection: RBXScriptConnection?,
	-- Active world-touch points used to pan the camera by hand (mobile). Keyed by
	-- InputObject; non-empty means the auto-aim lock should yield to the player.
	_dragTouches: { [InputObject]: boolean },
	_dragBeganConnection: RBXScriptConnection?,
	_dragEndedConnection: RBXScriptConnection?,
	attackRow: number,
	-- ===== Continuous-fire / auto-aim state (client) =====
	-- Firing runs while EITHER the shot button is held (`_fireButtonHeld`) OR the
	-- always-on auto-aim scan has a target locked (`_fireAimLocked`). `_firing`
	-- guards the single shared fire loop; `_aimAssistActive` mirrors the lock and
	-- is read by `_shot` to suppress recoil while the hard lock owns the camera.
	_fireButtonHeld: boolean,
	_fireAimLocked: boolean,
	_firing: boolean,
	_aimAssistActive: boolean,
	-- Injected methods --
	preAnimFx: ((self: AttackDistanceAbility, params: any?) -> ())?,
	get_anim_name: ((self: AttackDistanceAbility) -> string)?,
	post_anim: ((self: AttackDistanceAbility) -> ())?,
	-- ===== Overridden / new methods =====
	new: (constructor: AttackBaseAbilityConstructor) -> { self: AttackDistanceAbility },
	SetAttributes: (self: AttackDistanceAbility) -> (),
	_validateShot: (self: AttackDistanceAbility, timestamp: number, origin: CFrame) -> boolean,
	_resolveWeaponGrip: (
		self: AttackDistanceAbility,
		strategyName: string,
		methodName: string,
		model: Model
	) -> BasePart,
	_isContinuousShot: (self: AttackDistanceAbility, timestamp: number) -> boolean,
	_scheduleRecoilReset: (self: AttackDistanceAbility) -> (),
	_restoreRecoil: (self: AttackDistanceAbility) -> (),
	_createRecoilStrike: (self: AttackDistanceAbility) -> (),

	-- ===== Continuous-fire / auto-aim runtime (client) =====
	-- `Start` is cascaded from AbstractStrategy:Start on equip and stands up the
	-- always-on, throttled auto-aim scan. The scan (`_aimAssistTick`) drives the
	-- camera lock and, on assisted input, target acquisition starts continuous
	-- fire through the single shared loop (`_startContinuousFire`/`_updateFire`).
	-- `_setupContinuousFireObservable` wires the shot-button trigger.
	Start: (self: AttackDistanceAbility) -> (),
	_setupContinuousFireObservable: (self: AttackDistanceAbility) -> (),
	_hasManualCameraDrag: (self: AttackDistanceAbility) -> boolean,
	_aimAssistTick: (self: AttackDistanceAbility) -> (),
	_startContinuousFire: (self: AttackDistanceAbility) -> (),
	_updateFire: (self: AttackDistanceAbility) -> (),

	-- Override
	Execute: (self: AttackDistanceAbility) -> (),
	UnsetAttributes: (self: AttackDistanceAbility) -> (),

	_shot: (self: AttackDistanceAbility) -> (),
	_getBinder: (self: AttackDistanceAbility) -> (),
	recoil: (self: AttackDistanceAbility) -> (),
}

--?? DEFENSE ABILITY ??||

export type DefenseAbilityConstructor = BaseAbilityConstructor & {
	-- Optional priority used by weapon defense chains
	priority: number?,
}

export type DefenseAbility = BaseAbility & {
	-- ===== State =====
	isActive: boolean,
	priority: number?,
	new: (constructor: DefenseAbilityConstructor) -> { self: DefenseAbility },

	-- ===== Signals / Observables =====
	_activeSignal: any, -- Signal<boolean>

	-- Internal execution handler
	_process: any,

	-- ===== Observables =====

	-- Emits boolean values when defense active state changes
	ObserveActive: (self: DefenseAbility) -> any, -- Observable<boolean>

	-- Emits the DefenseAbility instance while active
	ObserveDefense: (self: DefenseAbility) -> any, -- Observable<DefenseAbility>

	-- ===== Lifecycle =====

	Activate: (self: DefenseAbility) -> (),
	Deactivate: (self: DefenseAbility) -> (),

	Stop: (self: DefenseAbility) -> (),
	Destroy: (self: DefenseAbility) -> (),

	-- ===== Core behavior =====

	SetAttributes: (self: DefenseAbility) -> (),

	Process: (self: DefenseAbility, context: any) -> (),

	-- Guard break logic
	_GuardBreak: (self: DefenseAbility) -> boolean?,

	-- Internal deactivation
	_deactivate: (self: DefenseAbility) -> (),

	-- ===== Override =====

	Execute: (
		self: DefenseAbility,
		params: {
			get_anim_name: (() -> string)?,

			-- Called during Execute, returns the defense processor
			_execute: (self: DefenseAbility) -> any,
		}
	) -> (),
	_additiona_deactivate: (self: DefenseAbility) -> (),
}

--?? MOVEMENT ABILITY ??||

export type MovementAbilityParams = {
    direction: "forward" | "backward",
    keyCode: Enum.KeyCode?,
    cancel: boolean?,
    dashName: string?,
}

return {}
