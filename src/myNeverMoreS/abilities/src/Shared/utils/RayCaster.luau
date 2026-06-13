--[=[
	@class RayCaster

	A per-shot / per-scan hit-casting context. Everything that used to be
	recomputed on every single ray is resolved ONCE here:

	  * the attacker's team (`resolveTeam` of the actor) — the attacker never
	    changes across a shot or a vision scan, only the defender does;
	  * the `RaycastParams` + exclude list (RayExclude tag, optionally NonStatic
	    for static-only casts, plus the actor's own character).

	`:Cast(origin, directions, radius)` then reuses both for every ray and uses
	the allocation-free [[resolveHitParts]] + [[isDamageableByTeam]] gate per hit.

	This is the fix for the aim-assist hot path: `findAimAssistTarget` builds one
	RayCaster per scan and reuses it across every candidate, instead of rebuilding
	the params / re-resolving the attacker team once per candidate.

	`actor` is a real `Player` or a `getCharacterActor` fake (NPC rigs) — only
	`.Character` is read here.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local resolveHitParts = require(script.Parent.resolveHitParts)
local isDamageableByTeam = require(script.Parent.isDamageableByTeam)

export type RayResult = {
	taggedHumanoid: Humanoid?,
	position: Vector3,
	normal: Vector3,
	instance: Instance?,
	limb: BasePart?,
}

export type RayCaster = {
	_attackerTeam: Team?,
	_params: RaycastParams,
	Cast: (self: RayCaster, origin: Vector3, directions: { Vector3 }, radius: number) -> { RayResult },
}

local RayCaster = {}
RayCaster.__index = RayCaster

function RayCaster.new(actor: Player, staticOnly: boolean?): RayCaster
	local self = setmetatable({}, RayCaster)

	-- Resolve the attacker team once; the per-ray gate only pays the defender lookup.
	self._attackerTeam = resolveTeam(actor.Character, actor)

	-- Build the exclude list + RaycastParams once and reuse for every Cast.
	local exclude = CollectionService:GetTagged(Constants.RAY_EXCLUDE_TAG)
	if staticOnly then
		local nonStatic = CollectionService:GetTagged(Constants.NON_STATIC_TAG)
		table.move(nonStatic, 1, #nonStatic, #exclude + 1, exclude)
	end

	-- Never let a shot hit the actor's own character.
	if actor.Character then
		table.insert(exclude, actor.Character)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = exclude
	self._params = params

	return (self :: any) :: RayCaster
end

function RayCaster.Cast(self: RayCaster, origin: Vector3, directions: { Vector3 }, radius: number): { RayResult }
	local params = self._params
	local attackerTeam = self._attackerTeam
	local rayResults = {}

	for _, direction in directions do
		-- Spherecast (small radius) instead of a raycast gives a little bullet
		-- magnetism: closely grazing shots register, improving 'game feel'.
		local raycastResult = Workspace:Spherecast(origin, radius, direction, params)
		local rayResult: RayResult = {
			position = origin + direction,
			normal = direction.Unit,
		}

		if raycastResult then
			rayResult.position = raycastResult.Position
			rayResult.normal = raycastResult.Normal
			rayResult.instance = raycastResult.Instance

			local humanoid, limb = resolveHitParts(raycastResult.Instance)
			if humanoid and isDamageableByTeam(attackerTeam, humanoid) then
				rayResult.taggedHumanoid = humanoid
				rayResult.limb = limb
			end
		end

		table.insert(rayResults, rayResult)
	end

	return rayResults
end

return RayCaster
