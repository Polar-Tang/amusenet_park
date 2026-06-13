local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CooldownController = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.CooldownController)
local EffectTypes = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectTypes)
local BaseAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Abilities.BaseAbility)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local castRays = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.castRays)
local drawRayResults = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.drawRayResults)
local getRayDirections = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getRayDirections)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Server.types.weaponTypes)

local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)

local CombatConfig = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.CombatConfig)
local CameraUtils = require(ReplicatedStorage.Shared.utils.CameraUtils)

export type AttackDistanceAbilityType = weaponTypes.AttackDistanceAbilityCLient
export type construnctor = weaponTypes.BaseAbilityConstructor
export type hitDetection = weaponTypes.hitDetection
export type HitEffectContract = EffectTypes.HitEffectContract

local MOVEMENT_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,

	-- Arrow keys
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,

	[Enum.KeyCode.Thumbstick1] = true,
	[Enum.KeyCode.DPadUp] = true,
	[Enum.KeyCode.DPadDown] = true,
	[Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.DPadRight] = true,
}

-- The default mobile movement thumbstick (DynamicThumbstick) lives on the LEFT of
-- the screen and does NOT set gameProcessed, so a `gameProcessed == false` touch is
-- not enough to tell "panning the camera" from "moving the character": the move
-- finger reads as a camera pan and suspends the auto-aim lock, so auto-aim drops the
-- instant the player walks. Mirror MobilePeephole's convention -- only a touch that
-- begins on the right (camera) side counts as a manual pan; the left-side move finger
-- is ignored, so auto-aim keeps tracking while the player moves.
local CAMERA_PAN_MIN_X_FRACTION = 0.4

local function isAnyMovementKeyDown(): boolean
	for keyCode in MOVEMENT_KEYS do
		if UserInputService:IsKeyDown(keyCode) then
			return true
		end
	end
	return false
end

-- Auto-aim is only for players who can't freely turn the camera while firing:
-- a thumb is pinned to the shot button (touch) or aiming with a stick (gamepad).
-- Gate on the *current* input type so a PC with a controller plugged in still
-- aims normally with the mouse.
local function isAssistedInput(): boolean
	local lastInput = UserInputService:GetLastInputType()
	return lastInput == Enum.UserInputType.Touch or lastInput.Name:match("^Gamepad") ~= nil
end

local AttackDistanceAbility = setmetatable({}, BaseAbility)
AttackDistanceAbility.__index = AttackDistanceAbility

