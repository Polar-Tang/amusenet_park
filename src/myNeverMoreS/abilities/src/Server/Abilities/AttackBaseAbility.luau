local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EffectTypes = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectTypes)
local hitTouchTemplate = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.hitTouchTemplate)
local canPlayerDamageHumanoid =
	require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.canPlayerDamageHumanoid)
local getCharacterActor = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.getCharacterActor)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Server.types.weaponTypes)

export type AttackBaseAbility = weaponTypes.AttackBaseAbility
export type construnctor = weaponTypes.BaseAbilityConstructor
export type hitDetection = weaponTypes.hitDetection
export type HitEffectContract = EffectTypes.HitEffectContract

local require = require(script.Parent.loader).load(script)

local HitboxResponseRemote = ReplicatedStorage.Shared.RemoteEvents.HitboxResponseRemote
local BaseAbility = require("BaseAbility")
local Maid = require("Maid")
local Promise = require("Promise")
local CombatConfig = require("CombatConfig")

local AttackBaseAbility = setmetatable({}, BaseAbility)
AttackBaseAbility.__index = AttackBaseAbility

function AttackBaseAbility.new(config: construnctor)
	local self = setmetatable(BaseAbility.new(config), AttackBaseAbility)
	self._lastAttackID = 0
	self.attackType = config.attackType
	-- Real Player when one owns the character; the Player-shaped stand-in for NPC
	-- rigs, so the friendly-fire gate in PromiseHit works for both (matches
	-- RangeAttack). Players:GetPlayerFromCharacter would be nil for NPCs and make
	-- canPlayerDamageHumanoid NPE on player.Character.
	self.player = getCharacterActor(self.character)

	return self :: AttackBaseAbility
end

function AttackBaseAbility._resolveWeaponGrip(
	self: AttackBaseAbility,
	strategyName: string,
	methodName: string,
	model: Model
)
	local weaponStats = CombatConfig:getweapon(strategyName)
	local fn = weaponStats[methodName]

	assert(typeof(fn) == "function", "Invalid weapon grip method")

	return fn(model)
end

function AttackBaseAbility._createScopedPromise(self: AttackBaseAbility, detectionInfo: hitDetection)
	local scopeMaid = Maid.new()

	local PromiseTask = Promise.new(function(resolve, reject)
		local weaponBinder = self._serviceBag:GetService(_G.BinderProvider):Get("Armed")
		local weapon: weaponTypes.WeaponContext = weaponBinder:Get(self.character)

		if not weapon then
			reject("Weapon not found")

			return
		end

		-- Register this promise
		weapon:RegisterHitboxPromise({
			attackID = detectionInfo.attackID,
			resolve = resolve,
			reject = reject,
			scopeMaid = scopeMaid,
			delay_cb_number = detectionInfo.delay_cb_number or 0.5,
			attackType = self.attackType,
		})

		-- Fire to client to start detection
		local attacker_player = Players:GetPlayerFromCharacter(self.character)
		HitboxResponseRemote:FireClient(attacker_player, detectionInfo)
		-- change this to a generic callback, the specific attacks do the roll_vfx thing
		if detectionInfo.delay_cb then
			local PromiseRollVfx = Promise.delay(detectionInfo.delay_cb_number or 0.5, function(resolve, reject)
				detectionInfo.delay_cb()
			end)
			scopeMaid:GiveTask(PromiseRollVfx)
		end

		local timeOutPromise = Promise.delay(2, function()
			weapon:RejectHitboxPromise(detectionInfo.attackID, "timeout")
		end)
		scopeMaid:GiveTask(timeOutPromise)
	end):Catch(function(err)
		if err == "timeout" then
			-- No hit detected, still play VFX

			-- Return nil to indicate miss
			return nil, nil
		else
			-- Other error, re-throw
			error(err)
		end
	end)
	return PromiseTask, scopeMaid
end

function AttackBaseAbility.SetAttributes(self: AttackBaseAbility)
	local CHAR = self.character
	local HUM = self.humanoid

	CHAR:SetAttribute("Attacking", true)
	CHAR:SetAttribute("Swing", true)

	HUM.WalkSpeed = 7
	HUM.JumpHeight = 0
