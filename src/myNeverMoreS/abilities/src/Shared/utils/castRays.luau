local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local getPartHitInfo = require(script.Parent.getPartHitInfo)
local canPlayerDamageHumanoid =
	require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.canPlayerDamageHumanoid)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)

export type RayResult = {
	taggedHumanoid: Humanoid?,
	position: Vector3,
	normal: Vector3,
	instance: Instance?,
	limb: BasePart?,
}
export type castRayParams = {
	player: Player,
	origin: Vector3,
	directions: { Vector3 },
	radius: number,
	staticOnly: boolean?
}
local function castRays(
	castRayParams: castRayParams
): { RayResult }
	local exclude = CollectionService:GetTagged(Constants.RAY_EXCLUDE_TAG)
	if castRayParams.staticOnly then
		local nonStatic = CollectionService:GetTagged(Constants.NON_STATIC_TAG)
		
		-- Append nonStatic to exclude
		table.move(nonStatic, 1, #nonStatic, #exclude + 1, exclude)
	end

	-- Always include the player's character in the exclude list
	if castRayParams.player.Character then
		table.insert(exclude, castRayParams.player.Character)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = exclude

	local rayResults = {}

	for _, direction in castRayParams.directions do
		-- In order to provide a simple form of bullet magnetism, we use spherecasts with a small radius instead of raycasts.
		-- This allows closely grazing shots to register as hits, making blasters feel a bit more accurate and improving the 'game feel'.
		local raycastResult = Workspace:Spherecast(castRayParams.origin, castRayParams.radius, direction, params)
		local rayResult: RayResult = {
			position = castRayParams.origin + direction,
			normal = direction.Unit,
		}

		if raycastResult then
			rayResult.position = raycastResult.Position
			rayResult.normal = raycastResult.Normal
			rayResult.instance = raycastResult.Instance
			local hitShitData = getPartHitInfo.new(raycastResult.Instance)
			hitShitData:init()
			local humanoid = hitShitData:findParentHumanoid()
			local limb = hitShitData:findLimb()
			if humanoid and canPlayerDamageHumanoid(castRayParams.player, humanoid) then
				rayResult.taggedHumanoid = humanoid
				rayResult.limb = limb
			end
			hitShitData:Destroy()
		end

		table.insert(rayResults, rayResult)
	end

	return rayResults
end

return castRays
