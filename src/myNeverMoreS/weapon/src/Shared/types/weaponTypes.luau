local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EffectTypes = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectTypes)
--== CLASSES ==--

export type ClientAbilityTable = { [string]: any }

export type WeaponStrategy = {
	character: Model,
	_serviceBag: any,
	weapon_name: string,
	weapon_stats: WeaponStatsBase,
	_maid: any,
	AbilityExecuted: any,
	attacks: ClientAbilityTable,
	skills: ClientAbilityTable,

	_createAbilities: (self: WeaponStrategy, attacks: ClientAbilityTable) -> ClientAbilityTable,
	Init: (self: WeaponStrategy) -> WeaponStrategy,
	createAbilitiesFromKey: (self: WeaponStrategy, key: string) -> ClientAbilityTable,
	-- May return a rejection reason (Constants.REJECT_REASON_*) — server-only
	-- signal consumed by AttckInvoker as cheat evidence; nil on success/client.
	Execute: (self: WeaponStrategy, action: any, params: any) -> string?,
	GetAction: (self: WeaponStrategy, action: string) -> any,
	GetStrategy: (self: WeaponStrategy) -> WeaponStrategy,
	Start: (self: WeaponStrategy) -> (),
	Destroy: (self: WeaponStrategy) -> (),
}

-- NEW ARGS
export type BaseAbilityConstructor = {
	keyCode: EnumItem?,
	key: { Name: string }?,
	animNames: { string }?,
	life_time: number?, -- This may be useful for not resolving the promise until the time us fulfil, meanwhile should live the hitbox effect (hitbox already live that long in the client, but the server resolve in the first target)
	type: string,
	cooldown: number?,
	attackType: string?,
	special_attack: boolean?,
}

--[=[
	Universal stats every weapon strategy must declare.

	@field damage -- base damage applied on a successful hit
	@field range -- effective reach: melee hitbox depth, ranged effective distance
	@field unanchoredImpulseForce -- knockback force applied to unanchored targets
	@field viewModel -- first-person view model name used by the FPS rig
]=]
export type WeaponStatsBase = {
	damage: number,
	criticalDamage : number,
	unanchoredImpulseForce: number,
	viewModel: string,
}

--[=[
	Extra stats required by ranged (gun) weapons on top of WeaponStatsBase.
	Consumed by RangeAttack / RangeAttackClient and the gun binders.
]=]
export type WeaponStatsRange = WeaponStatsBase & {
	_ammo: number,
	_reloading: boolean,
	range: number,

	aimAssistCenteringStrength: number,
	aimAssistFov: number,
	aimAssistFrictionStrength: number,
	aimAssistRange: number,
	aimAssistTrackingStrength: number,

	fireMode: string,
	magazineSize: number,
	maxDistance: number,

	bulletVelocity: number,
	rateOfFire: number,
	rayRadius: number,
	raysPerShot: number,

	recoilMax: Vector2,
	recoilMin: Vector2,
	recoilRise: number?,

	reloadTime: number,
	spread: number,
}

export type WeaponAbilitySpec = {
	config: BaseAbilityConstructor | AttackBaseAbilityConstructor | DefenseAbilityConstructor?,
	get_anim_name: ((ctx: BaseAbility) -> string)?,
	preAnimFx: ((ctx: BaseAbility) -> ())?,
	createHitboxes: any?,
	delay_cb: any?,
	delay_cb_number: number?,
	custom_init: any?,
	after_hit: any?,
	post_anim: ((ctx: BaseAbility) -> ())?,
	effect: ((ctx: BaseAbility) -> ())?,
	endFx: ((ctx: BaseAbility) -> ())?,
	set_attributes: ((ctx: BaseAbility) -> ())?,
	reset_attributes: ((ctx: BaseAbility) -> ())?,
	special_speed: number?,
}

