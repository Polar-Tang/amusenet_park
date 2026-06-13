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

export type CaptureTheFlag = typeof(setmetatable(
	{} :: {
		_flags: { any }, -- Flag binder instances, one per tagged flag part
		_zones: { [gameModeTypes.TeamId]: ZoneController.ZoneController }, -- per-team home zone
		_accum: number, -- Heartbeat accumulator toward the next capture tick
	},
	CaptureTheFlag
)) & TeamMode.TeamMode

function CaptureTheFlag.new(config: gameModeTypes.ModeConfig): CaptureTheFlag
	local self = setmetatable(TeamMode.new(config) :: any, CaptureTheFlag)

	-- Long-lived Flag binder instances (one per tagged flag part), captured at
	-- Start. NOT maid-owned: the binders outlive the match (tags are authored in
	-- the map), so Stop only disables them, never destroys them.
	self._flags = {} :: { any }
	-- TeamId -> ZoneController for that team's home capture zone. Maid-owned:
	-- TeamMode.Stop's DoCleaning destroys them.
	self._zones = {} :: { [gameModeTypes.TeamId]: ZoneController.ZoneController }
	self._accum = 0 -- Heartbeat accumulator toward the next capture tick

	return self :: CaptureTheFlag
end

-- The Flag binder for CTF_FLAG_TAG (or nil if the bag/provider isn't up yet).
-- `_G.BinderProvider` is the service KEY, not the started provider — the running
-- instance (whose binders have started) comes from `serviceBag:GetService` on it
-- (same pattern as ServiceRoot). The bag is handed to us at Init via deps. The
-- flags themselves are authored in the map and instantiated by the binder; we
-- never build them here, only observe them through this.
function CaptureTheFlag._getFlagBinder(self: CaptureTheFlag): any
	local serviceBag = self._deps and self._deps.serviceBag
	if not serviceBag or not _G.BinderProvider then
		return nil
	end
	local provider = serviceBag:GetService(_G.BinderProvider)
	if not provider then
		return nil
	end
	-- CTF_FLAG_TAG is registered in ServiceRoot's Binders table, so once the
	-- provider is up the binder MUST exist — a nil is a wiring bug (unregistered
	-- tag), distinct from "the map authored no flag parts" (tolerated below).
	local binder = provider:Get(GameModeConstants.CTF_FLAG_TAG)
	assert(binder, `[CaptureTheFlag] no binder registered for tag "{GameModeConstants.CTF_FLAG_TAG}" — register it in ServiceRoot's Binders table`)
	return binder
end

-- A flag bound (now via the GetAll sweep, or later via the class-added signal —
-- including a re-tag after destroy). Enable it and remember it. Idempotent: the
-- sweep and the signal can both reach a flag that was already bound at Start.
function CaptureTheFlag._onFlagBound(self: CaptureTheFlag, flag: any)
	if table.find(self._flags, flag) then
		return
	end
	table.insert(self._flags, flag)
	-- Safe here: Binder._add fires GetClassAddedSignal AFTER Flag.new built the
	-- ProximityPrompt, so SetEnabled always finds a live prompt.
	flag:SetEnabled(true)
end

-- A flag unbound (untagged/destroyed). Drop it so a re-tag rebinds cleanly; the
-- replacement re-enters _onFlagBound through the class-added signal.
function CaptureTheFlag._onFlagUnbound(self: CaptureTheFlag, flag: any)
	local index = table.find(self._flags, flag)
	if index then
		table.remove(self._flags, index)
	end
end

-- The flag DEFENDED by `teamId` (so we can require it be at base before scoring).
function CaptureTheFlag._flagForTeam(self: CaptureTheFlag, teamId: gameModeTypes.TeamId): any
	for _, flag in self._flags do
		if flag:GetTeam() == teamId then
			return flag
		end
	end
	return nil
end

-- The flag `character` is currently carrying (the enemy flag it stole), if any.
function CaptureTheFlag._flagHeldBy(self: CaptureTheFlag, character: Model): any
	for _, flag in self._flags do
		if flag:GetCarrier() == character then
			return flag
		end
	end
	return nil
end

-- Build a ZoneController for each team's home zone: the first BasePart tagged
-- CTF_HOME_ZONE_TAG whose TEAM_ATTRIBUTE matches the team id.
function CaptureTheFlag._buildZones(self: CaptureTheFlag)
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
function CaptureTheFlag._tickCaptures(self: CaptureTheFlag)
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

function CaptureTheFlag.Start(self: CaptureTheFlag, payload: gameModeTypes.MatchPayload)
	-- Roster + balanced team assignment first (TeamMode owns the bots).
	TeamMode.Start(self, payload)

	-- Flags are map-authored and bound by the Flag binder, which instantiates
	-- via task.spawn (Binder.Start) and through GetInstanceAddedSignal — so a
	-- flag can bind AFTER this Start runs, which a one-shot GetAll() snapshot
	-- races (the empty-table bug). Drive enabling off the binder's class-added
	-- stream instead: it fires once per bind (after Flag.new built the prompt),
	-- catches late binds, and re-fires on a re-tag. The GetAll() sweep covers
	-- flags already bound by the time we get here.
	local binder = self:_getFlagBinder()
	if binder then
		self._maid:GiveTask(binder:GetClassAddedSignal():Connect(function(flag)
			self:_onFlagBound(flag)
		end))
		self._maid:GiveTask(binder:GetClassRemovingSignal():Connect(function(flag)
			self:_onFlagUnbound(flag)
		end))
		for _, flag in binder:GetAll() do
			self:_onFlagBound(flag)
		end
	else
		warn(`[CaptureTheFlag] BinderProvider has no "{GameModeConstants.CTF_FLAG_TAG}" binder — captures will never score`)
	end

	-- Misconfigured-map warn, deferred: an empty _flags right now may just mean
	-- the flags haven't bound yet (the race above), so a synchronous warn would
	-- false-positive. Check a beat later; bail if the match already stopped.
	local stopped = false
	self._maid:GiveTask(function()
		stopped = true
	end)
	task.delay(GameModeConstants.CTF_TICK_INTERVAL, function()
		if not stopped and #self._flags == 0 then
			warn(`[CaptureTheFlag] no BasePart tagged "{GameModeConstants.CTF_FLAG_TAG}" — captures will never score`)
		end
	end)

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

function CaptureTheFlag.Stop(self: CaptureTheFlag)
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