function AttackDistanceAbility.new(config: construnctor)
	local self = setmetatable(BaseAbility.new(config), AttackDistanceAbility)
	self._lastAttackID = 0

	self.attackType = config.attackType
	self.player = Players:GetPlayerFromCharacter(self.character)

	-- NPC support. NPCs equip through the same client Armed context (their
	-- brain runs on this client, see NPCClient), so this ability is also
	-- instanced for characters the local player does NOT control. Everything
	-- that reads input devices or drives the camera stack must stay
	-- local-owner-only; the NPC instead aims through `customCamera`, a
	-- Camera-shaped CFrame holder its AttackController points at the target
	-- before each Execute (see SetCustomCamera).
	self._isLocalOwner = self.player == Players.LocalPlayer
	self.customCamera = config.customCamera

	self._lastShotTimestamp = 0
	self._recoilRestoreCFrame = nil
	self._recoilTimeoutThreshold = 0.01
	self._recoilCooldownController = CooldownController.new(self.character, self._serviceBag)
	self._recoilResetConnection = nil

	self.attackRow = 0

	-- Continuous-fire state. Firing runs while EITHER the shot button is held
	-- (`_fireButtonHeld`, PC mouse + mobile tap) OR the always-on auto-aim scan
	-- has a target locked (`_fireAimLocked`, touch/gamepad). `_firing` guards the
	-- single shared fire loop so the two trigger sources can't stack into a
	-- double-fire. `_aimAssistActive` mirrors `_fireAimLocked` and is read by
	-- `_shot` to suppress recoil while the hard lock owns the camera.
	self._fireButtonHeld = false
	self._fireAimLocked = false
	self._firing = false
	self._aimAssistActive = false

	self._playerMoved = false

	-- Touch points the player is using to manually pan the camera (mobile).
	-- The auto-aim hard lock yields while any of these is active so the drag
	-- isn't fighting the lock (otherwise the lock freezes the angle while the
	-- pan still orbits the camera position around the character). Keyed by the
	-- InputObject so a second thumb on the fire button — which arrives as a
	-- SEPARATE, gameProcessed touch — never clears a real world-drag.
	self._dragTouches = {}

	-- Everything below is local-player-only runtime: UserInputService
	-- listeners, the m1Hold mirror and the camera-lerp mutex have no meaning
	-- for an NPC-owned instance (its fire trigger is the Attacking state).
	if not self._isLocalOwner then
		return self :: AttackDistanceAbilityType
	end

	-- iF PLAYER MOVES THE MOUSE(SO CAMERA) COMPLETLY STOPS THE LERPING
	self._inputConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self._playerMoved = true

			_G.CurrentCameraHandler:StopLerpCamera()
		end
	end)
	self._maid:GiveTask(self._inputConnection)

	-- Character movement (WASD) also counts as "player moved" so the recoil
	-- restore lerp is skipped if the player walks during the cooldown window.
	self._movementBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if MOVEMENT_KEYS[input.KeyCode] then
			self._playerMoved = true
		end
	end)
	self._maid:GiveTask(self._movementBeganConnection)

	-- Only clear the flag when EVERY movement key is released — releasing one
	-- of two held keys (e.g. W+D → release D) must keep _playerMoved true.
	self._movementEndedConnection = UserInputService.InputEnded:Connect(function(input)
		if MOVEMENT_KEYS[input.KeyCode] and not isAnyMovementKeyDown() then
			self._playerMoved = false
		end
	end)
	self._maid:GiveTask(self._movementEndedConnection)

	-- Manual camera pan detection (mobile). A touch on empty world arrives with
	-- `gameProcessed == false`; a touch the player puts on a UI button (the fire
	-- button, ability buttons, …) is sunk by the GUI and arrives with
	-- `gameProcessed == true`. Tracking only the former is what lets us suspend
	-- the auto-aim lock while the player pans WITHOUT the fire button ever
	-- counting as "the player grabbed the camera" — the exact false-positive of
	-- disabling auto-aim on a bare TouchBegan.
	self._dragBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Touch or gameProcessed then
			return
		end
		
		if CameraUtils.isMovementTouch(input) then
			return
		end
		self._dragTouches[input] = true
	end)
	self._maid:GiveTask(self._dragBeganConnection)

	self._dragEndedConnection = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		-- Clearing a button touch we never tracked is a harmless no-op.
		self._dragTouches[input] = nil
	end)
	self._maid:GiveTask(self._dragEndedConnection)

	self:_setupContinuousFireObservable()

	return self :: AttackDistanceAbilityType
end

function AttackDistanceAbility._resolveWeaponGrip(
	self: AttackDistanceAbilityType,
	strategyName: string,
	methodName: string,
	model: Model
)
	local weaponStats = CombatConfig:getweapon(strategyName)
	local fn = weaponStats[methodName]

	assert(typeof(fn) == "function", "Invalid weapon grip method")

	return fn(model)
end

-- The shot button only flips the manual fire-trigger flag now; acquisition is
-- handled independently by the always-on scan in `:Start`. Both feed the single
-- shared fire loop through `_updateFire`.
function AttackDistanceAbility._setupContinuousFireObservable(self: AttackDistanceAbilityType)
	local bool: BoolValue = Players.LocalPlayer:FindFirstChild("m1Hold")

	local m1Con: RBXScriptConnection
	m1Con = bool.Changed:Connect(function()
		-- Mirror the button state both ways: on release `_fireButtonHeld` must
		-- go back to false so the fire loop's terminator (which checks
		-- `_fireButtonHeld or _fireAimLocked`) can stop it. `_updateFire` only
		-- (re)starts the loop when a trigger is active, so a release call is a
		-- harmless no-op beyond flipping the flag.
		self._fireButtonHeld = bool.Value
		self:_updateFire()
	end)
	self._maid:GiveTask(m1Con)
end

