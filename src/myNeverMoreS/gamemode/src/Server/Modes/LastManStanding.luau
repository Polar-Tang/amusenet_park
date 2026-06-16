--[=[
	@class LastManStanding
	The "lms" strategy: free-for-all, one life, last survivor wins. It extends
	BaseMode (NOT TeamMode) because everything that makes it different is the
	absence of the team machinery:

	  * No teams. config.teams is nil, so GameModeService creates no Team
	    instances and never assigns anyone — every player and bot stays teamless.
	    `resolveTeam` returns nil for a teamless combatant and the damage gate
	    (canPlayerDamageHumanoid) reads nil as "allow", so FFA falls straight out
	    of the existing rules: the "fallback" the team modes never needed is just
	    the pre-gamemode neutral behavior, already in resolveTeam.
	  * No respawn (config.respawnEnabled = false): ServiceRoot denies
	    RespawnRequest, so a death is an elimination.
	  * Profile loadout (config.giveLoadout = true): players are handed the weapons
	    named by their TeleportData profile (cloned out of ServerStorage by
	    LoadoutService), on top of the default fist (equipDefaultWeapon stays true).
	    onCharacterAdded chains BaseMode.onCharacterAdded to drive that loadout.

	Win condition. GameModeService owns the timer and the score cap, but an
	elimination win isn't score-shaped, so LMS calls deps.endMatch directly:
	  * elimination — once the round has had >= 2 living players and exactly one
	    remains, that survivor wins (0 left, a mutual kill => draw);
	  * time-up — GameModeService's timer calls endMatch(timerWinner()), which
	    ranks ScoreState.scores; LMS tallies each real player's kills there
	    (deps.addScore) so the most-kills player wins a timed-out round, ties =>
	    draw. The score cap (config.targetScore) is parked out of reach so this
	    tally never ends the round early.

	Bots count as combatants: spawned teamless via NpcSpawner, they fight, can
	eliminate players, and are tracked in the live set exactly like a real player
	— so an all-bot round still resolves (the last rig standing wins) instead of
	hanging forever. Only real players bank kills for the time-up tally (a bot has
	no ScoreState row), but for the last-standing check a bot is just another life.
	One life means no respawn wiring; Stop despawns them.
]=]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local BaseMode = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Server.Modes.BaseMode)
local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)
local Maid = require(ReplicatedStorage.Shared.Animations.Utils.Maid)

local NpcSpawner = require(ServerScriptService.Server.NPC.NpcSpawner)

local LastManStanding = setmetatable({}, { __index = BaseMode })
LastManStanding.__index = LastManStanding

-- Extends the shared GameMode shape (via BaseMode) with the FFA round state: no
-- teams, so none of TeamMode's roster — just the live set, the contest gate and
-- the bot rigs.
export type LastManStanding = typeof(setmetatable(
	{} :: {
		-- combatant Instance (Player for a human, rig Model for a bot) -> the
		-- display name shown on the HUD if they win. One life, so a key is removed
		-- on death and never re-added; the live set IS the round's survivors, bots
		-- included, so an all-bot round still resolves.
		_alive: { [Instance]: string },
		_aliveCount: number,
		-- Arms the elimination win only after the round has been a contest (>= 2
		-- alive): without it a solo Studio playtest would "win" instantly.
		_armed: boolean,
		-- FFA bot rigs, despawned at Stop (no respawn in a one-life round).
		_bots: { Model },
		_maid: Maid.Maid,
	},
	LastManStanding
)) & BaseMode.BaseMode

function LastManStanding.new(config: gameModeTypes.ModeConfig): LastManStanding
	local self = setmetatable(BaseMode.new(config) :: any, LastManStanding)

	self._alive = {} :: { [Instance]: string }
	self._aliveCount = 0
	self._armed = false
	self._bots = {} :: { Model }

	return self :: LastManStanding
end

