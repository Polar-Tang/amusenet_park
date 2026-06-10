local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraState = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.CameraState)
local SummedCamera = require(ReplicatedStorage.Nevermore.Quenty.camera.Client.Effects.SummedCamera)
local Spring = require(ReplicatedStorage.Nevermore.Quenty.spring.Shared.Spring)

local OffsetSpringCamera = {}
OffsetSpringCamera.__index = OffsetSpringCamera

export type OffsetSpringCamera = typeof(setmetatable(
    {} :: {
        CameraState: CameraState.CameraState,
        _getBaseState: () -> CameraState.CameraState,
        _spring: any,
        _lastUpdate: number,
        _enabled: boolean,
    },
    {} :: typeof({ __index = OffsetSpringCamera })
))

function OffsetSpringCamera.new(getBaseState: () -> CameraState.CameraState)
    assert(type(getBaseState) == "function", "getBaseState required")
    local self: OffsetSpringCamera = setmetatable({} :: any, OffsetSpringCamera)

    self._getBaseState = getBaseState
    self._spring = Spring.new(Vector3.new(0, 0, 0))
    self._spring.Damper = 0.7
    self._spring.Speed = 10
    self._lastUpdate = os.clock()
    self._enabled = true

    return self
end

function OffsetSpringCamera:SetEnabled(enabled: boolean)
    self._enabled = enabled and true or false
end

function OffsetSpringCamera:SetTarget(target: Vector3)
    self._spring.Target = target
end

function OffsetSpringCamera:Reset()
    self._spring.Target = Vector3.zero
end

function OffsetSpringCamera.__add(self: OffsetSpringCamera, other)
    return SummedCamera.new(self, other)
end

local function tryStep(spring, dt)
    local ok, _ = pcall(function()
        if type(spring.Step) == "function" then
            spring:Step(dt)
        elseif type(spring.Update) == "function" then
            spring:Update(dt)
        end
    end)
    return ok
end

function OffsetSpringCamera.__index(self: OffsetSpringCamera, index)
    if index == "CameraState" then
        local base = self._getBaseState()
        local now = os.clock()
        local dt = math.max(now - self._lastUpdate, 0)
        self._lastUpdate = now

        tryStep(self._spring, dt)

        if not self._enabled then
            return base
        end

        local out = CameraState.new()
        out.CFrame = base.CFrame * CFrame.new(self._spring.Position)
        out.FieldOfView = base.FieldOfView
        return out
    else
        return OffsetSpringCamera[index]
    end
end

return OffsetSpringCamera
