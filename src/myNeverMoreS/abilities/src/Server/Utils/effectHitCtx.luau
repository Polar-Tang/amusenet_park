export type effectHitCtx = {
	Defender: {
		Character: Model,
		Humanoid: Humanoid,
		HRP: BasePart
	},
	Attacker: {
		Character: Model,
		Humanoid: Humanoid,
		HRP: BasePart
	},
	GroundSmash: {
		position: Vector3,
		amount : number,
		velocity : number,
		material : EnumItem,
		dust : boolean ,
		shockwave : boolean,
		sizeRange : Vector2,
		lifetime : number,
	},
	strength: number,
	damage: number,
	kockback: Vector3,
	stunt_time: number,
	_serviceBag: any
}

return {}