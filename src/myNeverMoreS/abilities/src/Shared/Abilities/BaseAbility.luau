local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CooldownController = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.CooldownController)
local findAimAssistTarget = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.findAimAssistTarget)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Server.types.weaponTypes)
--CombatConfig
export type BaseAbility = weaponTypes.BaseAbility
-- local SoundService = game:GetService("SoundService")
-- local SoundFolder = SoundService.SFX
-- local WeaponSoundFolder = SoundFolder.Weapons

local require = require(script.Parent.loader).load(script)
local Maid = require("Maid")

local BaseAbility = {}
BaseAbility.__index = BaseAbility

function BaseAbility.new(config: weaponTypes.BaseAbilityConstructor)
	local self = setmetatable(config, BaseAbility)
	self.character = config.character
	self.humanoid = config.character:WaitForChild("Humanoid")
	self.hrp = config.character:WaitForChild("HumanoidRootPart")
	self.CD = false
	self.life_time = config.life_time
	-- self.sound_folder = WeaponSoundFolder[config.tool_name]
	self.weapon_stats = config.weapon_stats
	self.walk_speed_blocking = config.walk_speed_blocking
	self._serviceBag = config._serviceBag
	self._lastAttackID = 0
	self._tool = config.tool

	if RunService:IsServer() then
		self.RagdollService = self._serviceBag:GetService(require("Ragdoll"))
	else
		self.RagdollService = self._serviceBag:GetService(require("RagdollClient"))
	end

	-- BINDERS
	assert(_G.BinderProvider, "Binder Provider not initialized")
	-- Get the animation binder
	local BinderProvider = self._serviceBag:GetService(_G.BinderProvider)
	-- weapon Binder
	local WeaponBinder = BinderProvider:Get("Armed")
	self._weaponHandler = WeaponBinder:Get(self.character)

	self.animNames = config.animNames
	self._animName = config.animNames[1]
	self._endFx = config.endFx
	self._cooldown = config.cooldown

	self._maid = Maid.new()

	-- Animation Binder
	local AnimationBinder = BinderProvider:Get("AnimationHandler")
	
	if AnimationBinder then
		self._animHandler = AnimationBinder:Get(self.character)
	else 
		print()
	end

	return self
end

function BaseAbility.Init(self: BaseAbility, params)
	if params.endFx then
		params.endFx(self)
	end
end

-- function BaseAbility.PlaySound(self: BaseAbility, nameSound: string, lifeTime: number?)
-- 	local dur = lifeTime or 2
-- 	-- print("Playing sound: ", nameSound, debug.traceback())
-- 	local Sound = self.sound_folder[nameSound]:Clone()
-- 	Sound.Parent = self.character:WaitForChild("HumanoidRootPart")
-- 	Sound:Play()
-- 	Debris:AddItem(Sound, dur)
-- end

function BaseAbility.resetAtt(self: BaseAbility)
	if not self.character:GetAttribute("IsBlocking") then
		self.humanoid.WalkSpeed = 14
		self.humanoid.JumpHeight = 6.5
	end
	if self.type == "Attack" then
		self.character:SetAttribute("Attacking", false)
		self.character:SetAttribute("Swing", false)
	elseif self.type == "Defense" then
		self.character:SetAttribute("IsDefending", false)
	elseif self.type == "Others" then
		self.character:SetAttribute("Swing", false)
		self.character:SetAttribute("Attacking", false)
	elseif self.type == "Movement" then
		self.character:SetAttribute("Swing", false)
	else
		print("Uknown data.type ", self.type)
	end
end

function BaseAbility.StartCD(self: BaseAbility)
	self.CD = true
	task.delay(self._cooldown, function()
		self.CD = false
	end)
end

function BaseAbility.InitCDInst(self: BaseAbility)
	self._comboController = CooldownController.new(self.character, self._serviceBag)
end

function BaseAbility._countAttack(self: BaseAbility)
	self._lastAttackID += 1
end

function BaseAbility._GenerateAttackID(self: BaseAbility)
	-- Simple incrementing ID or use HttpService:GenerateGUID()
	local id = self.player.UserId .. "_" .. self.type .. "_" .. self._lastAttackID
	-- print("id ", id)
	return id
end

function BaseAbility.GetCD(self: BaseAbility)
	return self.CD
end

function BaseAbility.Execute(self: BaseAbility)
	error("Execute must be overridden in subclass")
end

-- ===== Auto-aim (mobile / gamepad, client only) ==========================
-- Continuous aim assist. The owning weapon runs an always-on scan loop (see
-- `RangeAttackClient:Start`) that calls this every scan tick. It re-scans for
-- the best target, drives the camera lock, and reports whether a target is
-- currently locked so the caller can gate continuous fire on acquisition.
-- Returns `true` while a target is locked (including the brief loss grace) and
-- `false` once the lock has been released. No-op / `false` on the server.

function BaseAbility._applyAutoAim(self: BaseAbility): boolean
	local cameraHandler = _G.CurrentCameraHandler
	if not cameraHandler or not cameraHandler.TrackAim then
		return false
	end

	local camera = Workspace.CurrentCamera
	local player = self.player or Players:GetPlayerFromCharacter(self.character)
	local range = (self.weapon_stats and self.weapon_stats.range) or Constants.AIM_ASSIST_RANGE_DEFAULT
	local target = findAimAssistTarget(player, camera, range, Constants.AIM_ASSIST_CONE_DEG)
	if not target then
		-- Target missing this frame. Don't release immediately: the scan
		-- flickers (a one-frame missing PrimaryPart), and an instant release
		-- snaps the camera back to the player's manual aim — the lock is only a
		-- mask on the camera stack, the default camera never learned the locked
		-- orientation. Hold the existing lock through a short grace window and
		-- only release once the target has been gone continuously for
		-- AIM_ASSIST_LOSS_GRACE, so brief flickers never cause a snap.
		self._aimAssistLostAt = self._aimAssistLostAt or os.clock()
		if os.clock() - self._aimAssistLostAt >= Constants.AIM_ASSIST_LOSS_GRACE then
			cameraHandler:StopTrackAim()
			return false
		end
		-- Still inside the grace window: keep reporting "locked" so fire and the
		-- camera lock persist through the flicker.
		return true
	end

	self._aimAssistLostAt = nil
	local goal = CFrame.lookAt(camera.CFrame.Position, target.Position)
	-- Pass the target's world position too: the third-person camera needs it to
	-- anchor its position offset on the character->target direction (a physical
	-- quantity), not on the locked camera rotation, which otherwise feeds back
	-- into the camera position and drifts out of alignment while the player moves.
	cameraHandler:TrackAim(goal, Constants.AIM_ASSIST_RESPONSIVENESS, target.Position)
	return true
end

function BaseAbility.Destroy(self: BaseAbility)
	self._maid:DoCleaning()
	setmetatable(self, nil)
	-- self = nil
	-- print("Ability deleted")
end

return BaseAbility
