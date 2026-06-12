
local Debris = game:GetService("Debris")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- COmbat config is a god-table required by server and client as well, but there are modules that shouldn't be required by client
if RunService:IsClient() then
	return {}
end

local Ragdoll = require(ReplicatedStorage.Nevermore.Quenty.ragdoll.Server.Classes.Ragdoll)
local roll_vfx = require(script.Parent.roll_vfx)

local remotes = RS.Shared.RemoteEvents
local VFX_Event: RemoteEvent = remotes.VFX
-- CUstom helpers/services
local ServerScriptService = game:GetService("ServerScriptService")
local QuestHandler = require(ServerScriptService.Server.Quests.QuestHandler)
local EffectTypes = require(script.Parent.EffectTypes)

export type effectHitCtx = EffectTypes.effectHitCtx
-- local stunHandler = require("StunHandlerV2")

local EffectService = {}

function EffectService.SetAttHit(hited)
	hited:SetAttribute("IsBlocking", false)
	hited:SetAttribute("Attacking", false)
	hited:SetAttribute("Swing", false)
	hited:SetAttribute("Parrying", false)
	hited:SetAttribute("IsBlocking", false)
end

local function weldToRoot(rootPart, hrp)
	if not hrp then
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = hrp
	weld.Parent = rootPart
end

--[[
force calculation:
local DIRECTION = (ENEMYHRP.Position - HRP.Position).Unit
local knockback = DIRECTION * parentClass.strength
]]
type gravityLessArgs = {
	parent: Model,
	Pos: Vector3,
}
local function createGravitylessPart(data: gravityLessArgs)
	local partA = Instance.new("Part")
	partA.CanCollide = false
	-- partA.Anchored = true

	partA.Position = data.Pos
	partA.Size = Vector3.new(6, 6, 6)
	partA.Parent = data.parent
	partA.Transparency = 1

	local mass = partA.AssemblyMass

	local vf = Instance.new("VectorForce")
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.new(0, workspace.Gravity * mass, 0)
	vf.Parent = partA

	-- Attachment for AlignPosition
	local attachment = Instance.new("Attachment")
	attachment.Name = "Attachment"
	attachment.Parent = partA
	vf.Attachment0 = attachment
	return partA
end

local function applySpin(enemy: BasePart, angularVel)
	local attachment = enemy:FindFirstChildOfClass("Attachment")

	local av = Instance.new("AngularVelocity")
	av.Attachment0 = attachment
	av.MaxTorque = math.huge
	av.AngularVelocity = angularVel
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = enemy

	Debris:AddItem(av, 0.25)
	Debris:AddItem(attachment, 0.25)
end

local function flyBack(enemy: BasePart, force)
	local offset = enemy.CFrame.RightVector * 2 -- sideways
	enemy:ApplyImpulseAtPosition(force, enemy.Position + offset)

	applySpin(enemy, Vector3.new(20, 0, 0))
end

local removeAnchorStateIfAny = function(context)
	if context.anchorState then
		context.anchorState:Remove()
	end
end

function EffectService._createAttachment(Parent: BasePart | Model, Name: string, properties): Attachment
	local newAttacment = Instance.new("Attachment")
	newAttacment.Name = Name
	newAttacment.Parent = Parent
	if properties then
		if properties.CFrame then
			newAttacment.CFrame = properties.CFrame
		end
	end
	return newAttacment
end

function EffectService:ChangeChildren(
	parent: Model | BasePart,
	childName: string,
	fn: (Model | BasePart, string, any) -> BasePart | Attachment | Model,
	properties
)
	local attachment = parent:FindFirstChild(childName)
	if not attachment then
		attachment = fn(parent, childName, properties)
	end
	return attachment
end

function EffectService._destroyChildren(parent, childName)
	local child = parent:FindFirstChild(childName)
	if child then
		child:Destroy()
	end
end

