--[=[
	@class ModerationService

	Anti-cheat escalation for the client-driven NPC brains. The brain-owner
	election gives one client authority over an NPC's movement and shots
	(see NPCServer), which a hacked client can abuse in two ways:

	1. BRAIN_SPOOF — firing the Swing remote with an `npcChar` it does not own.
	   Caught by AttckInvoker comparing the sender against the NPC's
	   BRAIN_OWNER_ATTRIBUTE. Near-certain evidence; the only false positive is
	   a Swing packet racing a join/leave re-election, absorbed by a debounce.
	2. FIRE_RATE — the legitimate owner spamming shots faster than the weapon
	   cooldown. The server ability already rejects those shots (RangeAttack
	   `GetCD()`), so damage never lands; AttckInvoker reports each rejected
	   NPC-routed shot here and a leaky bucket turns sustained abuse into a
	   strike while forgiving the couple of early arrivals network jitter
	   produces on an honest brain client.

	Strikes escalate gradually: re-elect every NPC brain away from the accused
	(neutralize, removes the exploit vector at zero false-positive cost), then
	kick, then a timed Players:BanAsync (which persists platform-side, blocks
	rejoin, and is auditable via GetBanHistoryAsync — no custom ban registry
	needed). Strikes and an incident log persist in a DataStore so
	kick -> rejoin -> repeat offense still reaches the ban tier.

	This is a ServiceBag service registered by ServiceRoot (MatchListener
	precedent), NOT a free-standing Script. Reports arrive from AttckInvoker
	via `serviceBag:GetService(ModerationService)`.
]=]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local NpcConstants = require(ReplicatedStorage.Nevermore.Custom.npc.src.Shared.NpcConstants)

local ModerationService = {}
ModerationService.ServiceName = "ModerationService"

-- Fire-rate leaky bucket: more than EARLY_SHOTS_PER_VIOLATION CD-rejected NPC
-- shots inside a rolling FIRE_RATE_WINDOW_SECONDS window = 1 strike. A legit
-- brain client paces on GetShootInterval and almost never hits the server CD,
-- so a handful of early arrivals is jitter, a sustained stream is a cheat.
local FIRE_RATE_WINDOW_SECONDS = 5
local EARLY_SHOTS_PER_VIOLATION = 4

-- Spoof evidence is near-certain, but an in-flight Swing can race a join/leave
-- re-election — debounce a burst into a single strike instead of insta-kicking.
local SPOOF_STRIKE_DEBOUNCE_SECONDS = 2

