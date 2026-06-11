local Players = game:GetService("Players")

--[=[
	@function getCharacterActor

	Returns the Player owning `character`, or — for NPC characters — a
	Player-shaped stand-in. The shot pipeline (castRays,
	canPlayerDamageHumanoid, validateTag, findAimAssistTarget) only reads
	`.Character`, `.Team`, `.Neutral` (and `.UserId` for attack ids), so the
	stand-in lets an NPC reuse the whole player hit path without branching
	every call site on "is this a real player".

	`Neutral = true` means an NPC can damage anyone, mirroring the neutral
	player rules in canPlayerDamageHumanoid.
]=]

-- One stand-in per character; weak keys so despawned NPCs don't leak.
local actorCache = setmetatable({}, { __mode = "k" })

local function getCharacterActor(character: Model): Player
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return player
	end

	local actor = actorCache[character]
	if not actor then
		actor = {
			Character = character,
			Team = nil,
			Neutral = true,
			UserId = character.Name,
		}
		actorCache[character] = actor
	end

	return (actor :: any) :: Player
end

return getCharacterActor