-- Begins tracking a combatant (a real player or a bot rig) as alive and arms
-- the death that eliminates them. `combatant` is the Player for a human or the
-- rig Model for a bot — it doubles as the live-set key AND the maid key, so the
-- elimination path is identical for both. `name` is what the HUD shows on a win.
-- Idempotent: the match-start sweep and the CharacterAdded signal can both reach
-- a player present at Start, and Start can re-reach a bot.
function LastManStanding._track(self: LastManStanding, combatant: Instance, char: Model, name: string)
	if self._alive[combatant] then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	self._alive[combatant] = name
	self._aliveCount += 1
	if self._aliveCount >= 2 then
		self._armed = true -- the round became a real contest
	end

	-- Died (not the kill signal) covers every elimination cause — a rival's
	-- shot, a fall, a reset. Keyed in the maid by the combatant Instance so a
	-- leave/death/Stop drops it.
	self._maid[combatant] = humanoid.Died:Connect(function()
		self:_eliminate(combatant)
	end)
end

function LastManStanding._eliminate(self: LastManStanding, combatant: Instance)
	if not self._alive[combatant] then
		return
	end
	self._alive[combatant] = nil
	self._aliveCount -= 1
	self._maid[combatant] = nil
	self:_checkWin()
end

-- Last survivor wins. Only fires once the round has been a contest (>= 2 alive)
-- so a single-player session never insta-ends; a mutual kill (0 left) is a draw.
function LastManStanding._checkWin(self: LastManStanding)
	if not self._armed or not self._deps or self._aliveCount > 1 then
		return
	end

	local winner: gameModeTypes.TeamId? = nil
	for _, name in self._alive do
		winner = name -- ScoreState.winner is a plain string; player/bot name reads fine on the HUD
	end
	self._deps.endMatch(winner)
end

function LastManStanding.onCharacterAdded(self: LastManStanding, char: Model, player: Player?)
	-- Chain BaseMode so LMS players get their profile loadout (config.giveLoadout
	-- is true): the weapons come from each player's TeleportData profile, cloned
	-- into StarterGear/Backpack by LoadoutService. The fist still spawns by default
	-- (equipDefaultWeapon) as the no-Tool melee fallback.
	BaseMode.onCharacterAdded(self, char, player)
	if not player then
		return
	end
	self:_track(player, char, player.Name)
end

function LastManStanding.onPlayerRemoving(self: LastManStanding, player: Player)
	-- A leaver is out of the running like a death (covers a rage-quit at 2 left).
	self:_eliminate(player)
end

function LastManStanding.onKill(self: LastManStanding, attackerChar: Model, defenderChar: Model)
	if attackerChar == defenderChar or not self._deps then
		return
	end
	-- Only a real player banks a kill (bots can't win). The tally exists solely
	-- to rank survivors if the round times out — GameModeService.timerWinner
	-- reads ScoreState.scores, and the cap is parked out of reach so this never
	-- ends the round early.
	local attacker = Players:GetPlayerFromCharacter(attackerChar)
	if not attacker then
		return
	end
	self._deps.addScore(attacker.Name, 1)
end

function LastManStanding.Start(self: LastManStanding, payload: gameModeTypes.MatchPayload)
	-- FFA bots: no teamIds => no GameTeam attribute => teamless (Neutral), so the
	-- brain hunts real players and the damage gate lets everyone hurt them. One
	-- life, so no respawn wiring — just hold the rigs for Stop teardown.
	local botCount = payload.botCount or 0
	if botCount > 0 then
		self._bots = NpcSpawner.Spawn(botCount)
		-- Track each rig as a one-life combatant so its death decrements the live
		-- set and an all-bot round still reaches a last-standing winner. NpcSpawner
		-- returns rigs already parented with a Humanoid, so _track wires Died now.
		for _, rig in self._bots do
			self:_track(rig, rig, rig.Name)
		end
	end
end

function LastManStanding.Stop(self: LastManStanding)
	-- Despawn FFA bots so their brains stop shooting during the end screen
	-- (untag runs the NPC binder Destroy chain), then drop the alive watches.
	for _, rig in self._bots do
		if rig.Parent then
			CollectionService:RemoveTag(rig, Constants.NPC_TAG)
			rig:Destroy()
		end
	end
	self._bots = {}

	BaseMode.Stop(self) -- _maid:DoCleaning drops the Died/leave connections
	table.clear(self._alive)
	self._aliveCount = 0
end

return LastManStanding
