--[=[
	@class GameModeService
	The persistent game-mode context (registered into the ServiceBag at
	ServiceRoot). One reserved server runs ONE mode for its lifetime: the lobby
	payload (or MatchListener's fallback) names it, `StartMatch` latches it,
	and a thin strategy (Modes/TeamDeathmatch, future Koth/Ctf/Lms) supplies
	the behavior — the Armed-binder context/strategy split applied to modes.

	The service owns everything mode-agnostic: the ScoreState snapshot, the
	Team instances, the match timer, win checks, replication over the
	MatchState remote, and the end-of-match combat freeze. The strategy only
	maps game events to `deps.addScore` / `deps.endMatch`.

	State lives in module-local upvalues, NOT in `self` fields: the ServiceBag
	wraps services in `setmetatable({}, { __index = module })`, so instance
	field writes would diverge from MatchListener's direct `require` of this
	module. Upvalues are shared by construction.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

-- Server-only PlayerBinder of per-player quest state. Reached through the bag
-- (registered in ServiceRoot before Init) so the Leave handler can snapshot a
-- leaving player's progress into TeleportData — same module EffectService uses.
local QuestHandler = require(ServerScriptService.Server.Quests.QuestHandler)

local EffectService = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectService)
local GameModeConfig = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConfig)
local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)
local CaptureTheFlag = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.CaptureTheFlag)
local KingOfTheHill = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.KingOfTheHill)
local LastManStanding = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.LastManStanding)
local TeamDeathmatch = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.TeamDeathmatch)

local MatchStateRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.MatchState
local LeaveMatchRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.LeaveMatch

-- Adding a mode = one entry here + one ModeConfig entry + the strategy file.
-- Each value is a GameMode class (its `.new(config)` builds the strategy).
local MODE_REGISTRY: { [string]: gameModeTypes.GameModeClass<gameModeTypes.GameMode> } = {
	tdm = TeamDeathmatch,
	koth = KingOfTheHill,
	ctf = CaptureTheFlag,
	lms = LastManStanding,
}

-- Typed as gameModeTypes.GameModeService at the return (the generic is left at
-- its GameMode default: this reserved server hosts one mode chosen at runtime).
local GameModeService = {}
GameModeService.ServiceName = "GameModeService"

-- Match-lifetime hook connections + timer; cleaned when the match ends.
local matchMaid = Maid.new()

local serviceBag: any = nil
local started = false
local latched = false
local pendingPayload: gameModeTypes.MatchPayload? = nil
local activeMode: gameModeTypes.GameMode? = nil
local activeConfig: gameModeTypes.ModeConfig? = nil

-- Single source of truth, broadcast whole on every mutation (tiny payload).
local scoreState: gameModeTypes.ScoreState = {
	phase = "waiting",
	modeId = "",
	scores = {},
	targetScore = 0,
	matchEndTime = nil,
	winner = nil,
}

local function broadcastScoreState()
	MatchStateRemote:FireAllClients(scoreState)
end

--[=[
	Sends one player back to the matchmaking lobby (LOBBY_PLACE_ID), carrying
	their live quest progress as TeleportData so the hop doesn't lose a match's
	worth of progress — keyed by userId under `questsByUserId` so the lobby reads
	it with the exact same reader it runs for the inbound lobby→match snapshot
	(ServiceRoot.loadSavedQuests). Spam-safe (TeleportService dedupes an in-flight
	teleport for the same player), so both call sites — the Leave button remote and
	the post-match auto-return sweep — can call it freely. With LOBBY_PLACE_ID unset
	(0, e.g. Studio) it's a logged no-op rather than a teleport into a void place.
]=]
function GameModeService.TeleportToLobby(_self: any, player: Player)
	local placeId = GameModeConstants.LOBBY_PLACE_ID
	if placeId <= 0 then
		warn(`[GameModeService] TeleportToLobby for {player.Name} but LOBBY_PLACE_ID is unset — ignoring`)
		return
	end

	local teleportData: gameModeTypes.LeaveTeleportData = {
		questsByUserId = {},
	}
	local playerQuests = serviceBag:GetService(QuestHandler):GetHandler(player)
	if playerQuests then
		teleportData.questsByUserId[tostring(player.UserId)] = playerQuests:GetSaveData()
	end

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(teleportData)

	local ok, err = pcall(function()
		TeleportService:Teleport(placeId, player, options)
	end)
	if not ok then
		warn(`[GameModeService] lobby teleport failed for {player.Name}: {err}`)
	end
