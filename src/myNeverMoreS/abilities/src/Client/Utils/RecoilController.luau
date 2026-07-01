--[=[
	@class RecoilController

	Owns the camera-recoil lifecycle for a ranged ability: the per-shot kick
	(a random pitch/yaw drawn from `weapon_stats`) and the wind-back state
	machine that schedules the recoil reset a cooldown after the player stops
	firing.

	Extracted from `RangeAttackClient` so the ability only has to announce "a
	shot just landed" (`HandleShot`) while the recoil bookkeeping -- the
	`CooldownController`, the reset connection, the continuous-burst counter and
	the restore-point -- lives here, splitting that responsibility out of the
	already large attack ability.

	Built local-owner-only: an NPC-owned ability never kicks a real camera, so
	it never constructs one (see `RangeAttackClient.new`).
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CooldownController = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.CooldownController)

local RecoilController = {}
RecoilController.__index = RecoilController

export type RecoilConfig = {
	character: Model,
	serviceBag: any,
	-- Ranged weapon stats clone (recoilMin / recoilMax / recoilRise).
	weaponStats: any,
	-- The ability's fire cooldown; drives the wind-back strike timing.
	cooldown: number,
	-- Predicate so `Restore` can re-derive "is the player still walking" from
	-- physical key state without owning the movement-key table (that stays with
	-- the ability's input listeners).
	isMovementKeyDown: () -> boolean,
}

export type RecoilController = {
	_character: Model,
	_weaponStats: any,
	_cooldown: number,
	_isMovementKeyDown: () -> boolean,
	_cooldownController: any,
	_resetConnection: RBXScriptConnection?,
	_lastShotTimestamp: number,
	-- Kept only for a future return to the LerpCamera-based restore (the recoil
	-- reset currently winds back through RecoilCamera:Reset directly).
	_restoreCFrame: CFrame?,
	_attackRow: number,
	_playerMoved: boolean,

	SetPlayerMoved: (self: RecoilController, moved: boolean) -> (),
	HandleShot: (self: RecoilController, origin: CFrame, now: number) -> (),
	NotifyShot: (self: RecoilController, now: number) -> (),
	Kick: (self: RecoilController) -> (),
	Restore: (self: RecoilController) -> (),
	_isContinuousShot: (self: RecoilController, timestamp: number) -> boolean,
	_createStrike: (self: RecoilController) -> (),
	_scheduleReset: (self: RecoilController) -> (),
	Destroy: (self: RecoilController) -> (),
}

local random = Random.new()

function RecoilController.new(config: RecoilConfig): RecoilController
	local self = setmetatable({}, RecoilController)

	self._character = config.character
	self._weaponStats = config.weaponStats
	self._cooldown = config.cooldown
	self._isMovementKeyDown = config.isMovementKeyDown

	self._cooldownController = CooldownController.new(config.character, config.serviceBag)
	self._resetConnection = nil
	self._lastShotTimestamp = 0
	self._restoreCFrame = nil
	self._attackRow = 0
	self._playerMoved = false

	return (self :: any) :: RecoilController
end

-- Mirrors the ability's input listeners: the camera-pan / WASD detectors flip
-- this so a shot fired while the player is moving re-anchors its restore point.
function RecoilController.SetPlayerMoved(self: RecoilController, moved: boolean)
	self._playerMoved = moved
end

-- One shot's camera kick: a random pitch/yaw inside the weapon's recoil
-- envelope, handed to the active camera handler as a rotation impulse.
function RecoilController.Kick(self: RecoilController)
	local stats = self._weaponStats
	local recoilMin = stats.recoilMin
	local recoilMax = stats.recoilMax

	local xDif = recoilMax.X - recoilMin.X
	local yDif = recoilMax.Y - recoilMin.Y
	local x = recoilMin.X + random:NextNumber() * xDif
	local y = recoilMin.Y + random:NextNumber() * yDif

	local recoil = Vector2.new(math.rad(-x), math.rad(y))
	local rise = stats.recoilRise

	local cameraHandler = _G.CurrentCameraHandler
	if cameraHandler and cameraHandler.recoil then
		cameraHandler:recoil(recoil, rise)
	end
end

function RecoilController._isContinuousShot(self: RecoilController, timestamp: number): boolean
	local last = self._lastShotTimestamp
	local threshold = 0.1
	local cooldown = self._cooldown
	return last > 0 and timestamp - last <= (cooldown + threshold)
end

-- Full per-shot sequence (local owner, camera not owned by the auto-aim lock):
-- end any in-flight restore lerp, kick the camera, then either start a fresh
-- recoil strike or extend the running one for a continuous burst.
function RecoilController.HandleShot(self: RecoilController, origin: CFrame, now: number)
	-- mutex: a fired shot ends any in-flight lerp before kicking recoil
	local cameraHandler = _G.CurrentCameraHandler
	if cameraHandler then
		cameraHandler:StopLerpCamera()
	end

	self:Kick()

	if not self:_isContinuousShot(now) then
		self._restoreCFrame = origin
		self:_createStrike()
		self._attackRow = 1
	else
		self._attackRow += 1
		self:_scheduleReset()
	end

	-- Re-anchor the restore point if the player moved the camera during the shot.
	if self._playerMoved then
		self._restoreCFrame = origin
		-- Re-derive from physical key state instead of blindly clearing:
		-- InputBegan only fires once per press, so a still-held movement key
		-- would otherwise be lost until release+repress.
		self._playerMoved = self._isMovementKeyDown()
	end

	self._lastShotTimestamp = now
end

-- Keep the last-shot clock current without kicking the camera. Used while the
-- auto-aim hard lock owns the camera: recoil is intentionally hidden, but the
-- first manual shot after the lock drops must still classify correctly.
function RecoilController.NotifyShot(self: RecoilController, now: number)
	self._lastShotTimestamp = now
end

function RecoilController._createStrike(self: RecoilController)
	self._cooldownController:init(self._cooldown + 0.15)
	task.defer(function()
		local c = self._cooldownController:getCD()
		if not c then
			return
		end
		if self._resetConnection then
			self._resetConnection:Disconnect()
		end
		self._resetConnection = c.Done:Connect(function()
			-- The connection may fire even after the weapon is unequipped.
			if self.Restore then
				self:Restore()
			end
		end)
	end)
end

function RecoilController._scheduleReset(self: RecoilController)
	local controller = self._cooldownController:getCD()
	if not controller then
		self:_createStrike()
	else
		self._cooldownController:ResetTo(self._cooldown + 0.1)
	end
end

function RecoilController.Restore(self: RecoilController)
	local cameraHandler = _G.CurrentCameraHandler
	-- Reset winds back only the recoiler's own pitch/yaw contribution; the
	-- player's mouse rotation never flowed through it, so this is safe
	-- regardless of player movement.
	if cameraHandler and cameraHandler.resetRecoil then
		cameraHandler:resetRecoil()
	end

	self._restoreCFrame = nil
	self._playerMoved = self._isMovementKeyDown()

	if self._resetConnection then
		self._resetConnection:Disconnect()
		self._resetConnection = nil
	end
end

function RecoilController.Destroy(self: RecoilController)
	if self._resetConnection then
		self._resetConnection:Disconnect()
		self._resetConnection = nil
	end
end

return RecoilController
