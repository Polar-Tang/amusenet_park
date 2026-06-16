--[=[
	@class CarrierClient
	Client-side wrapper for a flag carrier. A binder over every character tagged
	`CTF_CARRIER_TAG` — the tag the Flag binder authors on the server, replicated
	to every client for free.

	This is the "don't duplicate observed data" half of the carry visuals: the
	carrier identity is ALREADY replicated through the CollectionService tag, so
	the client observes the tag through this binder instead of listening on a
	dedicated remote that would re-send the same fact. FlagBillboard (overhead
	marker for every carrier) and GroundPath (navigation arrows for the local
	carrier) both drive off this binder's class-added / class-removing signals.

	The class is intentionally thin — it owns no connections, so the binder's
	automatic untag cleanup is all the teardown it needs. It only resolves the
	per-carrier data the consumers want: the carrier itself and, for navigation,
	the home zone this carrier must reach to score.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)

local CarrierClient = {}
CarrierClient.__index = CarrierClient

export type CarrierClient = typeof(setmetatable(
	{} :: {
		_character: Model,
		_team: Team?,
		_goal: BasePart?,
	},
	CarrierClient
))

-- Client binder ctor signature is `(inst, serviceBag, ...)` (see ServiceRoot's
-- BinderProvider wiring); this class needs none of the extra args.
function CarrierClient.new(character: Model, _serviceBag: any?): CarrierClient
	local self = setmetatable({}, CarrierClient)

	self._character = character
	self._team = nil :: Team?
	self._goal = nil :: BasePart?

	return self
end

function CarrierClient.GetCharacter(self: CarrierClient): Model
	return self._character
end

--[=[
	The carrier's own team, by the one rule the whole combat/mode stack shares
	(resolveTeam). Cached: a carrier's team can't change mid-carry. Returns nil
	for a teamless carrier — consumers fall back to a neutral colour / icon.
]=]
function CarrierClient.GetTeam(self: CarrierClient): Team?
	if self._team then
		return self._team
	end
	self._team = resolveTeam(self._character, getCharacterActor(self._character))
	return self._team
end

--[=[
	The capture zone this carrier must reach: the BasePart tagged
	CTF_HOME_ZONE_TAG carrying this carrier's OWN team (classic CTF — bring the
	stolen enemy flag to your own base). Home zones are map-authored and static,
	so the result is cached after the first resolve. Returns nil for a teamless
	carrier or a map with no matching home zone (a misconfigured map, not a crash).
]=]
function CarrierClient.GetGoal(self: CarrierClient): BasePart?
	if self._goal then
		return self._goal
	end

	local team = self:GetTeam()
	if not team then
		return nil
	end

	for _, inst in CollectionService:GetTagged(GameModeConstants.CTF_HOME_ZONE_TAG) do
		if inst:IsA("BasePart") and inst:GetAttribute(GameModeConstants.TEAM_ATTRIBUTE) == team.Name then
			self._goal = inst
			return inst
		end
	end

	return nil
end

return CarrierClient