-- Always-on auto-aim scan. Created on weapon equip (cascaded from
-- AbstractStrategy:Start), NOT gated on the fire button: the scan continuously
-- hunts for a target and, on assisted input, target acquisition is what starts
-- continuous fire — the inverse of the old "hold to fire, then assist" flow.
-- Throttled to AIM_ASSIST_SCAN_INTERVAL because the line-of-sight raycasts are
-- expensive; the LerpCamera lock still smooths every render frame in between.
function AttackDistanceAbility.Start(self: AttackDistanceAbilityType)
	-- NPC-owned instances skip the scan: target acquisition is the NPC
	-- TargetController's job, and the camera lock would fight the player's
	-- own camera stack.
	if not RunService:IsClient() or not self._isLocalOwner then
		return
	end

	debug.profilebegin("AimAssistant")
	local accumulated = 0
	self._maid._aimAssistConn = RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < Constants.AIM_ASSIST_SCAN_INTERVAL then
			return
		end
		accumulated = 0
		self:_aimAssistTick()
	end)

	-- Releasing the lock is itself a maid task, so it runs on ability Destroy
	-- (DoCleaning) too — the camera never stays locked on a stale target if the
	-- weapon is torn down mid-track.
	self._maid._aimAssistRelease = function()
		self._fireAimLocked = false
		self._aimAssistActive = false
		self._aimAssistLostAt = nil
		local cameraHandler = _G.CurrentCameraHandler
		if cameraHandler and cameraHandler.StopTrackAim then
			cameraHandler:StopTrackAim()
		end
	end
	debug.profileend()

end

-- NPC aim hook: the simulated camera `_shot` fires from instead of
-- workspace.CurrentCamera. Any object with a world-space `.CFrame` works (the
-- NPC AttackController hands over an unparented Camera instance it re-aims at
-- the target before every Execute).
function AttackDistanceAbility.SetCustomCamera(self: AttackDistanceAbilityType, camera: Camera?)
	self.customCamera = camera
end

-- True while the player is manually panning the camera with a world touch.
-- Auto-aim suspends its lock while this holds so the pan reads as normal manual
-- camera control instead of orbiting against a frozen aim.
function AttackDistanceAbility._hasManualCameraDrag(self: AttackDistanceAbilityType): boolean
	return next(self._dragTouches) ~= nil
end

-- One scan tick: drive the camera lock and decide whether a target is acquired.
-- Auto-aim is only for players who can't freely turn the camera while firing
-- (touch / gamepad). If the input is not assisted -- OR the player is currently
-- panning the camera by hand -- we never raycast; if we were locked when that
-- happened (input switched away, controller unplugged mid-track, or the player
-- grabbed the camera) we release the lock once so it doesn't stay frozen on the
-- target while the player drags.
function AttackDistanceAbility._aimAssistTick(self: AttackDistanceAbilityType)
	local locked = false
	if isAssistedInput() and not self:_hasManualCameraDrag() then
		locked = self:_applyAutoAim()
	elseif self._fireAimLocked then
		local cameraHandler = _G.CurrentCameraHandler
		if cameraHandler and cameraHandler.StopTrackAim then
			cameraHandler:StopTrackAim()
		end
		self._aimAssistLostAt = nil
	end

	self._fireAimLocked = locked
	self._aimAssistActive = locked
end

-- Single fire loop shared by the button and the acquisition triggers. Idempotent
-- via `_firing`, and the loop self-terminates the moment neither trigger is
-- active, so `_updateFire` only has to (re)start it.
function AttackDistanceAbility._startContinuousFire(self: AttackDistanceAbilityType)
	if self._firing then
		return
	end
	self._firing = true

	local thread
	thread = function()
		task.delay(self._cooldown, function()
			-- Either trigger may drop while the shot is scheduled.
			if not (self._fireButtonHeld) then
				self._firing = false
				return
			end
			self:Execute()
			self._maid.fireThread = thread
			thread()
		end)
	end

	thread()
end

function AttackDistanceAbility._updateFire(self: AttackDistanceAbilityType)
	if self._fireButtonHeld or self._fireAimLocked then
		self:_startContinuousFire()
	end
end

function AttackDistanceAbility._isContinuousShot(self: AttackDistanceAbilityType, timestamp: number)
	local last = self._lastShotTimestamp
	local threshold = 0.1
	local cooldown = self._cooldown
	return last > 0 and timestamp - last <= (cooldown + threshold)
end

function AttackDistanceAbility._restoreRecoil(self: AttackDistanceAbilityType)
	local cameraHandler = _G.CurrentCameraHandler
	-- Reset winds back only the recoiler's own pitch/yaw contribution; the
	-- player's mouse rotation never flowed through it, so this is safe
	-- regardless of _playerMoved (which is kept around, along with
	-- _recoilRestoreCFrame, for a future return to the LerpCamera-based
	-- restore — see CameraHandlerBase:LerpCamera).
	if cameraHandler and cameraHandler.resetRecoil then
		cameraHandler:resetRecoil()
	end

	self._recoilRestoreCFrame = nil
	self._playerMoved = isAnyMovementKeyDown()

	if self._recoilResetConnection then
		self._recoilResetConnection:Disconnect()
		self._recoilResetConnection = nil
	end
	local controller = self._recoilCooldownController:getCD()
	if controller then
		-- reset optional controller to let next shooting cycle recreate
		-- controller cancellation performed by its own model end state
	end
