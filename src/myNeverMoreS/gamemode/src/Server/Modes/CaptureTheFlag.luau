--[=[
	@class CaptureTheFlag
	The "ctf" strategy: two teams, each defends one flag (a BasePart tagged
	CTF_FLAG_TAG carrying its team's TEAM_ATTRIBUTE) and owns one capture zone (a
	BasePart tagged CTF_HOME_ZONE_TAG with the same TEAM_ATTRIBUTE). A team scores
	CTF_POINTS_PER_CAPTURE by carrying the ENEMY flag into its own home zone while
	its own flag sits at base. First team to the cap (3 captures) or the leader at
	time-up wins — GameModeService owns that check.

	The grab + carrier lifecycle is NOT this class's job: that lives in the Flag
	binder (server), which owns the ProximityPrompt, the server-validated grab
	(distance / team / one-flag-per-carrier), the authoritative CTF_CARRIER_TAG,
	and the return-to-base on the carrier's death. So the requirements that live
	in the binder, not here:
	  * "flag cannot be captured while already captured" — Flag._onTriggered
	    early-returns on a non-nil carrier;
	  * "carrier dies => no point, flag returns" — Flag's Died/AncestryChanged
	    watch calls ReturnToBase, dropping the carrier tag before this tick sees it.

	This class only: discovers flags + home zones at Start, enables the flags,
	and runs a Heartbeat tick that detects a carrier standing in its own home zone
	(ZoneController, sibling of NpcController/KOTH) and turns that into a score +
	a flag reset. It extends TeamMode for the team-vs-team roster + balanced
	assignment, like KingOfTheHill.

	A misconfigured map (no tagged flags / zones) still runs — bots, teams,
	respawns — but never scores: a loud warn, not a crash, so it's obvious in a
	playtest.
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local TeamMode = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.TeamMode)
local ZoneController = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.ZoneController)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)
local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)

local CaptureTheFlag = setmetatable({}, { __index = TeamMode })
CaptureTheFlag.__index = CaptureTheFlag

function CaptureTheFlag.new(config: gameModeTypes.ModeConfig)
	local self = setmetatable(TeamMode.new(config) :: any, CaptureTheFlag)

	-- Long-lived Flag binder instances (one per tagged flag part), captured at
	-- Start. NOT maid-owned: the binders outlive the match (tags are authored in
	-- the map), so Stop only disables them, never destroys them.
	self._flags = {} :: { any }
	-- TeamId -> ZoneController for that team's home capture zone. Maid-owned:
	-- TeamMode.Stop's DoCleaning destroys them.
	self._zones = {} :: { [gameModeTypes.TeamId]: ZoneController.ZoneController }
	self._accum = 0 -- Heartbeat accumulator toward the next capture tick

	return self
end

-- The Flag binder instances for every BasePart tagged CTF_FLAG_TAG. Read once at
-- Start through the standard binder-provider path (set well before a match
-- latches; see GameModeService).
function CaptureTheFlag._collectFlags(_self): { any }
	local provider = _G.BinderProvider
	local binder = provider and provider:Get(GameModeConstants.CTF_FLAG_TAG)
	return if binder then binder:GetAll() else {}
end

-- The flag DEFENDED by `teamId` (so we can require it be at base before scoring).
function CaptureTheFlag._flagForTeam(self, teamId: gameModeTypes.TeamId): any
	for _, flag in self._flags do
		if flag:GetTeam() == teamId then
			return flag
		end
	end
	return nil
end

-- The flag `character` is currently carrying (the enemy flag it stole), if any.
function CaptureTheFlag._flagHeldBy(self, character: Model): any
	for _, flag in self._flags do
		if flag:GetCarrier() == character then
			return flag
		end
	end
	return nil
end

-- Build a ZoneController for each team's home zone: the first BasePart tagged
-- CTF_HOME_ZONE_TAG whose TEAM_ATTRIBUTE matches the team id.
function CaptureTheFlag._buildZones(self)
	local byTeam: { [gameModeTypes.TeamId]: BasePart } = {}
	for _, inst in CollectionService:GetTagged(GameModeConstants.CTF_HOME_ZONE_TAG) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
			local teamId = inst:GetAttribute(GameModeConstants.TEAM_ATTRIBUTE)
			if typeof(teamId) == "string" and not byTeam[teamId] then
				byTeam[teamId] = inst
			end
		end
	end

	for teamId, part in byTeam do
		self._zones[teamId] = self._maid:Add(ZoneController.new(part, GameModeConstants.CTF_SCAN_INTERVAL))
	end
end

-- One scoring pass: a carrier standing in its OWN home zone, holding the enemy
-- flag, with its own flag at base => one capture. Returning the stolen flag is
-- what makes the capture "consume" it (the carrier tag clears, so it can't
-- re-score on the next tick).
function CaptureTheFlag._tickCaptures(self)
	if not self._deps then
		return
	end

	for teamId, zone in self._zones do
		for _, carrier in zone:GetTaggedOccupants(GameModeConstants.CTF_CARRIER_TAG) do
			-- Must be that team's OWN member standing in their OWN home zone.
			local carrierTeam = resolveTeam(carrier, getCharacterActor(carrier))
			if not carrierTeam or carrierTeam.Name ~= teamId then
				continue
			end

			-- Classic CTF: a team may only score while its own flag sits at base.
			local ownFlag = self:_flagForTeam(teamId)
			if ownFlag and not ownFlag:IsAtBase() then
				continue
			end

			local heldFlag = self:_flagHeldBy(carrier)
			if not heldFlag then
				continue
			end

			self._deps.addScore(teamId, GameModeConstants.CTF_POINTS_PER_CAPTURE)
			-- Send the stolen flag home; this also untags the carrier.
			heldFlag:ReturnToBase()
		end
	end
end

function CaptureTheFlag.Start(self, payload: gameModeTypes.MatchPayload)
	-- Roster + balanced team assignment first (TeamMode owns the bots).
	TeamMode.Start(self, payload)

	self._flags = self:_collectFlags()
	for _, flag in self._flags do
		flag:SetEnabled(true)
	end
	if #self._flags == 0 then
		warn(`[CaptureTheFlag] no BasePart tagged "{GameModeConstants.CTF_FLAG_TAG}" — captures will never score`)
	end

	self:_buildZones()
	if not next(self._zones) then
		warn(`[CaptureTheFlag] no BasePart tagged "{GameModeConstants.CTF_HOME_ZONE_TAG}" — captures will never score`)
	end

	self._maid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime)
		self._accum += deltaTime
		if self._accum < GameModeConstants.CTF_TICK_INTERVAL then
			return
		end
		self._accum -= GameModeConstants.CTF_TICK_INTERVAL
		self:_tickCaptures()
	end))
end

function CaptureTheFlag.Stop(self)
	-- Disable flags first (returns any held flag, kills the prompt) — they
	-- outlive the match, so Stop must clean them by hand; the zones go down with
	-- TeamMode.Stop's DoCleaning.
	for _, flag in self._flags do
		flag:SetEnabled(false)
	end
	self._flags = {}
	TeamMode.Stop(self)
end

return CaptureTheFlag
