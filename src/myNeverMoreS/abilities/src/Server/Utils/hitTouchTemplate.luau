local EffectService = require(script.Parent.EffectService)
local EffectTypes = require(script.Parent.EffectTypes)
export type effectHitCtx = EffectTypes.effectHitCtx

return function(hitEffectData, hitTarget, hitPart, serviceBag)
	local parentClass = table.clone(hitEffectData)
	local BinderProvider = serviceBag:GetService(_G.BinderProvider)
	-- weapon Binder
	local WeaponBinder = BinderProvider:Get("Armed")
	local NPCBinder = BinderProvider:Get("NPC")
	--newHitbox.Touched:Connect
	----------------------------------------------------
	local context = {
		Defender = {},
		Attacker = {},
		groundSmash = {},
		Explosion = {},
	}
	local ENEMY_CHAR: Model = hitTarget
	context.Defender.Character = ENEMY_CHAR

	local enemy_hum = ENEMY_CHAR:WaitForChild("Humanoid")

	context.Defender.Humanoid = enemy_hum

	context.strength = parentClass.strength

	local ENEMYHRP = ENEMY_CHAR:FindFirstChild("HumanoidRootPart") or ENEMY_CHAR.PrimaryPart or hitPart

	context.Defender.HRP = ENEMYHRP
	local CHAR = parentClass.attacker
	context.Attacker.Character = CHAR :: Model
	context.Attacker.Humanoid = CHAR:FindFirstChild("Humanoid") :: Humanoid
	local HRP = CHAR:FindFirstChild("HumanoidRootPart") or parentClass.HRP :: BasePart
	context.Attacker.HRP = HRP

	local DIRECTION = (ENEMYHRP.Position - HRP.Position).Unit
	if parentClass.strength and not parentClass.knockback then
		local knockback = DIRECTION * parentClass.strength
		if parentClass.isUpside then
			local sideMultiplier = 5
			local up = Vector3.new(0, parentClass.up, 0) * parentClass.strength
			local forward = DIRECTION * parentClass.strength * sideMultiplier

			context.knockback = forward + up
			-- context.knockback = (DIRECTION * parentClass.strength * sideMultiplier)
			--[[
				15:49:43.528  context.knockback  on Player1 -30.8356876373291, 100, -39.359375  -  Server - hitTouchTemplate:72
				15:49:54.858  context.knockback  on Rig -45.04938507080078, 99.95938873291016, -21.692188262939453  -  Server - hitTouchTemplate:72
				]]
			-- + Vector3.new(0, parentClass.up, 0) * parentClass.strength
		elseif parentClass.strength then
			context.knockback = knockback
		end
	end

	----------------------------------------------------
	-- LAST BUT NOT LEAST, IMPORTANT DATA FROM THE PARENT
	-- Overwrites groundSMash, if it exists it lacks the hit position, only know by this module
	context.id = parentClass.attackId

	local groundSmash = parentClass.groundSmash
	if groundSmash then
		groundSmash.position = ENEMYHRP.Position
	end
	context.hit_position = ENEMYHRP.Position
	context.strikes_hit = parentClass.strikes_hit
	context.groundSmash = groundSmash :: EffectTypes.GroundSmash
	context.damage = parentClass.damage
	context.stunt_time = parentClass.stun_time
	context.serviceBag = serviceBag
	context.ragdoll = parentClass.ragdoll
	context.hitPart = hitPart
	context.Explosion = parentClass.Explosion
	context.hitLock = parentClass.hitLock
	context.hardLock = parentClass.hardLock
	context.VFX = parentClass.VFX
	context.attackId = parentClass.attackId
	context.comeBabe = parentClass.comeBabe

	-- print("parentClass ", parentClass)
	local weaponEnemy = WeaponBinder:Get(ENEMY_CHAR)
	if not weaponEnemy then
		EffectService:Apply(context)

		return
	end
	-- print("context ", context)
	weaponEnemy:OnIncomingAttack(context)
	----------------------------------------------------
	-- Handling the hit blocking
	-- Heavy will be an attribute set by the heavy attack, execute()
	-- CheckInfront will be an utility directly by the weapon
	-- CombatUtils.Blocking could be a weapon method too, self._weapon[strategy].blockig
	--[[
		
		do
			if ENEMY_CHAR:GetAttribute("Parrying") and not Heavy and CombatUtils.CheckInfront(CHAR, ENEMY_CHAR) then
				CombatUtils.Parrying(CHAR, ENEMY_CHAR)
				return
			end
			if ENEMY_CHAR:GetAttribute("IsBlocking") and not Heavy and CombatUtils.CheckInfront(CHAR, ENEMY_CHAR) then
				CombatUtils.Blocking(ENEMY_CHAR, Damage)
				return
			end
			if ENEMY_CHAR:GetAttribute("IsRagdoll") or ENEMY_CHAR:GetAttribute("Iframes") or enemyHum.Health <= 0 then
				return
			end

			if Heavy then
				CHAR:SetAttribute("Combo", 4)
			end
		end
		]]
	------------ CONSTANTS ------------

	--local STRENGTH = 10

	---------------------- HIT: ANIM, DAMAGA ----------------------
	--enemyHrp.CFrame = CFrame.lookAt(enemyHrp.Position, hrp.Position)--makes the enemy look at you, disabled it cuz it doesnt look good lol

	-- PLAY THE HIT FROM THE COMBO
	---- print("Stop animation playing feint")
	---- print("NPCAnimBinder ", NPCAnimBinder)
end
