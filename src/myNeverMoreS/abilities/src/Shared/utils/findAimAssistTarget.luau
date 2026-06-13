local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RayCaster = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.RayCaster)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)

--[=[
	@function findAimAssistTarget

	Picks the best auto-aim target for `player` from the camera's point of view.

	A single raycast only catches whatever sits dead-centre, so instead we
	enumerate every *valid* humanoid (other players + NPC-tagged characters),
	keep the ones inside a forward cone (`fovDeg`) and within `range` that also
	have a clear line of sight, and return the **most centred** one's
	HumanoidRootPart. `canPlayerDamageHumanoid` is the validity gate (dead /
	same-team targets are skipped), matching the bullet-hit path in `castRays`.

	Returns the target's root part, or nil when nothing qualifies.
]=]
local function collectCandidateCharacters(): { Model }
	-- For testing purposes use all the characters tagget in Armed
	return CollectionService:GetTagged("Armed")
end

local function hasLineOfSight(caster: RayCaster.RayCaster, origin: Vector3, target: Model): boolean
	-- Line of sight is "can a thin line reach ANY part of the target". We aim one
	-- thin ray straight at each of the target's body parts rather than a random
	-- forward cone, because each earlier approach got it wrong in opposite ways:
	--   * A single dead-centre ray is too tight — a sliver of geometry grazing the
	--     centre line rejects a target that's plainly visible.
	--   * A wide spherecast (the bullet's magnetism radius) is too FAT for a LoS
	--     test — it can't fit through a window/doorway the target is visible
	--     through, so it snags the frame and reports no sight (the cabin bug).
	-- Thin per-part rays thread the opening AND cover the whole body, so if the
	-- head is visible through a slot while the torso is behind cover, the head ray
	-- still proves sight. Each direction's magnitude is the exact distance to that
	-- part, so the probe stops at the part. `castRays` excludes the RayExclude tag
	-- + the shooter and gates on `canPlayerDamageHumanoid`, so a returned
	-- `taggedHumanoid` is a hittable body — we just confirm it's ours.
	local directions: { Vector3 } = {}
	for _, part in target:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(directions, part.Position - origin)
		end
	end
	if #directions == 0 then
		return false
	end

	local rayResults = caster:Cast(origin, directions, Constants.AIM_ASSIST_RAY_RADIUS)
	for _, rayResult in rayResults do
		if rayResult.taggedHumanoid then
			return true
		end
	end
	return false
end

local function findAimAssistTarget(
	player: Player,
	camera: Camera,
	range: number,
	fovDeg: number,
	filter: ((character: Model) -> boolean)?
): BasePart?
	local cameraCFrame = camera.CFrame
	local cameraPosition = cameraCFrame.Position
	local lookDirection = cameraCFrame.LookVector
	local cosThreshold = math.cos(math.rad(fovDeg))

	-- One caster for the whole scan: the attacker (player) and exclude list are
	-- constant across every candidate, so resolving the attacker team + building
	-- RaycastParams once (instead of once per candidate) is the aim-assist win.
	local caster = RayCaster.new(player)

	-- Anchor for the "behind the player's back" reject below. The hard lock is a
	-- mask on the CAMERA, and a locked camera always points straight at its
	-- target, so the forward cone (measured from `cameraCFrame`) keeps passing no
	-- matter where the target moves -- without an extra guard the lock would swing
	-- the third-person camera a full 180° to follow a target that circled in
	-- behind the player. We test "behind" against the CHARACTER's facing, which
	-- the camera lock never rotates, so the test stays valid while locked.
	local playerCharacter = player.Character
	local playerRoot = playerCharacter and playerCharacter.PrimaryPart

	local bestRootPart: BasePart? = nil
	local bestScore = cosThreshold

	for _, character in collectCandidateCharacters() do
		-- Never target ourselves (the testing source GetTagged("Armed") includes
		-- the local character).
		if character == player.Character then
			continue
		end

		-- Optional caller gate (e.g. NPC vision only hunts real players, never
		-- the other "Armed"-tagged NPCs in the candidate pool).
		if filter and not filter(character) then
			continue
		end

		local rootPart = character.PrimaryPart
		if not rootPart then
			continue
		end

		-- Drop a target that has gotten in close behind the player's back: you
		-- can't auto-aim it without flipping the whole third-person view around,
		-- and the camera-anchored cone above can't catch it (see playerRoot note).
		-- Only the close back hemisphere is rejected -- a target in front stays
		-- lockable at any distance (point-blank front fire still assists).
		if playerRoot then
			local toTargetFromPlayer = rootPart.Position - playerRoot.Position
			local isBehindPlayer = playerRoot.CFrame.LookVector:Dot(toTargetFromPlayer) < 0
			if isBehindPlayer then
				continue
			end
		end

		local toTarget = rootPart.Position - cameraPosition
		local distance = toTarget.Magnitude
		if distance > range or distance <= 0 then
			if character.Name == "Target" then
				print("distance")
			end
			continue
		end

		-- Cone test: dot of the (unit) direction with the camera look vector.
		-- Higher = more centred; anything below the cone threshold (or behind
		-- the camera) is rejected.
		local score = lookDirection:Dot(toTarget / distance)
		if score <= bestScore then
			if character.Name == "Target" then
				print("score")
			end
			continue
		end

		if not hasLineOfSight(caster, cameraPosition, character) then
			if character.Name == "Target" then
				print("hasLineOfSight")
			end
			continue
		end

		bestScore = score
		bestRootPart = character:FindFirstChild("Target") or rootPart
	end
	return bestRootPart
end

return findAimAssistTarget