end

local function endMatch(winner: gameModeTypes.TeamId?)
	if scoreState.phase ~= "active" then
		return
	end

	scoreState.phase = "ended"
	scoreState.winner = winner or "draw"
	matchMaid._timer = nil

	-- One choke point freezes all combat: EffectService's damage block
	-- early-returns on this attribute (melee and guns both land there).
	Workspace:SetAttribute(GameModeConstants.MATCH_OVER_ATTRIBUTE, true)
	broadcastScoreState()

	-- Single funnel for every win path → the active strategy's inherited
	-- BaseMode.BroadcastResults fires the WinScreen remote (the results screen
	-- reads the already-replicated Leaderboard folder; this only carries the
	-- winner). Done before the deferred Stop so it's sent while the mode is live.
	if activeMode then
		activeMode:BroadcastResults(scoreState.winner)
	end

	-- Deferred: the winning kill reaches here synchronously from INSIDE
	-- EffectService.Apply (CharacterDied → onKill → addScore), and Stop
	-- destroys NPC rigs — possibly the very defender whose damage pipeline
	-- is still running. Let that frame finish before tearing the world down.
	task.defer(function()
		if activeMode then
			activeMode:Stop()
		end
		-- Drop the kill/join hooks; the dead phase needs none of them. The
		-- lobby owns server lifecycle from here (no kicks): the reserved
		-- server dies on its own once players leave.
		matchMaid:DoCleaning()
	end)

	-- Fallback return-to-lobby: once the results screen has been up long enough,
	-- sweep everyone still here back to the lobby (the Leave button is the manual
	-- shortcut; this guarantees a match server never strands players on the end
	-- screen). NOT on matchMaid — that's torn down above; this must outlive it.
	-- Per-player so each carries its own quest snapshot.
	task.delay(GameModeConstants.POST_MATCH_LOBBY_DELAY, function()
		for _, player in Players:GetPlayers() do
			GameModeService:TeleportToLobby(player)
		end
	end)
end

local function addScore(teamId: gameModeTypes.TeamId, amount: number)
	if scoreState.phase ~= "active" then
		return
	end

	scoreState.scores[teamId] = (scoreState.scores[teamId] or 0) + amount
	broadcastScoreState()

	if activeConfig and scoreState.scores[teamId] >= activeConfig.targetScore then
		endMatch(teamId)
	end
end

-- Timer expiry: highest score wins, nil (=> "draw") on a tie.
local function timerWinner(): gameModeTypes.TeamId?
	local bestTeam: gameModeTypes.TeamId? = nil
	local bestScore = -1
	local tied = false
	for teamId, score in pairs(scoreState.scores) do
		if score > bestScore then
			bestTeam, bestScore, tied = teamId, score, false
		elseif score == bestScore then
			tied = true
		end
	end
	return if tied then nil else bestTeam
end

local function createTeams(config: gameModeTypes.ModeConfig)
	if not config.teams then
		return
	end
	for _, spec in config.teams do
		local team = Instance.new("Team")
		team.Name = spec.id
		team.TeamColor = spec.color
		team.AutoAssignable = false
		team.Parent = Teams
		scoreState.scores[spec.id] = 0
	end
end

local function onPlayerAdded(player: Player)
	if scoreState.phase ~= "active" or not activeMode then
		return
	end
	activeMode:onPlayerAdded(player)

	matchMaid["char_" .. player.UserId] = player.CharacterAdded:Connect(function(char)
		activeMode:onCharacterAdded(char, player)
	end)
	if player.Character then
		activeMode:onCharacterAdded(player.Character, player)
	end
end

