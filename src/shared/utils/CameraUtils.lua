local module = {}
-- The default mobile movement control (DynamicThumbstick) activates on the LEFT of
-- the screen and does NOT reliably flag gameProcessedEvent, so `processed` alone
-- won't stop the move finger from starting an aim gesture. We only let a touch begin
-- an aim if it lands past this fraction of the screen width (the "right thumb aims"
-- side), then track that one finger by identity so the move finger can't touch it.
local AIM_REGION_MIN_X_FRACTION = 0.4
-- Reserve the left of the screen for the movement thumbstick: a touch that
-- starts there is a move finger, not an aim. (Mouse is Studio-only testing.)
local camera = workspace.CurrentCamera

module.isMovementTouch = function(input)
	return input.UserInputType == Enum.UserInputType.Touch
		and input.Position.X < camera.ViewportSize.X * AIM_REGION_MIN_X_FRACTION
end

return module
