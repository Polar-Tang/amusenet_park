--||Services||--
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TS = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

--||Services||--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local domeEffect = require(script.domeEffect)
local playRandomSoundFromSource = require(script.playRandomSoundFromSource)
local emitParticles = require(ReplicatedStorage.Shared.Helpers.emitParticles)
local drawRayResults = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.utils.drawRayResults)

--||Folder||--
local Effects = ReplicatedStorage.Shared.Roact


--vfx
--||Camera||--
local camera = game.Workspace.CurrentCamera

--||Camera Shake Module||--
-- local CameraShakeModule = require(RS.Shared.utils.CameraShaker)
-- local emitParticles = require(ReplicatedStorage.Shared.Helpers.emitParticles)
-- local camShake = CameraShakeModule.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
-- 	camera.CFrame = camera.CFrame * shakeCf
-- end)
-- camShake:Start()
------------------------------------------------------------------------------------------------------------------

local function getTorso(char)
	local HUM = char:FindFirstChild("Humanoid")

	if not HUM then
		return
	end

	local Torso
	if HUM.RigType == Enum.HumanoidRigType.R6 then
		Torso = char:WaitForChild("Torso")
	else
		Torso = char:WaitForChild("UpperTorso")
	end
	return Torso
end

local player_char = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()

--||VFX All Clients Function||--
RS.Shared.RemoteEvents.VFX.OnClientEvent:Connect(function(data)
	local action = data.action
	local enemy = data.enemy
	-- if action == "SwordHitShake" then
	-- 	camShake:ShakeOnce(1.6, 4.5, 0.2, 1)
	-- end

	-- if action == "ParryEffect" then
	-- 	Lighting.BlurEffect.Size = 25
	-- 	TS:Create(Lighting.BlurEffect, TweenInfo.new(1.5), { Size = 0 }):Play()
	-- 	camShake:ShakeOnce(1.2, 3.8, 0.15, 0.7)
	-- end

	-- if action == "GuardBreakCamera" then
	-- 	camShake:ShakeOnce(2.2, 5.7, 0.8, 1.5)
	-- end

	-- if action == "GuardBreakCamera" then
	-- 	camShake:ShakeOnce(2.2, 5.7, 0.8, 1.5)
	-- end

	if action == "StrikesHit" then
		local torso = getTorso(enemy)
		-- local strike = normal_strike:Clone()
		-- strike.Position = torso.Position
		-- strike.Parent = workspace
		-- emitParticles({
		-- 	effect = strike,
		-- })
		-- Debris:addItem(strike, 0.5)
		-- task.delay(0.3, function()
		-- 	emitParticles({
		-- 		effect = strike,
		-- 		destroy = true,
		-- 	})
		-- end)
	end
	if action == "shark_transformation" then
		local hrp = data.Attacker:WaitForChild("HumanoidRootPart")
		if data.destroy then
			-- Remove BottomAura
			local particle_emitter = hrp:FindFirstChild("ParticleEmitter")
			if particle_emitter then
				particle_emitter:Destroy()
			end
			local particle_emitter2 = hrp:FindFirstChild("ParticleEmitter")
			if particle_emitter2 then
				particle_emitter2:Destroy()
			end

			local water = hrp:FindFirstChild("water")
			if water then
				water:Destroy()
			end
			-- Remove particles from HRP
			local function removeParticles(targetPart)
				for _, child in pairs(targetPart:GetChildren()) do
					if child:IsA("ParticleEmitter") or child:IsA("Attachment") then
						child:Destroy()
					end
				end
			end

			removeParticles(hrp)

			-- Remove particles from limbs
			local limbs = { "Right Leg", "Left Leg", "Right Arm", "Left Arm" }
			for _, limbName in pairs(limbs) do
				local targetLimb = data.Attacker:FindFirstChild(limbName)
				if targetLimb then
					removeParticles(targetLimb)
				end
			end
		else
			-- Copy BottomAura to HRP
			local model = Effects.sharkVFX.coverWater
			local bottomAura = model:FindFirstChild("BottomAura")
			if bottomAura then
				bottomAura:Clone().Parent = hrp
			end

			-- Copy particles from RootAttachment
			local function copyParticles(sourcePart, targetPart)
				local sourceAttachment = sourcePart:FindFirstChild("RootAttachment")
				if sourceAttachment then
					for _, particle in pairs(sourceAttachment:GetChildren()) do
						if particle:IsA("ParticleEmitter") then
							particle:Clone().Parent = targetPart
						end
					end
				end
			end

			copyParticles(model:FindFirstChild("HumanoidRootPart"), hrp)

			-- Copy particles for limbs
			local limbs = { "Right Leg", "Left Leg", "Right Arm", "Left Arm" }
			for _, limbName in pairs(limbs) do
				local sourceLimb = model:FindFirstChild(limbName)
				local targetLimb = data.Attacker:FindFirstChild(limbName)
				if sourceLimb and targetLimb then
					copyParticles(sourceLimb, targetLimb)
				end
			end
		end
	end
	if action == "shark_roar" then
		if data.destroy then
			print()
			local head = data.Attacker:FindFirstChild("Head")
			local RoarAttachment = head:FindFirstChild("RoarAttachment")
			emitParticles({ effect = RoarAttachment, destroy = true })
			RoarAttachment:Destroy()
		else
			local head = data.Attacker:FindFirstChild("Head")
			local sourceAtt = ReplicatedStorage.Shared.Effects.sharkVFX.Roar.RoarAttachment
			local RoarAtt = sourceAtt:Clone()
			RoarAtt.CFrame = sourceAtt.CFrame
			RoarAtt.Parent = head
		end
	end
	if action == "wind_explosion" then
		local explosion = Effects.sharkVFX.Explosion:Clone()
		explosion.Position = data.src.Position

		explosion.Parent = workspace

		emitParticles({ effect = explosion, particlesToEmit = 1 })
		Debris:AddItem(explosion, 0.3)
		task.delay(0.3, function()
			emitParticles({ effect = explosion, destroy = true })
		end)
	end
	if action == "waterHit" then
		local waterHitL = Effects.sharkVFX.waterHit:Clone()
		local src = data.src
		local particlesL: Attachment = waterHitL:FindFirstChild("Hit")
		local particles2L: Attachment = waterHitL:FindFirstChild("Attachment")

		particlesL.Position = src.Position
		particlesL.Parent = src
		emitParticles({ effect = particlesL, particlesToEmit = 1 })

		particles2L.Position = src.Position
		particles2L.Parent = src
		emitParticles({ effect = particles2L, particlesToEmit = 1 })
	end
	if action == "counter" then
		local counter = Effects.sharkVFX.counter:Clone()

		local ground = Vector3.new(data.src.Position.X, data.src.Position.Y - 3, data.src.Position.Z)
		counter.Position = ground
		counter.Parent = workspace

		emitParticles({ effect = counter, particlesToEmit = 1 })
		Debris:AddItem(counter, 0.7)
		task.delay(0.7, function()
			emitParticles({ effect = counter, destroy = true })
		end)
	end
	if action == "hydro_beam" then
		local start = Effects.sharkVFX.ceroBarrage1:Clone()
		local finish = Effects.sharkVFX.ceroBarrage2:Clone()

		local hrp = data.Attacker:WaitForChild("HumanoidRootPart")
		print("Hrp ", hrp)
		start.Position = data.Pos
		finish.Position = hrp.Position + hrp.CFrame.LookVector * 40
		
		start.Parent = workspace
		finish.Parent = workspace

		print("data.life_time ", data.life_time)
		Debris:AddItem(start, data.life_time)
		Debris:AddItem(finish, data.life_time)

		for _, beam in ipairs(start:GetChildren()) do
			if beam:IsA("Beam") then
				beam.Attachment0 = start:WaitForChild("Attachment1")
				beam.Attachment1 = finish:WaitForChild("Attachment2")
				beam.Enabled = true
			end
		end
	end
	if action == "shot" then
		if data.src and data.src:IsDescendantOf(game) then
			local handle = data.src.Handle
			local sounds = data.src.Sounds
			local emitter = handle.AudioEmitter
			local muzzle = data.src:FindFirstChild("MuzzleAttachment", true)

			local position = muzzle.WorldPosition

			-- Play VFX
			muzzle.FlashEmitter:Emit(1)

			-- Play SFX
			playRandomSoundFromSource(sounds.Shoot, emitter)
			drawRayResults(position, data.rayResults)
		end
	end
	if action == "make_giant" then
		if data.src then
			local tween1 = TS:Create(data.src, TweenInfo.new(1), { Size = data.Size })
			tween1:Play()
		end
		if data.src2 then
			local tween2 = TS:Create(data.src2, TweenInfo.new(1), { Size = data.Size2 })
			tween2:Play()
		end
		if data.src_model then
			local src_model: Model = data.src_model
			src_model:ScaleTo(data.scaleTo)
		end
		if data.src_model2 then
			local src_model2: Model = data.src_model2
			src_model2:ScaleTo(data.scaleTo)
		end
	end
	if action == "BlockingHit" then
		--print(enemy, "enemy ", type(enemy))
		--enemy.
		local BlockEffect = Effects:WaitForChild("Block").Attachment:Clone()
		BlockEffect.Parent = getTorso(enemy)
		Debris:AddItem(BlockEffect, 3)

		for i, v in pairs(BlockEffect:GetDescendants()) do
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end

	if action == "ParryHit" then
		local ParryEffect = Effects:WaitForChild("Parry").Attachment:Clone()
		ParryEffect.Parent = getTorso(enemy)
		Debris:AddItem(ParryEffect, 3)

		for i, v in pairs(ParryEffect:GetDescendants()) do
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end

	if action == "GuardBreak" then
		local GuardBreakEffect = Effects:WaitForChild("GuardBreak").Attachment:Clone()

		GuardBreakEffect.Parent = getTorso(enemy)
		Debris:AddItem(GuardBreakEffect, 3)

		for i, v in pairs(GuardBreakEffect:GetDescendants()) do
			v:Emit(v:GetAttribute("EmitCount"))
		end
	end

	if action == "cutscene" then
		print("data.Defender ", data.Defender, data.Attacker)
		print("player_char ", player_char)
		if data.Defender ~= player_char and data.Attacker ~= player_char then
			return
		end

		local attackerCamera: Camera = workspace.CurrentCamera

		do
			if data.destroy then
				repeat
					task.wait()

					attackerCamera.CameraType = Enum.CameraType.Custom

				until attackerCamera.CameraType == Enum.CameraType.Custom
				print()
				return
			end
			repeat
				task.wait()

				attackerCamera.CameraType = Enum.CameraType.Scriptable

			until attackerCamera.CameraType == Enum.CameraType.Scriptable
		end
		local goal_cf
		if typeof(data.camera_location) == "Vector3" then
			if data.look_to then
				goal_cf = CFrame.lookAt(data.camera_location, data.look_to)
			else
				goal_cf = CFrame.new(data.camera_location)
			end
		elseif typeof(data.camera_location) == "CFrame" then
			goal_cf = data.camera_location
		else
			print("Unkown type ", typeof(data.camera_location))
		end
		camera.CFrame = goal_cf
		--[[
	local defenderCamera = data.Defender:FindFirstChild("Camera")
	local TweenInf = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0)

	if attackerCamera then
		local attackerTween = TS:Create(attackerCamera, TweenInf, { CFrame = goal_cf })

		attackerTween:Play()
	end
	if defenderCamera then
		local defenderTween = TS:Create(defenderCamera, TweenInf, { CFrame = CFrame.new(data.camera_location) })
		defenderTween:Play()
		defenderTween.Completed:Wait()
	end
]]
	end

	if action == "HeavyAttack" then
		local char = data.character

		local KanjiEffect = Effects:WaitForChild("DangerKanji"):Clone()
		KanjiEffect.Parent = char.Head.FaceCenterAttachment
		Debris:AddItem(KanjiEffect, 3)

		KanjiEffect:Emit(1)
	end

	-- Grenade flight: pivot the projectile model along the SAME kinematic arc
	-- the thrower previewed and the server solved. Runs on every client; the
	-- server never pivots it. s = s0 + v0*t + 0.5*g*t^2
	if action == "grenade_flight" then
		local vfxFolder = ReplicatedFirst:FindFirstChild("VFX")
		local template = vfxFolder and vfxFolder:FindFirstChild("Grenade")
		if template then
			local model = template:Clone()
			model.Parent = workspace

			local startPosition = data.startPosition
			local initialVelocity = data.initialVelocity
			local flightTime = data.flightTime or 0.5
			local gravity = Vector3.new(0, -workspace.Gravity, 0)

			local t = 0
			local lastY = startPosition.Y
			local conn
			conn = RunService.Heartbeat:Connect(function(deltaTime)
				t += deltaTime
				local newPos = startPosition + initialVelocity * t + 0.5 * gravity * (t ^ 2)
				model:PivotTo(CFrame.new(newPos))

				-- Stop on ground-cross or when the flight time elapses.
				if (lastY > 0 and newPos.Y <= 0) or t >= flightTime then
					conn:Disconnect()
					model:Destroy()
				end
				lastY = newPos.Y
			end)
			-- Safety net in case the heartbeat is interrupted before it tears down.
			Debris:AddItem(model, flightTime + 2)
		end
	end

	-- Grenade impact at the landing point (placeholder: reuse the wind explosion).
	if action == "grenade_explosion" then
		
		domeEffect(data.Pos)

	end
end)
