--[=[
	@class BaseMode
	Abstract game-mode strategy: stores the ModeConfig + GameModeDeps, owns a
	Maid, and defaults every hook to a no-op so concrete modes only override
	what they use (same shape as WeaponBase under the Armed context).

	Lifecycle (driven by GameModeService): Init(deps) → Start(payload) → hooks
	while the match is active → Stop() when it ends. Stop must leave the world
	clean (despawn mode-owned rigs/objects); Destroy is Stop for binder-style
	teardown symmetry.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local LoadoutService = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.LoadoutService)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)

local WinScreenRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.WinScreen

local BaseMode = {}
BaseMode.__index = BaseMode

-- BaseMode IS the shared GameMode interface (gameModeTypes.GameMode): it
-- implements every hook as a no-op and owns config/_deps/_maid. Concrete modes
-- `&`-extend this with their own fields.
export type BaseMode = gameModeTypes.GameMode

function BaseMode.new(config: gameModeTypes.ModeConfig): BaseMode
	local self = setmetatable({}, BaseMode)

	self.config = config
	self._deps = nil
	self._maid = Maid.new()

	return self :: BaseMode
end

function BaseMode.Init(self: BaseMode, deps: gameModeTypes.GameModeDeps)
	self._deps = deps
end

function BaseMode.Start(self: BaseMode, _payload: gameModeTypes.MatchPayload) end

function BaseMode.Stop(self: BaseMode)
	self._maid:DoCleaning()
end

function BaseMode.onPlayerAdded(self: BaseMode, _player: Player) end

function BaseMode.onPlayerRemoving(self: BaseMode, _player: Player) end

-- Data-driven loadout: a mode with `giveLoadout` hands every real player their
-- profile loadout (StarterGear + Backpack; see LoadoutService) — StarterGear makes
-- it survive respawn, so this per-spawn call is idempotent (a no-op once the
-- weapons are already present). A subclass that overrides this and still wants the
-- loadout MUST chain `BaseMode.onCharacterAdded(self, char, player)`.
function BaseMode.onCharacterAdded(self: BaseMode, char: Model, _player: Player?)
	if self.config.giveLoadout then
		LoadoutService.GiveLoadout(char)
	end
end

function BaseMode.onKill(self: BaseMode, _attackerChar: Model, _defenderChar: Model) end

--[=[
	End-of-match results broadcast. Defined here so every concrete mode inherits
	it: GameModeService.endMatch (the single funnel every win path lands in —
	score cap, timer expiry, LMS last-alive) calls it on the active strategy.

	Fires the WinScreen remote to all clients to load the results screen. The
	leaderboard itself is NOT in this payload — it already lives, fully
	replicated, in the ReplicatedStorage Leaderboard folder LeaderboardService
	builds, so the client just observes that. The remote only carries the trigger
	plus the winner for the banner ("draw" on a tie / nil winner).

	First it freezes every player where they stand. Combat is already frozen by
	the MATCH_OVER_ATTRIBUTE choke point (GameModeService.endMatch); this stops
	movement so the match visibly ends under the results screen. WalkSpeed AND
	jump both go to 0 — a walk-only freeze still lets players hop around — and
	JumpPower/JumpHeight are both zeroed to cover either Humanoid.UseJumpPower
	mode. Per-player only; mode-owned NPC rigs are torn down by Stop().
]=]
function BaseMode.BroadcastResults(_self: BaseMode, winner: gameModeTypes.TeamId?)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		end
	end

	WinScreenRemote:FireAllClients({ winner = winner or "draw" })
end

function BaseMode.Destroy(self: BaseMode)
	self:Stop()
end

return BaseMode