end

function AttackBaseAbility.UnsetAttributes(self: AttackBaseAbility)
	local CHAR = self.character
	local HUM = self.humanoid

	CHAR:SetAttribute("Attacking", false)
	CHAR:SetAttribute("Swing", false)

	HUM.WalkSpeed = 16
	HUM.JumpHeight = 6.5
end

function AttackBaseAbility.PromiseHit(
	self: AttackBaseAbility,
	hitDetection: weaponTypes.hitDetection,
	hitEffect: HitEffectContract,
	params: any
)
	-- I'm sure if this work for aoe, it does resolve in the first target
	self:_createScopedPromise(hitDetection):Then(function(hits)
		if hits == "timeout" then
			return
		elseif hits and next(hits) then
			if params and params.after_hit then
				params.after_hit(self, {
					vfxs = hitDetection.VFXS,
					hits = hits,
				})
			end
			for _, hitData in ipairs(hits) do
				-- Friendly-fire gate (no team killing) — same rule the gun path
				-- enforces through validateTag. Skip a target the attacker can't
				-- damage so the client can't report a teammate hit. A teamless
				-- attacker/defender always passes (non-team modes untouched).
				local targetHumanoid = hitData.target and hitData.target:FindFirstChildOfClass("Humanoid")
				if targetHumanoid and not canPlayerDamageHumanoid(self.player, targetHumanoid) then
					continue
				end
				-- if this resolve by the client the hitTouch is activated, it calls weapon:OnIncomming attack, and that uses EffectService:Apply(hit_effect_data)
				hitTouchTemplate(hitEffect, hitData.target, hitData.hitPart, self._serviceBag)
			end
		end
	end)
end

function AttackBaseAbility.Execute(self: AttackBaseAbility, params)
	local CHAR = self.character
	local frontenShit = params

	if not self.special_attack then
		if CHAR:GetAttribute("Attacking") or CHAR:GetAttribute("Swing") or CHAR:GetAttribute("IsDefending") then
			return
		end
	end

	if self:GetCD() then
		return
	end
	-- start attack
	self:StartCD()
	--Settin attr
	self:SetAttributes()

	self:_countAttack()

	self.attackId = self:_GenerateAttackID()

	local preAnimFx = (params and params.preAnimFx) or self.preAnimFx
	if preAnimFx then
		preAnimFx(self, frontenShit)
	end

	local animHandler = self._animHandler
	local getAnimName = (params and params.get_anim_name) or self.get_anim_name
	local animName = (getAnimName and getAnimName(self)) or self._animName

	self.animationTrack = animHandler:LoadAnimation(true, animName)

	-- local hit_effect_data = self.hit_effect_data -- rembember to use this as an attirbute
	local hitFx = function(animation, param)
		local createHitboxes = (params and params.createHitboxes) or self.createHitboxes
		assert(createHitboxes, "Missing createHitboxes callback on ability")
		local hitInfo = createHitboxes(self, frontenShit, animation, param)
		local cb

		local hitboxes = hitInfo.hitboxes
		local hit_effect_data: HitEffectContract = table.clone(hitInfo.hit_effect_data)
		hit_effect_data["attackId"] = self.attackId
		hit_effect_data["attacker"] = self.character

		local vfxs = hitInfo.vfxs

		if self.delay_cb then
			cb = self.delay_cb(self, vfxs)
		elseif hitInfo.endUpFx then
			self["after_hit"] = hitInfo.endUpFx
			cb = hitInfo.endUpFx
		end
		-- I'm sure if this work for aoe, it does resolve in the first target
		self:PromiseHit({
			attackID = self.attackId,
			Attacker = self.character,
			hitboxes = hitboxes,
			VFXS = vfxs,
			lifetime = self.life_time,
			delay_cb = cb,
			delay_cb_number = self.delay_cb_number or 0.1,
		}, hit_effect_data, params)
	end
	animHandler:OnSignal({
		callback = hitFx,
		animationName = animName,
		animationEventName = "Hit",
		override = true,
	})
	local postAnim = self.post_anim
	if postAnim then
		postAnim(self)
	end
end


return AttackBaseAbility
