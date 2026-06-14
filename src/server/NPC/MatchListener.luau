--[=[
	@class MatchListener

	Receives the lobby's "match found" broadcast and starts this reserved
	server's match (game mode + bots). The lobby publishes, once per match:

		MessagingService:PublishAsync(Config.MATCH_FOUND_TOPIC, {
			matchId = HttpService:GenerateGUID(false),
			accessCode = accessCode,
			userIds = userIds,
			botCount = botCount,
			mode = mode, -- GameModeConfig key; omitted => DEFAULT_MODE
			privateServerId = privateServerId, -- see "Which server" below
		})

	The payload is handed to GameModeService:StartMatch, which resolves the
	mode strategy (TDM spawns + team-assigns the bots itself — this script no
	longer drives NpcSpawner directly).

	"Which server" — MessagingService broadcasts to *every* running server in
	the universe, so the payload must name the target server and that server
	must recognise itself. The reliable key is the PrivateServerId the lobby got
	back from `TeleportService:ReserveServer` (returned alongside the
	accessCode): the reserved server reads the identical value from
	`game.PrivateServerId`. The accessCode can't be read back by the server it
	reserved, so it's no good for matching — it only exists to do the teleport.
	=> ask the lobby to put `privateServerId` on the message.

	Boot timing — MessagingService does NOT queue for a server that hasn't
	started yet. If the lobby publishes the instant it reserves, this server
	isn't up and never hears it. So we also read the payload out of
	TeleportData on the first arriving player: the teleport is what boots this
	server, so that path can't miss. Whichever trigger arrives first wins;
	`_state.filled` makes the start run exactly once per server (a reserved
	server hosts one match). A third trigger covers everything else: after
	STUDIO_FALLBACK_SECONDS with no payload, Studio playtests and direct-join
	(non-reserved) servers start DEFAULT_MODE with a few bots.

	This is a ServiceBag service registered by ServiceRoot, NOT a free-standing
	Script: its require chain (GameModeService → EffectService → Quenty Ragdoll)
	contains loader-dependent Quenty modules, and a sibling Script can be
	scheduled before ServiceRoot's `bootstrapGame` has injected the `loader`
	links. ServiceRoot requires everything post-bootstrap, so the triggers are
	wired in `Start()`. The GetPlayers sweep covers players who landed earlier.
]=]

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local helpers = require(ServerScriptService.Server.Utils.helpers)
local Constanst = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local GameModeService = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.GameModeService)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)

local MatchListener = {}
MatchListener.ServiceName = "MatchListener"

-- MUST equal the lobby's `Config.MATCH_FOUND_TOPIC`. Different place, separate
-- codebase, so it can't be shared by require — keep the two strings in sync.

-- One match per reserved server: once we've started it we ignore every later
-- trigger (the redundant MessagingService/TeleportData paths, retries).
-- Module-local on purpose: the ServiceBag calls methods on a proxy instance,
-- so service state must live in upvalues, never in `self` fields.
local _state = { filled = false }
local started = false

--[=[
	Starts the match exactly once. `source` is just for the log line so we can
	see which trigger won the race. A start failure un-latches `filled` so the
	other trigger still gets a shot.
]=]
local function fill(data: gameModeTypes.MatchFoundPayload, source: string)
	if _state.filled then
		return
	end
	-- Defensive despite the static type: `data` reaches us off MessagingService /
	-- TeleportData, both `any` at runtime and authored in a separate place.
	if type(data) ~= "table" then
		warn(`[MatchListener] ignoring {source} trigger: payload is not a table`)
		return
	end

	local botCount = data.botCount
	local mode = data.mode
	local hasBots = type(botCount) == "number" and botCount >= 0
	local hasMode = type(mode) == "string"
	-- A mode-only payload is a valid all-human match (botCount = 0); a
	-- bots-only payload is the legacy lobby shape (mode defaults server-side).
	if not hasBots and not hasMode then
		warn(`[MatchListener] ignoring {source} trigger: payload has neither botCount nor mode`)
		return
	end

	_state.filled = true
	-- returnDataOrError pushes the failure to the client debug console (readable
	-- from a published-game client) and returns falsy on error.
	local ok = helpers.returnDataOrError(nil, function()
		GameModeService:StartMatch({
			mode = if hasMode then mode else nil,
			botCount = if hasBots then botCount else 0,
			matchId = data.matchId,
		})
	end)
	if ok then
		print(`[MatchListener] match started: mode={tostring(mode)} bots={tostring(botCount)} (via {source})`)
	else
		_state.filled = false
		warn(`[MatchListener] GameModeService:StartMatch failed (via {source})`)
	end
