--[=[
	@class MatchListener

	Receives the lobby's "match found" broadcast and fills this reserved server
	with bots. The lobby publishes, once per match:

		MessagingService:PublishAsync(Config.MATCH_FOUND_TOPIC, {
			matchId = HttpService:GenerateGUID(false),
			accessCode = accessCode,
			userIds = userIds,
			botCount = botCount,
			privateServerId = privateServerId, -- see "Which server" below
		})

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
	isn't up and never hears it. So we also read `botCount` out of TeleportData
	on the first arriving player: the teleport is what boots this server, so
	that path can't miss. Whichever trigger arrives first wins; `_state.filled`
	makes the spawn run exactly once per server (a reserved server hosts one
	match).
]=]

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local helpers = require(ServerScriptService.Server.Utils.helpers)
local Constanst = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local NpcSpawner = require(script.Parent.NpcSpawner)

-- MUST equal the lobby's `Config.MATCH_FOUND_TOPIC`. Different place, separate
-- codebase, so it can't be shared by require — keep the two strings in sync.

-- One match per reserved server: once we've spawned the bots we ignore every
-- later trigger (the redundant MessagingService/TeleportData paths, retries).
local _state = { filled = false }

--[=[
	Spawns `botCount` bots, exactly once. `source` is just for the log line so
	we can see which trigger won the race. A spawn failure un-latches `filled`
	so the other trigger still gets a shot.
]=]
local function fill(botCount: any, source: string)
	if _state.filled then
		return
	end
	if type(botCount) ~= "number" or botCount <= 0 then
		warn(`[MatchListener] ignoring {source} trigger: botCount is not a positive number ({tostring(botCount)})`)
		return
	end

	_state.filled = true
	-- returnDataOrError pushes the failure to the client debug console (readable
	-- from a published-game client) and returns falsy on error.
	local ok = helpers.returnDataOrError(nil, function()
		NpcSpawner.Spawn(botCount)
	end)
	if ok then
		print(`[MatchListener] filled server with {botCount} bots (via {source})`)
	else
		_state.filled = false
		warn(`[MatchListener] NpcSpawner.Spawn failed (via {source})`)
	end
end

--[=[
	Is this MessagingService broadcast meant for this server? Primary check is
	the reserved-server identity; the userIds check is a best-effort fallback
	for a lobby that didn't send `privateServerId`.
]=]
local function isForThisServer(data: any): boolean
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

-- Trigger 1: the MessagingService broadcast.
task.spawn(function()
	-- returnDataOrError reports the failure to the client debug console for us.
	local ok = helpers.returnDataOrError(nil, function()
		MessagingService:SubscribeAsync(Constanst.MATCH_FOUND_TOPIC, function(message)
			local data = message.Data
			if isForThisServer(data) then
				fill(data.botCount, "MessagingService")
			end
		end)
	end)
	if not ok then
		warn(`[MatchListener] SubscribeAsync({Constanst.MATCH_FOUND_TOPIC}) failed`)
	end
end)



-- Trigger 2: botCount carried in TeleportData on the players the lobby sent.
-- The teleport is what boots this server, so this path can't be missed.
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
	if type(teleportData) == "table" and teleportData.botCount then
		fill(teleportData.botCount, "TeleportData")
	end
end

for _, player in Players:GetPlayers() do
	task.spawn(tryTeleportData, player)
end
Players.PlayerAdded:Connect(tryTeleportData)
