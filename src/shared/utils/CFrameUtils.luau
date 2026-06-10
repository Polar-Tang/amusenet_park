local CFrameUtils = {}

-- Returns true if the camera is very close to the head position or is looking directly at it
function CFrameUtils.isCameraTooCloseToHead(headPos: Vector3, camCFrame: CFrame, distanceThreshold: number?)
    distanceThreshold = distanceThreshold or 0.9
    local dist = (headPos - camCFrame.Position).Magnitude
    if dist < distanceThreshold then
        return true
    end

    local toHead = headPos - camCFrame.Position
    if toHead.Magnitude > 0 then
        local facing = camCFrame.LookVector:Dot(toHead.Unit)
        if facing > 0.9 then
            return true
        end
    end

    return false
end

return CFrameUtils
