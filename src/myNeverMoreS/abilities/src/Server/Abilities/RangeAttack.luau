local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EffectService = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectService)
local EffectTypes = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectTypes)
local roll_vfx = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.roll_vfx)
local validateTag = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.validateTag)
local BaseAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Abilities.BaseAbility)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local castRays = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.castRays)
local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local getRayDirections = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getRayDirections)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Server.types.weaponTypes)
local testPart = require(ReplicatedStorage.Shared.test.testPart)

local AttackDistanceAbility = setmetatable({}, BaseAbility)
AttackDistanceAbility.__index = AttackDistanceAbility

function AttackDistanceAbility.new(config)
	local self = setmetatable(BaseAbility.new(config), AttackDistanceAbility)

	self._lastAttackID = 0
	-- Real Player when one owns the character; the Player-shaped stand-in for
	-- NPC weapons, so castRays/validateTag/_GenerateAttackID below keep working
	-- when AttckInvoker routes a client-driven NPC shot here.
	self.player = getCharacterActor(self.character)

	-- Seed the authoritative magazine on the Tool. The attribute (not
	-- weapon_stats, which every ability holds a private clone of) is the shared
	-- ammo store: the server writes it, it replicates to the client for free
	-- (RangeAttackClient dry-fire gate + the AmmoCounter UI both read it).
	-- Seeded here, not per strategy, so every gun gets it data-driven. nil-check
	-- so a respawned strategy on the same Tool keeps the partial magazine.
	if self._tool and self._tool:GetAttribute(Constants.AMMO_ATTRIBUTE) == nil then
		self._tool:SetAttribute(Constants.AMMO_ATTRIBUTE, self.weapon_stats.magazineSize)
	end

	return self
end

local THRESHOLD = 80 --in miliseconds

function AttackDistanceAbility._validateShot(
	self: weaponTypes.AttackBaseAbility,
	timestamp: number,
	origin: CFrame
): boolean
	-- Validate timestamp
	local now = Workspace:GetServerTimeNow()
	if timestamp > now then
		print("timestamp have passed")
		return false
	end

	local difference = now - timestamp
	if difference > THRESHOLD then
		print("timestamp have passed")
		return false
	end

	local distance = (self.hrp.Position - origin.Position).Magnitude
	local maxDistance = self.weapon_stats.maxDistance
	if distance > maxDistance then
		print("timestamp have passed")

		return false
	end

	return true
end

function AttackDistanceAbility._getBinder(self: weaponTypes.AttackDistanceAbility)
	if not self.weaponBinder then
		local BinderProviderInitialized = self._serviceBag:GetService(_G.BinderProvider)
		local WeaponBinderStarted = BinderProviderInitialized:Get("Armed")
		self.weaponBinder = WeaponBinderStarted
	end
	return self.weaponBinder
end

type tagged = {
	Humanoid: Humanoid,
	limb: BasePart,
}