-- Escalation tiers (strike thresholds). Monotonic per session: only the
-- highest newly-crossed tier is applied, so a jump straight to KICK does not
-- also run NEUTRALIZE (the kick's PlayerRemoving re-elects anyway).
local NEUTRALIZE_TIER, KICK_TIER, BAN_TIER = 1, 2, 3
local NEUTRALIZE_AT_STRIKES = 1
local KICK_AT_STRIKES = 2
local BAN_AT_STRIKES = 3
local BAN_DURATION_SECONDS = 7 * 24 * 60 * 60 -- 7 days
local KICK_MESSAGE = "Kicked by anti-cheat: NPC weapon exploitation detected."
local BAN_DISPLAY_REASON = "Exploiting (NPC weapon abuse)."

local MODERATION_STORE_NAME = "ModerationLog_v1"
local MAX_LOGGED_INCIDENTS = 50

type Incident = {
	t: number, -- os.time(), human-auditable
	kind: string, -- "BRAIN_SPOOF" | "FIRE_RATE"
	npc: string,
}

type PlayerRecord = {
	strikes: number,
	earlyShotClocks: { number },
	lastSpoofClock: number,
	appliedTier: number,
	incidents: { Incident },
}

-- Module-local on purpose: the ServiceBag calls methods on a proxy instance,
-- so service state must live in upvalues, never in `self` fields.
local serviceBag = nil
local moderationStore: DataStore? = nil
local started = false
local records: { [number]: PlayerRecord } = {}

local function getRecord(userId: number): PlayerRecord
	local record = records[userId]
	if not record then
		record = {
			strikes = 0,
			earlyShotClocks = {},
			lastSpoofClock = -math.huge,
			appliedTier = 0,
			incidents = {},
		}
		records[userId] = record
	end
	return record
end

local function appendIncident(record: PlayerRecord, kind: string, npcChar: Model)
	table.insert(record.incidents, { t = os.time(), kind = kind, npc = npcChar.Name })
	while #record.incidents > MAX_LOGGED_INCIDENTS do
		table.remove(record.incidents, 1)
	end
end

-- Fire-and-forget persistence of {strikes, incidents}. Silent no-op in Studio
-- without API access (moderationStore is nil) — the session still escalates,
-- it just doesn't remember across rejoins.
local function flushRecord(userId: number, record: PlayerRecord)
	if not moderationStore then
		return
	end
	task.spawn(function()
		local ok, err = pcall(moderationStore.UpdateAsync, moderationStore, `player_{userId}`, function()
			return { strikes = record.strikes, incidents = record.incidents }
		end)
		if not ok then
			warn(`[ModerationService] failed to persist record for {userId}: {err}`)
		end
	end)
end

-- Merge the persisted record into the live one (add, don't overwrite: a
-- violation may have landed before this async load finished). appliedTier is
-- deliberately NOT persisted — last session's tier actions already ran, and a
-- fresh 0 makes the next strike after a rejoin cross straight into the right
-- tier (e.g. persisted strikes=2 + 1 new strike => BAN only).
local function loadRecord(player: Player)
	if not moderationStore then
		return
	end
	local ok, saved = pcall(moderationStore.GetAsync, moderationStore, `player_{player.UserId}`)
	if not ok then
		warn(`[ModerationService] failed to load record for {player.UserId}: {saved}`)
		return
	end
	if type(saved) ~= "table" then
		return
	end
	if player.Parent == nil then
		return -- left while GetAsync yielded
	end

	local record = getRecord(player.UserId)
	if type(saved.strikes) == "number" then
		record.strikes += saved.strikes
	end
	if type(saved.incidents) == "table" then
		for index = #saved.incidents, 1, -1 do
			table.insert(record.incidents, 1, saved.incidents[index])
		end
		while #record.incidents > MAX_LOGGED_INCIDENTS do
			table.remove(record.incidents, 1)
		end
	end
	if record.strikes > 0 then
		print(`[ModerationService] {player.Name} rejoined with {record.strikes} persisted strike(s)`)
	end
end

-- Hand every NPC brain the accused currently owns to another client (or the
-- server). Removes the exploit vector without punishing — the tier for "we
-- are suspicious but not certain enough to kick". A point-in-time GetAll() is
-- correct here: this is an on-demand sweep, not a lifecycle subscription.
local function neutralize(accused: Player)
	local provider = serviceBag:GetService(_G.BinderProvider)
	local npcBinder = provider:Get(Constants.NPC_TAG)
	assert(npcBinder, `ModerationService: no binder registered for tag "{Constants.NPC_TAG}"`)

	local reelected = 0
	for _, npcServer in npcBinder:GetAll() do
		if npcServer.char:GetAttribute(NpcConstants.BRAIN_OWNER_ATTRIBUTE) == accused.UserId then
			npcServer:ReelectBrainOwner(accused)
			reelected += 1
		end
	end
	print(`[ModerationService] neutralized {accused.Name}: re-elected {reelected} NPC brain(s)`)
end

local function summarizeIncidents(record: PlayerRecord): string
	local counts: { [string]: number } = {}
	for _, incident in record.incidents do
		counts[incident.kind] = (counts[incident.kind] or 0) + 1
	end
	local parts = {}
	for kind, count in counts do
		table.insert(parts, `{kind} x{count}`)
	end
	return `NPC weapon exploit, {record.strikes} strike(s): {table.concat(parts, ", ")}`
end

local function banAccused(accused: Player, record: PlayerRecord)
	local privateReason = summarizeIncidents(record)
	task.spawn(function()
		-- BanAsync yields and throws in Studio / with API access disabled.
		local ok, err = pcall(function()
			Players:BanAsync({
				UserIds = { accused.UserId },
				Duration = BAN_DURATION_SECONDS,
				DisplayReason = BAN_DISPLAY_REASON,
				PrivateReason = privateReason,
				ExcludeAltAccounts = false,
				ApplyToUniverse = true,
			})
		end)
		if not ok then
			warn(`[ModerationService] BanAsync failed ({err}); falling back to kick`)
			if accused.Parent then
				accused:Kick(KICK_MESSAGE)
			end
		end
	end)
end

local function escalate(accused: Player, record: PlayerRecord)
	local tier = 0
	if record.strikes >= BAN_AT_STRIKES then
		tier = BAN_TIER
	elseif record.strikes >= KICK_AT_STRIKES then
		tier = KICK_TIER
	elseif record.strikes >= NEUTRALIZE_AT_STRIKES then
		tier = NEUTRALIZE_TIER
	end
	if tier <= record.appliedTier then
		return
	end
	record.appliedTier = tier

	if tier == NEUTRALIZE_TIER then
		neutralize(accused)
	elseif tier == KICK_TIER then
		flushRecord(accused.UserId, record)
		accused:Kick(KICK_MESSAGE)
	elseif tier == BAN_TIER then
		flushRecord(accused.UserId, record)
		banAccused(accused, record)
	end
end

local function addStrike(accused: Player, kind: string, npcChar: Model)
	local record = getRecord(accused.UserId)
	record.strikes += 1
	appendIncident(record, kind, npcChar)
	print(`[ModerationService] {kind} by {accused.Name} on {npcChar.Name} (strikes={record.strikes})`)
	escalate(accused, record)
end

--[=[
	A client fired the Swing remote for an NPC it does not own. The shot was
	already rejected by AttckInvoker; this only records and escalates.
]=]
function ModerationService.ReportBrainSpoof(_self: any, accused: Player, npcChar: Model)
	local record = getRecord(accused.UserId)
	local now = os.clock()
	if now - record.lastSpoofClock < SPOOF_STRIKE_DEBOUNCE_SECONDS then
		-- Same burst (or the same re-election race) — evidence, not a new strike.
		appendIncident(record, "BRAIN_SPOOF", npcChar)
		return
	end
	record.lastSpoofClock = now
	addStrike(accused, "BRAIN_SPOOF", npcChar)
end

--[=[
	The brain owner's NPC shot was rejected by the server-side weapon cooldown
	(damage already denied). Feeds the leaky bucket; only a sustained stream of
	early shots becomes a strike.
]=]
function ModerationService.ReportFireRateViolation(_self: any, accused: Player, npcChar: Model)
	local record = getRecord(accused.UserId)
	local now = os.clock()

	table.insert(record.earlyShotClocks, now)
	local clocks = record.earlyShotClocks
	while #clocks > 0 and now - clocks[1] > FIRE_RATE_WINDOW_SECONDS do
		table.remove(clocks, 1)
	end

	if #clocks > EARLY_SHOTS_PER_VIOLATION then
		table.clear(clocks)
		addStrike(accused, "FIRE_RATE", npcChar)
	end
end

function ModerationService.Init(_self: any, _serviceBag: any)
	serviceBag = _serviceBag
end

function ModerationService.Start(_self: any)
	if started then
		return
	end
	started = true

	-- GetDataStore throws in Studio when API access is disabled; moderation
	-- still escalates within the session, strikes just don't persist.
	local storeOk, store = pcall(DataStoreService.GetDataStore, DataStoreService, MODERATION_STORE_NAME)
	if storeOk then
		moderationStore = store
	else
		warn("[ModerationService] DataStore unavailable, strikes will not persist: ", store)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadRecord, player)
	end)
	-- Server-side Start runs during serviceBag:Start(); players who landed
	-- before the connection above still get their record loaded.
	for _, player in Players:GetPlayers() do
		task.spawn(loadRecord, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local record = records[player.UserId]
		if record then
			if #record.incidents > 0 then
				flushRecord(player.UserId, record)
			end
			records[player.UserId] = nil
		end
	end)
end

return ModerationService