function GameModeService.StartMatchNow(_self: any, payload: gameModeTypes.MatchPayload)
	local modeId = payload.mode or GameModeConstants.DEFAULT_MODE
	local config = GameModeConfig[modeId]
	if not config or not MODE_REGISTRY[modeId] then
		warn(`[GameModeService] unknown mode "{tostring(modeId)}", falling back to {GameModeConstants.DEFAULT_MODE}`)
		modeId = GameModeConstants.DEFAULT_MODE
		config = GameModeConfig[modeId]
	end

	activeConfig = config
	scoreState.modeId = modeId
	scoreState.targetScore = config.targetScore
	scoreState.matchEndTime = Workspace:GetServerTimeNow() + config.timeLimitSeconds
	createTeams(config)

	local deps: gameModeTypes.GameModeDeps = {
		serviceBag = serviceBag,
		addScore = addScore,
		getScoreState = function()
			return scoreState
		end,
		endMatch = function()
			endMatch()
		end,
	}

	local newActiveMode = MODE_REGISTRY[modeId].new(config)
	activeMode = newActiveMode
	newActiveMode:Init(deps)

	matchMaid:GiveTask(EffectService.CharacterDied:Connect(function(attackerChar, defenderChar)
		newActiveMode:onKill(attackerChar, defenderChar)
	end))
	matchMaid:GiveTask(Players.PlayerAdded:Connect(onPlayerAdded))
	matchMaid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		matchMaid["char_" .. player.UserId] = nil
		newActiveMode:onPlayerRemoving(player)
	end))

	scoreState.phase = "active"
	newActiveMode:Start(payload)

	-- Teleported players can land before the lobby payload arrives — sweep
	-- whoever is already here (onPlayerAdded is idempotent by contract).
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	matchMaid._timer = task.delay(config.timeLimitSeconds, function()
		endMatch(timerWinner())
	end)

	broadcastScoreState()
	print(`[GameModeService] match started: {config.displayName} (targetScore={config.targetScore}, timeLimit={config.timeLimitSeconds}s)`)
end

--[=[
	Entry point MatchListener drives (lobby payload, TeleportData, or its
	fallback). Latched: one reserved server hosts one match. Callable before
	the ServiceBag finished starting — the payload is parked and consumed at
	the end of `Start()`.
]=]
function GameModeService.StartMatch(_self: any, payload: gameModeTypes.MatchPayload)
	if latched then
		return
	end
	if not started then
		pendingPayload = pendingPayload or payload
		return
	end
	latched = true
	GameModeService:StartMatchNow(payload)
end

-- ServiceRoot gate for RemoteEvents.RespawnRequest (LMS turns this off; a
-- TDM end screen still allows respawns — denial is config-driven only).
function GameModeService.CanRespawn(_self: any, _player: Player): boolean
	return activeConfig == nil or activeConfig.respawnEnabled
end

-- ServiceRoot gate for characterCtxUtils:EquipDefaultWeapon (LMS seam).
function GameModeService.ShouldEquipDefaultWeapon(_self: any): boolean
	return activeConfig == nil or activeConfig.equipDefaultWeapon
end

function GameModeService.GetScoreState(_self: any): gameModeTypes.ScoreState
	return scoreState
end

function GameModeService.Init(_self: any, bag: any)
	serviceBag = bag
end

function GameModeService.Start(_self: any)
	if started then
		return
	end
	started = true

	-- HUD resync-on-mount: the client fires the remote back at us and we
	-- answer with the full snapshot (QuestProgress pattern — join-time
	-- broadcasts land before the component connected OnClientEvent).
	MatchStateRemote.OnServerEvent:Connect(function(player)
		MatchStateRemote:FireClient(player, scoreState)
	end)

	-- Win-screen "Leave" button: the manual shortcut into the shared return path.
	LeaveMatchRemote.OnServerEvent:Connect(function(player)
		GameModeService:TeleportToLobby(player)
	end)

	if pendingPayload then
		local payload = pendingPayload
		pendingPayload = nil
		GameModeService:StartMatch(payload)
	end
end

return GameModeService :: gameModeTypes.GameModeService<gameModeTypes.GameMode>