end

function AttackDistanceAbility._createRecoilStrike(self: AttackDistanceAbilityType)
	self._recoilCooldownController:init(self._cooldown + 0.15)
	task.defer(function()
		local c = self._recoilCooldownController:getCD()
		if not c then
			return
		end
		if self._recoilResetConnection then
			self._recoilResetConnection:Disconnect()
		end
		self._recoilResetConnection = c.Done:Connect(function()
			-- The connection may fire even when the armed in unequip
			if self._restoreRecoil then 
				self:_restoreRecoil()
				
			end
		end)
		-- self._maid:GiveTask(self._recoilCooldownController)
	end)
end

function AttackDistanceAbility._scheduleRecoilReset(self: AttackDistanceAbilityType)
	local controller = self._recoilCooldownController:getCD()
	if not controller then
		self:_createRecoilStrike()
	else
		if self._cooldown == 3 then
			print()
		end
		self._recoilCooldownController:ResetTo(self._cooldown + 0.1)
	end
end

function AttackDistanceAbility.SetAttributes(self: AttackDistanceAbilityType)
	local CHAR = self.character
	local HUM = self.humanoid

	CHAR:SetAttribute("Attacking", true)
	CHAR:SetAttribute("Swing", true)

	HUM.WalkSpeed = 7
	HUM.JumpHeight = 0
end

function AttackDistanceAbility.UnsetAttributes(self: AttackDistanceAbilityType)
	local CHAR = self.character
	local HUM = self.humanoid

	CHAR:SetAttribute("Attacking", false)
	CHAR:SetAttribute("Swing", false)

	HUM.WalkSpeed = 16
	HUM.JumpHeight = 6.5
end

function AttackDistanceAbility._shot(self: AttackDistanceAbilityType)
	local spread = self.weapon_stats.spread
	local raysPerShot = self.weapon_stats.raysPerShot
	local range = self.weapon_stats.range
	local rayRadius = self.weapon_stats.rayRadius

	local now = Workspace:GetServerTimeNow()

	-- Any attempt to compute the camera cframe via camera handler will be different of the actual camera cframe write because camera effects use dt based in os.clock() and they will be computed at differents times of the frame causing cframe mismathing
	-- NPCs fire from their simulated camera (SetCustomCamera) instead.
	local camera = self.customCamera or workspace.CurrentCamera
	local origin = camera.CFrame

	-- While the continuous auto-aim lock owns the camera (mobile/gamepad firing),
	-- the recoil kick + restore-lerp mutex is skipped entirely: the Heartbeat
	-- track is what aims the camera, and recoil is intentionally hidden (the
	-- chosen "hard lock"). The shot still fires from `origin` below.
	-- NPC-owned instances skip it too: there is no real camera to kick.
	if self._isLocalOwner and not self._aimAssistActive then
		-- mutex: a fired shot ends any in-flight lerp before kicking recoil
		if _G.CurrentCameraHandler then
			_G.CurrentCameraHandler:StopLerpCamera()
		end

		self:recoil()

		if not self:_isContinuousShot(now) then
			self._recoilRestoreCFrame = origin

			self:_createRecoilStrike()
			self.attackRow = 1
		else
			self.attackRow += 1
			self:_scheduleRecoilReset()
		end

		-- Update restore point if player moved camera during shot
		if self._playerMoved then
			self._recoilRestoreCFrame = origin
			-- Re-derive from physical key state instead of blindly setting false:
			-- InputBegan only fires once per press, so a still-held movement key
			-- would otherwise be lost until release+repress.
			self._playerMoved = isAnyMovementKeyDown()
		end
	end
	self._lastShotTimestamp = now

	local rayDirections = getRayDirections(origin, raysPerShot, math.rad(spread), now)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end

	-- getCharacterActor returns the real Player when there is one; for NPCs it
	-- is the Player-shaped stand-in castRays/canPlayerDamageHumanoid accept.
	local rayResults = castRays({player = getCharacterActor(self.character), origin = origin.Position, directions= rayDirections, radius = rayRadius})
	-- Rather than passing the entire table of rayResults to the server, we'll pass the shot origin and a list of tagged humanoids.
	-- The server will then recalculate the ray directions from the origin and validate the tagged humanoids.
	-- Strings are used for the indices since non-contiguous arrays do not get passed over the network correctly.
	-- (This may be non-contiguous in the case of firing a shotgun, where not all of the rays hit a target)
	local tagged = {}
	for index, rayResult in rayResults do
		if rayResult.taggedHumanoid then
			tagged[tostring(index)] = {
				Humanoid = rayResult.taggedHumanoid,
				limb = rayResult.limb,
			}
		end
	end
	-- `npcChar` tells AttckInvoker to execute on the NPC's server Weapon
	-- context instead of the firing player's (only honored for NPC-tagged
	-- models). Nil for player-owned instances, keeping the payload unchanged.
	ReplicatedStorage.Shared.RemoteEvents.Swing:FireServer(
		Enum.UserInputType.MouseButton1,
		{ timestamp = now, tagged = tagged, origin = origin, npcChar = if self.player then nil else self.character }
	)

	drawRayResults(origin.Position, rayResults)
