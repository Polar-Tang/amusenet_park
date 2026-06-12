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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)

local BaseMode = {}
BaseMode.__index = BaseMode

export type BaseMode = typeof(setmetatable(
	{} :: {
		config: gameModeTypes.ModeConfig,
		_deps: gameModeTypes.GameModeDeps?,
		_maid: any,
	},
	BaseMode
))

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

function BaseMode.onCharacterAdded(self: BaseMode, _char: Model, _player: Player?) end

function BaseMode.onKill(self: BaseMode, _attackerChar: Model, _defenderChar: Model) end

function BaseMode.Destroy(self: BaseMode)
	self:Stop()
end

return BaseMode
