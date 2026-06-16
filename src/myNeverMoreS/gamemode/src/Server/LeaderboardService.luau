--[=[
	@class LeaderboardService
	Per-player match scoreboard. Owns one ReplicatedStorage Folder of IntValues
	per player, so any client can mirror the whole board by observing children —
	no remote, no per-mode branching (see LeaderboardConstants for the shape).

	Two sources feed it:
	  * Base stats (kills / deaths / damage) are wired here off EffectService's
	    authoritative combat signals — CharacterDied (the one lethal-damage site)
	    and DamageDealt (every validated hit). The service is the only consumer
	    that needs to know those signals map to a scoreboard; modes stay out of it.
	  * Mode-specific stats (CTF flags, KOTH hill_time) are pushed by the mode
	    strategy via `AddStat`, which creates the IntValue lazily on first use —
	    so the optional field appears only in the mode that tracks it.

	Only REAL players get a registry; NPC rigs (CharacterDied/DamageDealt also
	fire for bots) are filtered out via Players:GetPlayerFromCharacter.

	State lives in module-local upvalues, NOT `self` fields — same reasoning as
	GameModeService (the ServiceBag wraps the module in setmetatable, so instance
	writes would diverge from a direct require; see the servicebag-instance-vs-
	module-identity memory). Methods take `_self: any` and ignore it.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local EffectService = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectService)
local LeaderboardConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.LeaderboardConstants)

local LeaderboardService = {}
LeaderboardService.ServiceName = "LeaderboardService"

-- Lifetime connections (EffectService + Players signals); cleaned never in
-- practice (the service lives as long as the server), but parked in a Maid for
-- symmetry / future teardown.
local maid = Maid.new()

local started = false
local rootFolder: Folder? = nil
-- UserId -> that player's registry Folder.
local registries: { [number]: Folder } = {}

-- The IntValue named `statName` under a player's registry, created at 0 if it
-- doesn't exist yet. Returns nil only if the player has no registry (left, or a
-- bot) — callers treat that as a no-op.
local function getOrCreateStat(player: Player, statName: string): IntValue?
	local registry = registries[player.UserId]
	if not registry then
		return nil
	end

	local stat = registry:FindFirstChild(statName)
	if stat then
		return stat :: IntValue
	end

	local newStat = Instance.new("IntValue")
	newStat.Name = statName
	newStat.Value = 0
	newStat.Parent = registry
	return newStat
end

-- Create the player's registry Folder with the base stats seeded at 0.
-- Idempotent: a re-register (the Start sweep racing PlayerAdded) is a no-op.
function LeaderboardService.RegisterPlayer(_self: any, player: Player)
	if registries[player.UserId] then
		return
	end
	assert(rootFolder, "[LeaderboardService] RegisterPlayer before Start built the root folder")

	local registry = Instance.new("Folder")
	registry.Name = tostring(player.UserId)
	registries[player.UserId] = registry

	-- Seed the always-present base stats before parenting, so a client observer
	-- that catches the folder's ChildAdded already sees the three IntValues.
	for _, statName in {
		LeaderboardConstants.STAT_KILLS,
		LeaderboardConstants.STAT_DEATHS,
		LeaderboardConstants.STAT_DAMAGE,
	} do
		local stat = Instance.new("IntValue")
		stat.Name = statName
		stat.Value = 0
		stat.Parent = registry
	end

	registry.Parent = rootFolder
end

function LeaderboardService.RemovePlayer(_self: any, player: Player)
	local registry = registries[player.UserId]
	if registry then
		registry:Destroy()
		registries[player.UserId] = nil
	end
end

-- The registry Folder for a player (for a client-side resync read, or a mode
-- that wants to inspect it). nil for a player without one (bot / not joined).
function LeaderboardService.GetRegistry(_self: any, player: Player): Folder?
	return registries[player.UserId]
end

--[=[
	Add `amount` to a player's `statName`, creating the IntValue at 0 first if it
	doesn't exist. This is the seam modes use for their own fields: CTF calls it
	with STAT_FLAGS, KOTH with STAT_HILL_TIME, and the field pops into the
	registry on first use. `amount` is rounded — IntValue is integer, and a
	fractional damage tick would otherwise truncate toward zero each call.
	No-op for a player without a registry (bot / left mid-event).
]=]
function LeaderboardService.AddStat(_self: any, player: Player, statName: string, amount: number)
	local stat = getOrCreateStat(player, statName)
	if not stat then
		return
	end
	stat.Value += math.round(amount)
end

-- Pre-create `statName` at 0 without changing it — lets a mode surface its
-- optional field from match start (so the HUD shows "0 flags" rather than the
-- field only appearing on the first capture). No-op if it already exists.
function LeaderboardService.EnsureStat(_self: any, player: Player, statName: string)
	getOrCreateStat(player, statName)
end

-- kills/deaths: the one authoritative lethal-damage signal. The killer is a
-- character Model that may be an NPC rig; both sides are filtered to real
-- players. A self/team kill still counts whatever fired (mode policy lives in
-- the mode, not here).
local function onCharacterDied(attackerChar: Model, defenderChar: Model)
	local killer = Players:GetPlayerFromCharacter(attackerChar)
	if killer then
		LeaderboardService:AddStat(killer, LeaderboardConstants.STAT_KILLS, 1)
	end

	local victim = Players:GetPlayerFromCharacter(defenderChar)
	if victim then
		LeaderboardService:AddStat(victim, LeaderboardConstants.STAT_DEATHS, 1)
	end
end

-- damage: every validated hit. Only the attacker accrues; bots are filtered.
local function onDamageDealt(attackerChar: Model, _defenderChar: Model, amount: number)
	local attacker = Players:GetPlayerFromCharacter(attackerChar)
	if attacker then
		LeaderboardService:AddStat(attacker, LeaderboardConstants.STAT_DAMAGE, amount)
	end
end

function LeaderboardService.Init(_self: any, _bag: any) end

function LeaderboardService.Start(_self: any)
	if started then
		return
	end
	started = true

	local folder = Instance.new("Folder")
	folder.Name = LeaderboardConstants.FOLDER_NAME
	folder.Parent = ReplicatedStorage
	rootFolder = folder

	-- Combat-driven base stats, off the authoritative EffectService signals.
	maid:GiveTask(EffectService.CharacterDied:Connect(onCharacterDied))
	maid:GiveTask(EffectService.DamageDealt:Connect(onDamageDealt))

	-- Self-driven player lifecycle (no ServiceRoot wiring needed). RegisterPlayer
	-- is idempotent, so the join signal racing the existing-players sweep is safe.
	maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		LeaderboardService:RegisterPlayer(player)
	end))
	maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		LeaderboardService:RemovePlayer(player)
	end))
	for _, player in Players:GetPlayers() do
		LeaderboardService:RegisterPlayer(player)
	end
end

return LeaderboardService
