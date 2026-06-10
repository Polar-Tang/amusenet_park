local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local emitParticles = require(ReplicatedStorage.Shared.Helpers.emitParticles)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local testPart = require(ReplicatedStorage.Shared.test.testPart)
local bulletTemplate = game.ReplicatedStorage.Shared.Effects.Bullet

local function laserBeamEffect(startPosition: Vector3, endPosition: Vector3)
	local distance = (startPosition - endPosition).Magnitude
	local tweenTime = distance / Constants.LASER_BEAM_VISUAL_SPEED
	local tweenCon

	-- 0.1 = d / bulletPerVelocity
	local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local Bullet = bulletTemplate:Clone()
	emitParticles({effect = Bullet, Lifetime = NumberRange.new(tweenTime,tweenTime)})
	Bullet.CFrame = CFrame.lookAt(startPosition, endPosition) * CFrame.Angles(0, math.rad(90), 0)
	Bullet.Parent = Workspace

	-- testPart({ Position = endPosition, Size = Vector3.new(0.5, 0.5, 0.5) })

	local tween = TweenService:Create(Bullet, tweenInfo, { Position = endPosition })
	tween:Play()
	tweenCon = tween.Completed:Once(function()
		Bullet:Destroy()
		tweenCon:Disconnect()
	end)
end

return laserBeamEffect
