local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraState = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.CameraState)
local SummedCamera = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.Effects.SummedCamera)
local Spring = require(ReplicatedStorage.Nevermore.Quenty.spring.Shared.Spring)

local RecoilCamera = {}
RecoilCamera.__index = RecoilCamera

export type RecoilCamera = typeof(setmetatable(
	{} :: {
		CameraState: CameraState.CameraState,
		_recoil: Vector2,
		_lastUpdate: number,
		_recoverySpeed: number,
		_minMagnitude: number,
		_spring: Spring.Spring<Vector3>,
	},
	{} :: typeof({ __index = RecoilCamera })
))

function RecoilCamera.new(): RecoilCamera
	local self: RecoilCamera = setmetatable({} :: any, RecoilCamera)

	self._recoil = Vector2.new()
	self._lastUpdate = os.clock()
	self._recoverySpeed = 10
	self._minMagnitude = 0.001

	-- Drives the cumulative Y rise (gun kicking up the aim). Target is bumped
	-- per shot in :Recoil; spring chases it. :Reset drops target to zero so
	-- the spring decays back down on the next idle frame the combo is sampled.
	self._spring = Spring.new(Vector3.zero)
	self._spring.Speed = 10
	self._spring.Damper = 0.7

	return self
end

function RecoilCamera.Recoil(self: RecoilCamera, recoilAmount: Vector2, rise: number?)
	assert(typeof(recoilAmount) == "Vector2", "Bad recoilAmount")
	self._recoil += recoilAmount
	self._lastUpdate = os.clock()
	if rise then
		-- accumulate: each shot pushes the target up so sustained fire keeps rising
		self._spring.Target = self._spring.Target + Vector3.new(0, rise, 0)
	end
end

function RecoilCamera.Reset(self: RecoilCamera)
	self._recoil = Vector2.zero
	self._spring.Target = Vector3.zero
	self._lastUpdate = os.clock()
end

function RecoilCamera.__add(self: RecoilCamera, other)
	return SummedCamera.new(self, other):SetMode("Relative")
end

function RecoilCamera.__index(self: RecoilCamera, index)
	if index == "CameraState" then
		local now = os.clock()
		local dt = math.max(now - self._lastUpdate, 0)
		self._lastUpdate = now

		if self._recoil.Magnitude < self._minMagnitude then
			self._recoil = Vector2.zero
		else
			self._recoil = self._recoil:Lerp(Vector2.zero, math.min(dt * self._recoverySpeed, 1))
		end

		local rotation = CFrame.Angles(self._recoil.Y * dt, self._recoil.X * dt, 0)
		local riseY = self._spring.Position.Y

		local state = CameraState.new()
		state.FieldOfView = 0
		state.CFrame = rotation * CFrame.Angles(math.rad(riseY), 0, 0)
		return state
	else
		return RecoilCamera[index]
	end
end

return RecoilCamera
