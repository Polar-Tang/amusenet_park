export type VFX = {
	Attacker: Instance,
	action: string,
	dashDir: Vector3?,
	camYaw: number?,
	animName: string?,
	Pos: Vector3?,
	attackId: number?,
	destroy: boolean?,
	CF: CFrame?,
	life_time: number?,
	dir: Vector3?,
	camera_location: Vector3?,
	src: BasePart?,
	src2: BasePart?,
	Size: Vector3?,
	Size2: Vector3?,
	src_model: Model?,
	src_model2: Model?,
	scaleTo: number?,
}

export type GroundSmash = {
	position: Vector3?,
	amount: number?,
	velocity: number?,
	material: EnumItem?,
	dust: boolean?,
	shockwave: boolean?,
	sizeRange: Vector2?,
	lifetime: number?,
}

export type hardLock = {
	lifetime: number,
	destroy: boolean?,
	part1: BasePart?,
	direction: Vector3?,
}

export type comeBabe = {
	lifetime: number,
	destroy: boolean?,
	part1: BasePart?,
}

export type dashing = {
	destroy: boolean?,
	direction: Vector3?,
	lifetime: number?,
}

export type hitLock = {
	position: Vector3?,
	duration: number?,
	offset: number?,
	direction: Vector3?,
}

export type HitEffectContract = {
	attackId: string,
	attacker: Model,
	groundSmash: GroundSmash?,
	strength: number?,
	damage: number?,
	knockback: Vector3?,
	stunt_time: number?,
	ragdoll: {
		isRag: boolean,
		duration: number,
	}?,
	hit_position: Vector3?,
	Explosion: {}?,
	HitPart: BasePart?,
	strikes_hit: boolean?,
	hitPart: BasePart?,
	hitLock: hitLock?,
	dashing: dashing?,
	hardLock: hardLock?,
	countDamage: (number) -> ()?,
	VFX: { VFX }?,
	comeBabe: comeBabe?,
	post_hit: ((ctx: any) -> ())?,
	pre_hit: ((ctx: any) -> ())?,
	cutscene: {
		duration: number?,
		create_point: (Camera) -> CFrame,
		camera_location: Vector3,
		look_to: Vector3?,
		destroy: boolean?,
	}?,
}

export type HitEffectContractTemplate = HitEffectContract & {
	serviceBag: any,
	anchorState: any?,
	attacker: Model,
}

export type effectHumanoid = {
	Character: Model,
	Humanoid: Humanoid,
	HRP: BasePart,
}

export type effectHitCtx = HitEffectContractTemplate & {
	Defender: effectHumanoid,
	Attacker: effectHumanoid,
}
return {}
