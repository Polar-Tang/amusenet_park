--[=[
	@function isDamageableByTeam

	The friendly-fire gate with the attacker's team already resolved by the
	caller. Splitting this out of `canPlayerDamageHumanoid` lets a per-shot /
	per-scan caster (`RayCaster`) resolve the attacker team ONCE and pay only the
	defender lookup per ray, instead of re-resolving the (unchanging) attacker on
	every single ray.

	`attackerTeam` is the result of `resolveTeam(attacker.Character, attacker)`.
	A `nil` attacker team means "teamless" → allow damage, exactly the
	pre-gamemode neutral behavior. See [[canPlayerDamageHumanoid]] for the
	per-call public wrapper.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)

local function isDamageableByTeam(attackerTeam: Team?, taggedHumanoid: Humanoid): boolean
	-- Dead targets take no more damage.
	if not taggedHumanoid:IsA("Humanoid") or taggedHumanoid.Health <= 0 then
		return false
	end

	-- Teamless attacker (neutral player, dummy, pre-match) damages anyone.
	if not attackerTeam then
		return true
	end

	local taggedCharacter = taggedHumanoid.Parent :: Model?
	local defenderTeam = resolveTeam(taggedCharacter, Players:GetPlayerFromCharacter(taggedCharacter))

	-- Teamless defender is always damageable; otherwise only across teams.
	if not defenderTeam then
		return true
	end

	return attackerTeam ~= defenderTeam
end

return isDamageableByTeam
