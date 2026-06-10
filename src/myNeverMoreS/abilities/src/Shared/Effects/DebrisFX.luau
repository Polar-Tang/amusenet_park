-- DebrisFX.lua
-- Author: Luau (your assistant)
-- A reusable, physics-based destruction FX generator for abilities.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local FXPart = require(script.Parent.FXPart)

local Effects = ReplicatedStorage.Shared.Effects

local DebrisFX = {}
DebrisFX.__index = DebrisFX

-- Default settings
local DEFAULT_SETTINGS = {
	sizeRange = Vector2.new(1, 3),
	velocity = 50,
	material = Enum.Material.Rock,
	lifetime = 3,
	shockwave = true,
	radius = 8,
}

-- Utility: random float
local function randf(min, max)
	return min + math.random() * (max - min)
end

-- Utility: random vector
local function randomDirection()
	return Vector3.new(randf(-1, 1), randf(0.2, 1), randf(-1, 1)).Unit
end

---------------------------------------------------------------------
-- 🌋 MAIN ENTRY FUNCTION
---------------------------------------------------------------------

function DebrisFX:GroundSmash(params)
	params = setmetatable(params or {}, { __index = DEFAULT_SETTINGS })

	local position = params.position
	local normal = params.normal or Vector3.new(0, 1, 0)

	-- Spawn debris chunks
	if params.amount then
		for _ = 1, params.amount do
			self:_spawnChunk(position, normal, params) -- random chunks
		end
	end

	-- Optional dust cloud
	if params.dust then
		self:_spawnDust(position)
	end

	-- Optional shockwave
	if params.shockwave then
		self:_spawnShockwave(position, params.radius)
	end
end

---------------------------------------------------------------------
-- 🧱 SPAWN A SINGLE DEBRIS CHUNK
---------------------------------------------------------------------

function DebrisFX:_spawnChunk(position, normal, params)
	local size = randf(params.sizeRange.X, params.sizeRange.Y)

	local newInstance = FXPart.new({
		props = {
			Position = position + normal * 1.5,
			Size = Vector3.new(size, size, size),
			Material = params.material,
			Color = Color3.new(0.35, 0.35, 0.35),
			Shape = Enum.PartType.Block,
			CastShadow = true,
			CanCollide = true,
			Anchored = false,
		},
		lifetime = params.lifetime,
		sink = {
			delay = 5,
			depth = 3,
			duration = 3,
		},

		fade = {
			delay = 4,
			duration = 1,
		},
	})

	local part = newInstance.Part
	-- Initial impulse
	part.AssemblyLinearVelocity = randomDirection() * randf(params.velocity * 0.5, params.velocity)

	-- Rotational impulse
	part.AssemblyAngularVelocity = Vector3.new(randf(-8, 8), randf(-8, 8), randf(-8, 8))
end

---------------------------------------------------------------------
-- ☁️ DUST PARTICLES
---------------------------------------------------------------------

function DebrisFX:_spawnDust(position)
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxassetid://248625108" -- nice dust puff texture
	p.Rate = 0
	p.Speed = NumberRange.new(5, 15)
	p.Lifetime = NumberRange.new(0.4, 0.8)
	p.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	p.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(1, 8),
	})
	p.SpreadAngle = Vector2.new(360, 360)

	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = workspace.Terrain

	p.Parent = a
	p:Emit(40)

	Debris:AddItem(a, 1.5)
end

---------------------------------------------------------------------
-- 🌊 SHOCKWAVE RING
---------------------------------------------------------------------

function DebrisFX:_spawnShockwave(position, radius)
	local newInstance = FXPart.new({
		size = Vector3.new(radius, 0.2, radius),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		material = Enum.Material.ForceField,
		color = Color3.new(1, 1, 1),
		lifetime = 5,
		shape = Enum.PartType.Cylinder,
		castShadow = true,
		canCollide = true,
		anchored = true,
		transparency = 0.5,
		sink = {
			delay = 5,
			depth = 3,
			duration = 3,
		},

		fade = {
			delay = 4,
			duration = 1,
		},
	})

	local scaled = 1

	local ring = newInstance.Part
	task.spawn(function()
		local start = tick()
		local duration = 0.4
		while tick() - start < duration do
			local t = (tick() - start) / duration
			scaled = 1 + t * 3
			ring.Size = Vector3.new(radius * scaled, 0.2, radius * scaled)
			ring.Transparency = 0.5 + t * 0.5
			RunService.Heartbeat:Wait()
		end
		ring:Destroy()
	end)
end

return DebrisFX