function EffectService:Apply(context: effectHitCtx)
	assert(context.Attacker, "No 'attacker' on 'effectHitCtx'")
	assert(context.Defender, "No 'defender' on 'effectHitCtx'")
	assert(context.attackId, "No 'attackId' on 'effectHitCtx'")
	assert(context.serviceBag, "No 'serviceBag' on 'effectHitCtx'")

	-- assert(not (context.hardLock and context.comeBabe) , "hardLock and comeBabe are not compatible")

	local effectCtx = {} --Leave a registry of important information needed for another attacks


	local defender_char = context.Defender.Character :: Model
	local defender_humanoid = context.Defender.Humanoid
	local defender_hrp = context.Defender.HRP

	local attacker_char = context.Attacker.Character
	local attacker_humanoid = context.Attacker.Humanoid
	local attacker_hrp = context.Attacker.HRP

	if context.pre_hit then
		context.pre_hit(context)
	end

	if context.ragdoll and context.hitPart then
		removeAnchorStateIfAny(context)

		defender_humanoid:ChangeState(6)
		local RagdollService = context.serviceBag:GetService(Ragdoll)
		RagdollService:Tag(defender_humanoid)

		defender_humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		defender_humanoid.AutoRotate = true
		-- TODO: check use this API for set network nil

		defender_hrp:SetNetworkOwner(nil)
		context.hitPart:SetNetworkOwner(nil)

		task.delay(context.ragdoll.duration, function()
			RagdollService:Untag(defender_humanoid)
			defender_humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			defender_humanoid.AutoRotate = true
			defender_hrp:SetNetworkOwner(nil)
			context.hitPart:SetNetworkOwner(nil)
		end)
	end

	if context.hitLock then
		local forward = context.hitLock.direction or attacker_hrp.Position + (attacker_hrp.CFrame.LookVector * 4)
		-- 	or Vector3.new(attacker_hrp.CFrame.LookVector.X, 0, attacker_hrp.CFrame.LookVector.Z + 1)

		-- if forward.Magnitude < 0.001 then
		-- 	forward = attacker_hrp.CFrame.RightVector
		-- end

		-- forward = forward.Unit
		-- local offsetDistance = 2 or context.hitLock.offset
		-- local targetPosition = attacker_hrp.Position + (forward * offsetDistance) + Vector3.new(-4, 0, 0)
		defender_hrp.Position = forward

		-- context.anchorState:Add(context.hitLock.duration) -- extend time
		-- local lockId = context.attacker:GetDebugId() .. "_HitLock"
		-- self._movementLock:Add(lockId, context.hitLock.duration)

		-- stunHandler.Stun(defender_humanoid, context.hitLock.duration)
	end

	if context.dashing then
		if context.dashing.destroy then
			-- May be destroyed by the lifetime property
			self._destroyChildren(context.Attacker.HRP, "attachmentDash")
			self._destroyChildren(context.Defender.HRP, "attachmentDash")
		elseif context.dashing.direction then
			local lookAt = CFrame.lookAt(attacker_hrp.Position, context.dashing.direction, Vector3.yAxis)

			attacker_humanoid.AutoRotate = false
			task.delay(context.dashing.lifetime, function()
				attacker_humanoid.AutoRotate = true
			end)

			attacker_hrp.CFrame = lookAt
			local attachmentAlignPos = Instance.new("Attachment")
			attachmentAlignPos.Name = "attachmentDash"
			attachmentAlignPos.Visible = true
			attachmentAlignPos.CFrame = lookAt
			attachmentAlignPos.Parent = attacker_hrp

			local alignPos = Instance.new("AlignPosition")
			alignPos.Attachment0 = attachmentAlignPos
			alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
			alignPos.MaxForce = math.huge
			alignPos.MaxVelocity = math.huge
			alignPos.Position = context.dashing.direction
			alignPos.Responsiveness = 5
			alignPos.ApplyAtCenterOfMass = true
			alignPos.Parent = attacker_hrp
			Debris:AddItem(alignPos, context.dashing.lifetime)
			Debris:AddItem(attachmentAlignPos, context.dashing.lifetime)

			--[[
		do
			local attackerAlignOri = Instance.new("AlignOrientation")
			attackerAlignOri.Attachment0 = attachmentAlignPos
			attackerAlignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
			attackerAlignOri.CFrame = lookAt
			-- attackerAlignOri.AlignType = Enum.AlignType.PrimaryAxisLookAt
			-- attackerAlignOri.LookAtPosition = context.dashing.direction

			attackerAlignOri.MaxAngularVelocity = 5000
			attackerAlignOri.MaxTorque = 5000

			attackerAlignOri.PrimaryAxis = attacker_hrp.CFrame.RightVector
			attackerAlignOri.SecondaryAxis = attacker_hrp.CFrame.UpVector --  Vector3.new(0, 1, 0)
			attackerAlignOri.Responsiveness = 10
			attackerAlignOri.Parent = attacker_hrp
			Debris:AddItem(attackerAlignOri, context.dashing.lifetime)
		end
		]]

			do
				local defenderAttachmentAlignPos = Instance.new("Attachment")
				defenderAttachmentAlignPos.Name = "attachmentDash"
				defenderAttachmentAlignPos.Visible = true
				defenderAttachmentAlignPos.Parent = defender_hrp

				local defenderAlignPos = Instance.new("AlignPosition")
				defenderAlignPos.Attachment0 = defenderAttachmentAlignPos
				defenderAlignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
				defenderAlignPos.MaxForce = math.huge
				defenderAlignPos.MaxVelocity = math.huge
				defenderAlignPos.Position = context.dashing.direction
				defenderAlignPos.ForceLimitMode = Enum.ForceLimitMode.PerAxis
				defenderAlignPos.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
				-- testPart({Position = endPos, Size = Vector3.new(5,5,5)})
				defenderAlignPos.Responsiveness = 5
				defenderAlignPos.ApplyAtCenterOfMass = true
				defenderAlignPos.ForceRelativeTo = Enum.ActuatorRelativeTo.World
				defenderAlignPos.Parent = defender_hrp
				Debris:AddItem(defenderAlignPos, context.dashing.lifetime)
				Debris:AddItem(defenderAttachmentAlignPos, context.dashing.lifetime)
			end
		end
	end

	if context.hardLock then
		-- Attachments
		-- TODO: check use this API for set network nil
		removeAnchorStateIfAny(context)
		-- Create a model with a primaty part about its center

		local motionName = "EnemiesMotion_" .. attacker_char.Name .. "_" .. defender_char.Name
		local enemiesMotion = workspace:FindFirstChild(motionName) or Instance.new("Model")
		effectCtx.weld_two_chars = enemiesMotion
		local newDefenderHealth = defender_humanoid.Health - context.damage

		if context.hardLock.destroy or newDefenderHealth <= 0 then
			attacker_char.Parent = workspace
			defender_char.Parent = workspace
			enemiesMotion:Destroy()
		elseif context.hardLock.direction then
			enemiesMotion.Name = motionName

			local enemiesCenter = (attacker_hrp.Position + defender_hrp.Position) / 2
			local partA = enemiesMotion.PrimaryPart
				or createGravitylessPart({
					parent = enemiesMotion,
					Pos = enemiesCenter,
				})

			enemiesMotion.PrimaryPart = partA

			enemiesMotion.Parent = workspace
			attacker_char.Parent = enemiesMotion
			defender_char.Parent = enemiesMotion
			-- WELD ALL TOGETHER
			weldToRoot(partA, attacker_hrp)
			weldToRoot(partA, defender_hrp)

			local attachmentAlignPos = partA:FindFirstChild("attachmentAlignPos")
			if not attachmentAlignPos then
				attachmentAlignPos = Instance.new("Attachment")
				attachmentAlignPos.Name = "attachmentAlignPos"
				attachmentAlignPos.Parent = partA
			end

			local alignPos = Instance.new("AlignPosition")
			alignPos.Attachment0 = attachmentAlignPos
			alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
			alignPos.MaxForce = math.huge
			alignPos.Position = context.hardLock.direction
			alignPos.ApplyAtCenterOfMass = true
			alignPos.Parent = partA
			Debris:AddItem(alignPos, context.hardLock.lifetime)

			task.delay(1, function()
				attacker_char.Parent = workspace
				defender_char.Parent = workspace
				enemiesMotion:Destroy()
			end)
		end
	end

	if context.comeBabe then
		local atacker_attachment = context.Attacker.Character:FindFirstChild("Grab")
		if not atacker_attachment and context.comeBabe.destroy then
			atacker_attachment:Destroy()
		else
			atacker_attachment = self:ChangeChildren(context.Attacker.Character, "Grab", self._createAttachment)
			local defender_attachment =
				self:ChangeChildren(context.Defender.Character, "Grabbed", self._createAttachment, {
					CFrame = CFrame.new(0, 0, 3),
				})

			local alignPos = Instance.new("AlignPosition")
			alignPos.Attachment0 = defender_attachment --atacker_attachment
			alignPos.Attachment1 = atacker_attachment --defender_attachment

			alignPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
			alignPos.MaxForce = math.huge
			alignPos.MaxVelocity = math.huge
			alignPos.Responsiveness = 200
			alignPos.ApplyAtCenterOfMass = false
			alignPos.Parent = context.Defender.HRP
			Debris:AddItem(alignPos, context.comeBabe.lifetime)
			Debris:AddItem(atacker_attachment, context.comeBabe.lifetime)
			Debris:AddItem(defender_attachment, context.comeBabe.lifetime)
		end
	end

	if context.cutscene then
		local vfx: EffectTypes.VFX = {
			attackId = context.attackId,
			Attacker = attacker_char,
			Defender = defender_char,
			action = "cutscene",
			camera_location = context.cutscene.camera_location,
			destroy = context.cutscene.destroy,
			look_to = context.cutscene.look_to,
		}
		roll_vfx({ vfx })

		if context.cutscene.duration then
			attacker_humanoid.WalkSpeed = 0
			defender_humanoid.WalkSpeed = 0
			task.delay(context.cutscene.duration, function()
				-- WARNING: CODE SMALL HERE, STATE COUPLING
				attacker_humanoid.WalkSpeed = 16
				defender_humanoid.WalkSpeed = 16
			end)
		end
	end

	-- tHIS SHOULD BE A VFX ROLLED BY ROLL_VFX
	-- if context.groundSmash then
	-- 	local GConfig = context.groundSmash

	-- 	DebrisFX:GroundSmash({
	-- 		position = GConfig.position,
	-- 		amount = GConfig.amount,
	-- 		velocity = GConfig.velocity,
	-- 		material = GConfig.material,
	-- 		dust = GConfig.dust,
	-- 		shockwave = GConfig.shockwave,
	-- 		sizeRange = GConfig.sizeRange,
	-- 		lifetime = GConfig.lifetime,
	-- 	})
	-- end

	if context.strikes_hit then
		VFX_Event:FireAllClients("StrikesHit", defender_char)
	end
	-- Decide what to do with strength
	-- local ragdollBinder = serviceBag:GetService(RagdollBindersServer).Ragdoll

	-- local ragdoll = ragdollBinder:Get(humanoid)
	-- if ragdoll then
	-- 	print("Is ragdolled")
	-- 	ragdollBinder:Unbind(humanoid)
	-- else
	-- 	print("Not ragdolled")
	-- 	ragdollBinder:Bind(humanoid)
	-- end
	if context.knockback and context.hitPart then
		removeAnchorStateIfAny(context)
		print("")
		local force = context.knockback
		local mass = defender_hrp.AssemblyMass
		local normalizedForce = force * mass
		flyBack(context.hitPart, normalizedForce)
	end

	if context.damage then
		local wasAlive = defender_humanoid.Health > 0
		defender_humanoid:TakeDamage(context.damage)

		local BinderProvider = context.serviceBag:GetService(_G.BinderProvider)
		local WeaponBinder = BinderProvider:Get("Armed")
		local weaponEnemy = WeaponBinder:Get(attacker_char)
		weaponEnemy:increaseDmgCount(context.damage)
		local countDamage = ReplicatedStorage.Shared.RemoteEvents.countDamage
		countDamage:FireAllClients({
			dmg = context.damage,
			src = defender_hrp,
		})
		weaponEnemy:RegisterAttackEffect(context.attackId, context)

		-- Kill confirmation: this is the only place lethal damage lands, so it is
		-- the one authoritative "attacker killed defender" signal. The killer is
		-- sent as a character Model because it may be an NPC rig (getCharacterActor
		-- fake players carry the rig in .Character, same field as real players).
		-- The dead client fabricates the killer-cam CFrame from that Model's Head —
		-- neither a player's Camera nor the NPC brain's unparented Camera replicate,
		-- and the NPC aims from its Head anyway (AttackController.Shoot).
		if wasAlive and defender_humanoid.Health <= 0 then
			local defenderPlayer = Players:GetPlayerFromCharacter(defender_char)
			if defenderPlayer then
				remotes.PlayerDied:FireClient(defenderPlayer, { killer = attacker_char })
			end
		end

		-- Quest progress by kind: every active quest of the kind advances on the same event
		local attackerPlayer = Players:GetPlayerFromCharacter(attacker_char)
		if attackerPlayer then
			local questHandler = context.serviceBag:GetService(QuestHandler)
			local attackerQuests = questHandler:GetHandler(attackerPlayer)
			if attackerQuests then
				attackerQuests:IncreaseProgress("damage", context.damage)
				if wasAlive and defender_humanoid.Health <= 0 then
					attackerQuests:IncreaseProgress("kill", 1)
				end
			end
		end
	end

	if context.stunt_time then
		-- stunt_client(defender_humanoid, context.stunt_time)
		local BinderProvider = context.serviceBag:GetService(_G.BinderProvider)
		local AnimBinder = BinderProvider:Get("AnimationHandler")
		local AnimEnemy = AnimBinder:Get(defender_char)
		if AnimEnemy then
			AnimEnemy:LoadAnimation(true, "stuned")
		end
		defender_humanoid.WalkSpeed = 0
		task.delay(context.stunt_time, function()
			-- WARNING
			defender_humanoid.WalkSpeed = 16
		end)
	end

	self.SetAttHit(defender_char)
	if context.VFX then
		roll_vfx(context.VFX)
	end
	-- VFX_Event:FireAllClients("SwordHit", defender_char)
	local Player = Players:GetPlayerFromCharacter(defender_char)
	if Player then
		VFX_Event:FireClient(Player, "SwordHitShake")
	end

	return effectCtx
end

return EffectService