function AttackDistanceAbility.Execute(
	self: weaponTypes.AttackDistanceAbility,
	params
)
	-- The reason string propagates up through WeaponBase:Execute ->
	-- Weapon.Execute so AttckInvoker can count CD-rejected NPC shots as
	-- fire-rate cheat evidence (a legit brain client paces on GetShootInterval
	-- and rarely lands here). Reload/empty returns below stay bare: the NPC
	-- brain dry-fires those legitimately, they are not evidence.
	if self:GetCD() then
		return Constants.REJECT_REASON_COOLDOWN
	end

	-- Ammo gate (authoritative). The client early-returns on empty too, but a
	-- hacked client firing the Swing remote with an empty/reloading magazine
	-- must land here and do nothing.
	local tool = self._tool
	if tool then
		if tool:GetAttribute(Constants.RELOADING_ATTRIBUTE) then
			return
		end
		local ammo = tool:GetAttribute(Constants.AMMO_ATTRIBUTE)
		if ammo ~= nil and ammo <= 0 then
			return
		end
	end

	-- start attack
	self:StartCD()

	self:_countAttack()
	local attackId = self:_GenerateAttackID()
	local origin = params.origin
	local timestamp = params.timestamp
	-- Validate that the player can make this shot
	if not self:_validateShot(timestamp, origin) then
		return
	end

	local spread = self.weapon_stats.spread
	local raysPerShot = self.weapon_stats.raysPerShot
	local range = self.weapon_stats.range
	local rayRadius = self.weapon_stats.rayRadius

	-- Subtract ammo from the live attribute (NOT weapon_stats._ammo, which is a
	-- static config value — reading it here would pin the count at magazine-1
	-- forever). Decremented only after the shot validated, so a rejected shot
	-- costs nothing.
	if tool then
		local ammo = tool:GetAttribute(Constants.AMMO_ATTRIBUTE)
		if ammo ~= nil then
			tool:SetAttribute(Constants.AMMO_ATTRIBUTE, math.max(ammo - 1, 0))
		end
	end

	-- The timestamp that was passed by the client also serves as the seed for the blaster's random spread.
	-- This allows us to recalculate the spread accurately on the server relative to the look direction, rather than simply
	-- accepting a direction or directions from the client.
	local spreadAngle = math.rad(spread)
	local rayDirections = getRayDirections(origin, raysPerShot, spreadAngle, timestamp)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end
	-- Raycast against static geometry only: every character part is tagged
	-- NonStatic, so this cast finds WALLS for validateTag's occlusion check —
	-- re-hitting the moving target is the client's job (latency would make the
	-- server miss), the claim is then validated by distance + angle.
	local rayResults = castRays({
		player = self.player,
		origin = origin.Position,
		directions = rayDirections,
		radius = rayRadius,
		staticOnly = true,
	})

	-- Validate hits
	for indexString, tagged in params.tagged do
		local taggedHumanoid = tagged.Humanoid
		-- The tagged table contains a client-reported list of the humanoids hit by each of the rays that was fired.
		-- Strings are used for the indices since non-contiguous arrays do not get passed over the network correctly.
		-- (This may be non-contiguous in the case of firing a shotgun, where not all of the rays hit a target)
		-- For each humanoid that the client reports it tagged, we'll validate against the ray that was recast on the server.
		local index = tonumber(indexString)
		if not index then
			continue
		end
		local rayResult = rayResults[index]
		if not rayResults[index] then
			continue
		end
		local rayDirection = rayDirections[index]
		if not rayDirection then
			continue
		end

		-- Validate that the player is able to tag this humanoid based on the server raycast
		if not validateTag(self.player, taggedHumanoid, origin.Position, rayDirection, rayResult) then
			continue
		end

		rayResult.taggedHumanoid = taggedHumanoid

		-- Align the rayResult position to the tagged humanoid. This is necessary so that when we replicate
		-- this shot to the other clients they don't see lasers going through characters they should be hitting.
		local model = taggedHumanoid:FindFirstAncestorOfClass("Model")
		if model then
			local modelPosition = model:GetPivot().Position
			local distance = (modelPosition - origin.Position).Magnitude
			rayResult.position = origin.Position + rayDirection.Unit * distance
		end

		if taggedHumanoid.Health <= 0 then
			continue
		end

		local char: Model = self.character
		local attacker: EffectTypes.effectHumanoid = {
			Character = char,
			HRP = self.hrp,
			Humanoid = self.humanoid,
		}
		local Defender: EffectTypes.effectHumanoid = {
			Character = model,
			HRP = model.PrimaryPart,
			Humanoid = taggedHumanoid,
		}

		local isHead = tagged.limb
			and tagged.limb.Name == "Head"
			and (rayResult.position - tagged.limb.Position).Magnitude < 2
		local damage = isHead and self.weapon_stats.criticalDamage or self.weapon_stats.damage
		local WeaponBinderStarted = self:_getBinder()
		local weapon = WeaponBinderStarted:Get(model)
		if not weapon then
			local fullContext = {
				damage = damage,
				Attacker = attacker,
				Defender = Defender,
				attackId = attackId,
				serviceBag = self._serviceBag,
			} :: EffectTypes.effectHitCtx
			EffectService:Apply(fullContext)
		else
			weapon:OnIncomingAttack({
				damage = damage,
				Attacker = attacker,
				Defender = Defender,
				attackId = attackId,
				serviceBag = self._serviceBag,
			})

		end
		roll_vfx({
			src = self._tool,
			rayResults = rayResults,
		})
	end
end

return AttackDistanceAbility