end

local random = Random.new()
function AttackDistanceAbility.recoil(self: AttackDistanceAbilityType)
	local recoilMin = self.weapon_stats.recoilMin
	local recoilMax = self.weapon_stats.recoilMax

	local xDif = recoilMax.X - recoilMin.X
	local yDif = recoilMax.Y - recoilMin.Y
	local x = recoilMin.X + random:NextNumber() * xDif
	local y = recoilMin.Y + random:NextNumber() * yDif

	local recoil = Vector2.new(math.rad(-x), math.rad(y))
	local rise = self.weapon_stats.recoilRise

	local cameraHandler = _G.CurrentCameraHandler
	if cameraHandler and cameraHandler.recoil then
		cameraHandler:recoil(recoil, rise)
	end
end

-- Dry-fire gate, mirroring the server's authoritative check in
-- RangeAttack.Execute. The Tool attributes are the shared ammo store (every
-- ability holds a private clone of weapon_stats, so they could never share a
-- counter). nil-tolerant: a Tool without the attribute (not yet replicated,
-- or a non-gun) never blocks.
function AttackDistanceAbility._canShoot(self: AttackDistanceAbilityType): boolean
	local tool = self._tool
	if not tool then
		return true
	end
	if tool:GetAttribute(Constants.RELOADING_ATTRIBUTE) then
		return false
	end
	local ammo = tool:GetAttribute(Constants.AMMO_ATTRIBUTE)
	return ammo == nil or ammo > 0
end

function AttackDistanceAbility.Execute(self: AttackDistanceAbilityType, params)
	local CHAR = self.character
	local frontenShit = params

	if not self.special_attack then
		if CHAR:GetAttribute("Attacking") or CHAR:GetAttribute("Swing") or CHAR:GetAttribute("IsDefending") then
			return
		end
	end

	if not self:_canShoot() then
		-- Auto-reload on empty: dispatch through the weapon context by key —
		-- the same path InputManager/MobileButtons use — so this ability never
		-- holds a reference to the reload ability. ReloadAbilityClient's own
		-- gates (cooldown + `_reloading` attribute) make hammering this from
		-- the continuous-fire loop a no-op. Works for NPC-owned instances too:
		-- `_weaponHandler` is that character's Armed context on this client.
		local tool = self._tool
		if tool and not tool:GetAttribute(Constants.RELOADING_ATTRIBUTE) then
			self._weaponHandler:Execute(Constants.KEYBOARD_RELOAD_KEY_CODE)
		end
		return
	end

	if self:GetCD() then
		return
	end
	-- start attack
	self:StartCD()

	local preAnimFx = (params and params.preAnimFx) or self.preAnimFx
	if preAnimFx then
		preAnimFx(self, frontenShit)
	end

	-- Schedule the shot to happen at the very begin of the next frame so workspace.Camera is the last actual cframe because any attemp to read it from the handler will mismatch the final cframe due to the Spring internal clock
	debug.profilebegin("RangeShoot")
	task.defer(function()
		self:_shot()
	end)
	debug.profileend()


	local postAnim = (params and params.post_anim) or self.post_anim
	if postAnim then
		postAnim(self)
	end
end

return AttackDistanceAbility