export type MeleeSpec = {
	skills: { [string]: WeaponAbilitySpec },
	weapon_stats: WeaponStatsBase | WeaponStatsRange,
	attacks: { [string]: WeaponAbilitySpec },
	walk_speed_normal: number,
	walk_speed_blocking: number,
	walk_speed_counter: number,
	required_damage: number,
	getLeftGrip: (model: Model) -> BasePart?,
	getRightGrip: (model: Model) -> BasePart?,
	getHead: (model: Model) -> BasePart?,
	weapon_name: string?,
	gripC0: CFrame?,
	gripC1: CFrame?,
	centerAimToCamera: boolean?,

	-- Per-weapon equip hooks fired from `EquiTool` once the strategy is
	-- installed. Each may return a cleanup function that the context runs on
	-- swap / unequip / destroy (e.g. the grenade aimer's teardown). Both are
	-- optional and nil-safe; `onEquipCBClient` is the client side,
	-- `onEquipCB` the server side.
	onEquipCB: ((context: WeaponContextBase) -> (() -> ())?)?,
	onEquipCBClient: ((context: WeaponContextBase) -> (() -> ())?)?,
}

--[=[
	Base shape of the "Armed" binder bound to a character. Both the client
	(`WeaponClient`) and the server (`Weapon`) implement this surface so that
	`characterCtxUtils` can drive equip/unequip without branching on side.

	Side-specific fields (defense system, hitbox promise registry on the
	server; camera mediator on the client) live in the per-side extensions
	below, not here.
]=]
export type WeaponContextBase = {
	-- Properties
	Char: Model,
	_weapon: WeaponStrategy?,
	_serviceBag: any,
	Humanoid: Humanoid,
	tool_name: string?,
	_maid: any,
	-- Cleanup returned by the active weapon's onEquip hook, run on the next
	-- swap / unequip / destroy. nil when the current weapon has no hook.
	_onEquipCleanup: (() -> ())?,

	-- Shared methods (same signature on both client and server)
	Execute: (self: WeaponContextBase, action: any, params: any?) -> string?,
	GetStrategy: (self: WeaponContextBase) -> WeaponStrategy?,
	GetAction: (self: WeaponContextBase, action: any) -> any,
	EquiTool: (self: WeaponContextBase, toolName: string) -> (),
	UnequiTool: (self: WeaponContextBase) -> (),
	registryTool: (self: WeaponContextBase, toolName: string) -> (),
	Destroy: (self: WeaponContextBase) -> (),
}

--[=[
	Client-side weapon context. Adds the camera mediator (used to toggle
	first-person on aim) and `ToggleFirstPerson`, which only makes sense
	on the local player's machine.
]=]
export type WeaponContextClient = WeaponContextBase & {
	_cameraMediator: any,
	_tool: Tool?,
	_aimPosition: Attachment?,
	-- Cached "Right Arm" part and the server-created grip "Handle" Motor6D (+ its
	-- base C0/C1). The Handle only exists while a Tool is equipped, so all three
	-- are nil for Tool-less weapons (fist).
	_rigtArm: BasePart,
	_handle: Motor6D?,
	_handleC0Base: CFrame?,
	_handleC1Base: CFrame?,

	ToggleFirstPerson: (self: WeaponContextClient) -> (),
	GetAimPosition: (self: WeaponContextClient) -> Attachment?,
	GetTool: (self: WeaponContextClient) -> Tool?,
	GetHandle: (self: WeaponContextClient) -> (Motor6D?, CFrame?, CFrame?),
	GetCenterAimToCamera: (self: WeaponContextClient) -> boolean,
	GetGripC0: (self: WeaponContextClient) -> CFrame,
}

-- Kept as a back-compat alias so existing client call sites that still
-- import `weaponTypes.WeaponContext` resolve to the client shape.
export type WeaponContext = WeaponContextClient

export type BaseAbility = {
	-- Core state
	character: Model,
	humanoid: Humanoid,
	hrp: BasePart,

	type: "Attack" | "Defense" | "Others" | string,
	player: Player,

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
	_maid: any,

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

export type AttackBaseAbility = BaseAbility & {
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

--[=[
	Client-side melee ability. The server still owns the heavy work
	(animation, hitbox promise, damage application); this client class
	only validates local guards and fires the Swing remote so the server
	pipeline can run. The hitbox handshake then comes back via
	HitboxResponseRemote and is rendered by AttckInvockerClient.
]=]
export type AttackBaseClient = BaseAbility & {
	attackType: string,
	_keyCode: EnumItem?,

	new: (constructor: AttackBaseAbilityConstructor) -> AttackBaseClient,
	Execute: (self: AttackBaseClient, params: any) -> (),
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

export type MovementAbilitySpec = {
    get_anim_name: ((ctx: BaseAbility, params: MovementAbilityParams) -> string)?,
    effect: ((ctx: BaseAbility, params: MovementAbilityParams) -> ())?,
    endFx: ((ctx: BaseAbility) -> ())?,
    set_attributes: ((ctx: BaseAbility) -> ())?,
    reset_attributes: ((ctx: BaseAbility) -> ())?,
}

--?? RELOAD ABILITY ??||

--[=[
	Generic reload ability (`type = "Reload"`), one shared shape for the
	server refill (ReloadAbility) and the client request gate
	(ReloadAbilityClient). State lives on the Tool's `_ammo` / `_reloading`
	attributes, never on the instance, so both sides stay stateless.
]=]
export type ReloadAbility = BaseAbility & {
	_tool: Tool?,
	_keyCode: EnumItem?,
	weapon_stats: WeaponStatsRange,
	player: Player?,

	new: (constructor: BaseAbilityConstructor) -> ReloadAbility,
	Execute: (self: ReloadAbility, params: any?) -> (),
}

export type MovementAbility = BaseAbility & {
    player: Player,
    _lastAttackID: number,
    _isActive: boolean?,

    spec: MovementAbilitySpec,

    effect: ((self: MovementAbility, params: MovementAbilityParams) -> ())?,
    endFx: ((self: MovementAbility) -> ())?,
    get_anim_name: ((self: MovementAbility, params: MovementAbilityParams) -> string)?,

    new: (constructor: BaseAbilityConstructor) -> MovementAbility,
    Execute: (self: MovementAbility, params: MovementAbilityParams) -> (),
    SetAttributes: (self: MovementAbility) -> (),
}

return {}
