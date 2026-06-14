--[=[
	@class Flag
	The CTF flag, server side. A binder over every BasePart tagged CTF_FLAG_TAG:
	the part carries the TEAM_ATTRIBUTE of the team that OWNS it (enemies steal
	it). The binder owns the whole flag lifecycle — the ProximityPrompt, the
	server-validated grab, the carrier tag, and the return-to-base on death — so
	the CaptureTheFlag mode only has to discover flags and decide scoring.

	Trust model (the prompt is the exploitable surface):
	  * `ProximityPrompt.Triggered` fires from a client-initiated signal and the
	    engine does NOT re-check distance / line-of-sight server-side — an
	    exploiter can fire it from across the map. `_onTriggered` re-validates
	    distance against CTF_GRAB_DISTANCE itself (scenario #1 fix), plus
	    aliveness, team eligibility (steal the ENEMY flag only) and one-flag-per
	    carrier.
	  * The carrier tag is set ON THE SERVER, so it is authoritative — clients
	    can't forge it, and FlagBillboard / the capture ZoneController read it
	    for free off the replicated tag.

	The flag is grabbable only while the CTF mode has enabled it (`SetEnabled`),
	which also gates the prompt to active matches even though the binder itself
	lives for the whole server (tags are authored in the map, not per-match).
]=]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)
local resolveTeam = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.resolveTeam)

local Flag = {}
Flag.__index = Flag

function Flag.new(flag: BasePart, _serviceBag: any, _binderProvider: any)
	local self = setmetatable({}, Flag)

	self._flag = flag
	self._maid = Maid.new()
	-- The team that DEFENDS this flag (a TeamId string). Enemies steal it.
	self._team = flag:GetAttribute(GameModeConstants.TEAM_ATTRIBUTE) :: gameModeTypes.TeamId?
	self._baseCFrame = flag.CFrame
	self._baseTransparency = flag.Transparency
	self._carrier = nil :: Model? -- the character currently holding this flag
	self._active = false -- the CTF mode toggles this on at Start

	self:_createProximityPrompt()
	return self
end

-- One custom prompt per flag. The distances/text here are client hints; the
-- real gate is the server re-validation in `_onTriggered`.
function Flag._createProximityPrompt(self)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal Flag"
	prompt.ObjectText = (self._team or "Flag") .. " Flag"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = GameModeConstants.CTF_GRAB_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = self._flag
	self._prompt = prompt
	self._maid:GiveTask(prompt)

	self._maid:GiveTask(prompt.Triggered:Connect(function(player: Player)
		self:_onTriggered(player)
	end))
	print("prompt ", prompt)
end

function Flag.GetTeam(self): gameModeTypes.TeamId?
	return self._team
end

function Flag.GetCarrier(self): Model?
	return self._carrier
end

-- Classic CTF: a team may only score while its own flag sits at base.
function Flag.IsAtBase(self): boolean
	return self._carrier == nil
end

--[=[
	The CTF mode enables flags at Start and disables them at Stop. Disabling
	also returns any held flag so the world is clean for the end screen. The
	prompt is only ever live while enabled AND at base.
]=]
function Flag.SetEnabled(self, enabled: boolean)
	self._active = enabled
	if not enabled then
		self:ReturnToBase()
	end
	self._prompt.Enabled = enabled and self._carrier == nil
end

function Flag._onTriggered(self, player: Player)
	if not self._active or self._carrier then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Scenario #1 fix: the prompt's MaxActivationDistance is enforced only on the
	-- triggering client and is spoofable, so re-check the real distance here.
	if (hrp.Position - self._flag.Position).Magnitude > GameModeConstants.CTF_GRAB_DISTANCE then
		return
	end

	-- Team eligibility: steal the ENEMY flag only. resolveTeam is the same rule
	-- the damage check uses, so players (and future bots) are judged identically;
	-- a teamless grabber or a touch on your own flag is a no-op.
	local grabberTeam = resolveTeam(character, getCharacterActor(character))
	if not grabberTeam or not self._team or grabberTeam.Name == self._team then
		return
	end

	-- One flag per carrier.
	if CollectionService:HasTag(character, GameModeConstants.CTF_CARRIER_TAG) then
		return
	end

	self:_attachTo(character)
end

function Flag._attachTo(self, character: Model)
	self._carrier = character
	-- Server-authored, replicated to every client: the single source of truth the
	-- capture ZoneController reads and the client carry visuals (FlagBillboard +
	-- GroundPath, via the CarrierClient binder) observe — no remote needed. Hide
	-- the flag part itself; the billboard represents it.
	CollectionService:AddTag(character, GameModeConstants.CTF_CARRIER_TAG)
	self._prompt.Enabled = false
	self._flag.Transparency = 1

	-- Drop on death (and on the carrier leaving the world): return the flag home
	-- so it never vanishes with a corpse. Keyed on the maid so ReturnToBase can
	-- drop these watches without touching the prompt/Triggered tasks.
	local carrierMaid = Maid.new()
	self._maid._carrier = carrierMaid

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		carrierMaid:GiveTask(humanoid.Died:Connect(function()
			self:ReturnToBase()
		end))
	end
	carrierMaid:GiveTask(character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:ReturnToBase()
		end
	end))
end

-- Send the flag home: clear the carrier (untag, drop the death watch), restore
-- the part. Used by drop-on-death, by a capture (the mode calls this after it
-- scores), and by SetEnabled(false) on Stop.
function Flag.ReturnToBase(self)
	local character = self._carrier
	if not character then
		return
	end
	self._carrier = nil
	self._maid._carrier = nil

	if character.Parent then
		-- Removing the tag is the unmount signal: the CarrierClient binder fires
		-- its class-removing on every client, dropping the carry visuals. (A
		-- death/despawn untags via the destroyed instance too, and FlagBillboard
		-- keeps its own AncestryChanged net as a redundant backstop.)
		CollectionService:RemoveTag(character, GameModeConstants.CTF_CARRIER_TAG)
	end

	self._flag.CFrame = self._baseCFrame
	self._flag.Transparency = self._baseTransparency
	self._prompt.Enabled = self._active
end

function Flag.Destroy(self)
	-- Untag the carrier before the maid tears the rest down.
	self:ReturnToBase()
	self._maid:DoCleaning()
	print("DESTROYINF FLAG")
end

return Flag
