--[=[
	@function castRays

	Back-compat single-shot wrapper around [[RayCaster]]: builds a caster (which
	resolves the attacker team + RaycastParams once) and casts the directions in
	one go. Use this for one-off casts (a single shot). For repeated casts that
	share the same actor — e.g. the aim-assist scan over many candidates — build a
	[[RayCaster]] yourself and reuse it instead of paying the per-call setup.
]=]

local RayCaster = require(script.Parent.RayCaster)

export type RayResult = RayCaster.RayResult
export type castRayParams = {
	player: Player,
	origin: Vector3,
	directions: { Vector3 },
	radius: number,
	staticOnly: boolean?,
}

local function castRays(castRayParams: castRayParams): { RayResult }
	local caster = RayCaster.new(castRayParams.player, castRayParams.staticOnly)
	return caster:Cast(castRayParams.origin, castRayParams.directions, castRayParams.radius)
end

return castRays