end

--[=[
	Is this MessagingService broadcast meant for this server? Primary check is
	the reserved-server identity; the userIds check is a best-effort fallback
	for a lobby that didn't send `privateServerId`.
]=]
local function isForThisServer(data: gameModeTypes.MatchFoundPayload): boolean
	if type(data) ~= "table" then
		return false
	end

	-- Reserved servers have a non-empty PrivateServerId equal to the one the
	-- lobby got from ReserveServer. Empty string => a normal server: not us.
	local thisServerId = game.PrivateServerId
	if data.privateServerId and thisServerId ~= "" then
		return data.privateServerId == thisServerId
	end

	-- No id on the payload: accept only if one of the match's users is already
	-- here. Weaker (subject to the boot-timing caveat) but better than spawning
	-- bots into every server in the universe.
	if type(data.userIds) == "table" then
		for _, userId in data.userIds do
			if Players:GetPlayerByUserId(userId) then
				return true
			end
		end
	end

	return false
end

-- Trigger 2: the payload carried in TeleportData on the players the lobby
-- sent. The teleport is what boots this server, so this path can't be missed.
local function tryTeleportData(player: Player)
	if _state.filled then
		return
	end
	local ok, joinData = helpers.returnDataOrError(player, function()
		return player:GetJoinData()
	end)
	-- returnDataOrError returns nothing on failure (and already logged it).
	if not ok then
		return
	end

	local teleportData = joinData.TeleportData
	if type(teleportData) == "table" and (teleportData.botCount or teleportData.mode) then
		fill(teleportData, "TeleportData")
	end
end

function MatchListener.Init(_self: any, _serviceBag: any)
	-- Nothing to resolve from the bag; triggers are wired in Start.
end

function MatchListener.Start(_self: any)
	if started then
		return
	end
	started = true

	-- Trigger 1: the MessagingService broadcast.
	task.spawn(function()
		-- returnDataOrError reports the failure to the client debug console for us.
		local ok = helpers.returnDataOrError(nil, function()
			MessagingService:SubscribeAsync(Constanst.MATCH_FOUND_TOPIC, function(message)
				local data = message.Data
				if isForThisServer(data) then
					fill(data, "MessagingService")
				end
			end)
		end)
		if not ok then
			warn(`[MatchListener] SubscribeAsync({Constanst.MATCH_FOUND_TOPIC}) failed`)
		end
	end)

	-- Trigger 2 wiring: sweep covers players who landed before Start ran.
	for _, player in Players:GetPlayers() do
		task.spawn(tryTeleportData, player)
	end
	Players.PlayerAdded:Connect(tryTeleportData)

	-- Trigger 3: no payload ever arrives — Studio playtests and direct-join
	-- servers. Gated off real reserved servers so a slow lobby publish is never
	-- preempted by the default mode.
	task.delay(GameModeConstants.STUDIO_FALLBACK_SECONDS, function()
		if _state.filled then
			return
		end
		if RunService:IsStudio() or game.PrivateServerId == "" then
			fill({
				mode = GameModeConstants.DEFAULT_MODE,
				botCount = GameModeConstants.STUDIO_FALLBACK_BOT_COUNT,
			}, "fallback")
		end
	end)
end

return MatchListener
