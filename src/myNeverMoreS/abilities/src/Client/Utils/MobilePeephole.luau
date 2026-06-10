--[=[
	@class MobilePeephole

	Touch grenade aimer: drag to aim, release to throw. The aim point is a screen
	raycast (there is no `mouse.Hit` on touch), throttled so we only re-raycast when
	the finger moves enough. On release the landing point is handed back through
	`throwCallback`; only the drag gesture ends, the aimer stays live so the player
	can throw again (matching `PCPeephole`). Teardown is external via `finish` on
	unequip/swap.

	Owns no networking: the throw is delivered via `throwCallback` (the weapon
	strategy's `Execute`), matching `PCPeephole`/`TrajectoryAimer` -- the in-place
	`clickEvent:FireServer` from the prototype is intentionally gone.

	Side-safe: `LocalPlayer`/camera/`UserInputService`/`RenderStepped` are only
	touched inside the call, never at module scope.

	The kinematics MUST match `CombatConfig.grenade` (FLIGHT_TIME) so the previewed
	arc equals the real flight: v0 = (P1 - P0 - 0.5*G*T^2) / T
]=]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraUtils = require(ReplicatedStorage.Shared.utils.CameraUtils)
local drawTrajectory = require(
	game:GetService("ReplicatedStorage").Nevermore.Custom.abilities.src.Client.Utils.drawTrajectory
)
local Constants = require(
	game:GetService("ReplicatedStorage").Nevermore.Custom.abilities.src.Shared.Constanst
)

-- Fixed flight time, shared with the server throw (see CombatConfig.grenade).
local FLIGHT_TIME = 0.5
-- Re-raycast only after the finger moves this many screen pixels.
local REAIM_PIXELS = 2
-- Re-sync the start point only after the character moves this many studs.
local REAIM_STUDS = 2
-- Aim raycast reach.
local RAY_LENGTH = 500


--[=[
	Start the touch aimer. `throwCallback(landingPos)` runs on release; `_finish` is
	the external teardown (unused by the gesture -- the aimer stays live across
	throws). Returns a cleanup that disconnects every connection, called by
	`sightClass.finish`.
]=]
local function MobilePeephole(throwCallback: (Vector3) -> (), _finish: () -> ()): () -> ()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local gravity = Vector3.new(0, -workspace.Gravity, 0)
	local character = player.Character or player.CharacterAdded:Wait()

	-- Ignore every player character so the aim raycast lands on the world, not on
	-- a body. The grenade is thrown *at* other players, so their characters must not
	-- catch the aim point (and aiming near ourselves must not land on our own back).
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Rebuilt each raycast so respawns / joins / leaves stay covered. The parts are
	-- tagged server-side in CombatMediator.PlayerAdded.
	local function refreshCharacterFilter()
		raycastParams.FilterDescendantsInstances = CollectionService:GetTagged(Constants.peepholeExclude)
	end

	local startPos: Vector3? = nil -- 3D launch point (the character's PrimaryPart)
	local touchPoint: Vector2? = nil -- live 2D screen point of the finger
	local lastTouchPoint: Vector2? = nil -- cached 2D point to throttle re-aim
	local touchPos: Vector3? = nil -- resolved 3D aim point
	local activeTouch: InputObject? = nil -- the finger that owns the current aim gesture

	local touchStart: RBXScriptConnection? = nil
	local touchUpdate: RBXScriptConnection? = nil
	local touchEnd: RBXScriptConnection? = nil
	local renderStep: RBXScriptConnection? = nil

	local function cleanup()
		if touchStart then
			touchStart:Disconnect()
			touchStart = nil
		end
		if touchUpdate then
			touchUpdate:Disconnect()
			touchUpdate = nil
		end
		if touchEnd then
			touchEnd:Disconnect()
			touchEnd = nil
		end
		if renderStep then
			renderStep:Disconnect()
			renderStep = nil
		end
	end

	local function getAimPosition(screenPoint: Vector2): Vector3
		refreshCharacterFilter()
		local unitRay = camera:ScreenPointToRay(screenPoint.X, screenPoint.Y)
		local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * RAY_LENGTH, raycastParams)
		if result then
			return result.Position
		end
		return unitRay.Origin + unitRay.Direction * RAY_LENGTH
	end

	local function redraw()
		if not startPos or not touchPos then
			return
		end
		local initialVelocity = (touchPos - startPos - 0.5 * gravity * FLIGHT_TIME ^ 2) / FLIGHT_TIME
		drawTrajectory.drawTrajectory(startPos, initialVelocity, FLIGHT_TIME, touchPos)
	end

	-- Keep the start point in sync as the character moves, and re-aim when the
	-- finger has moved enough.
	renderStep = RunService.RenderStepped:Connect(function()
		local hrp = character.PrimaryPart
		if not hrp then
			return
		end
		if startPos and (hrp.Position - startPos).Magnitude > REAIM_STUDS then
			startPos = hrp.Position
		end

		if touchPos and touchPoint and (not lastTouchPoint or (lastTouchPoint - touchPoint).Magnitude > REAIM_PIXELS) then
			lastTouchPoint = touchPoint
			touchPos = getAimPosition(touchPoint)
			redraw()
		end
	end)

	-- True for the finger (or the Studio-emulation mouse) that owns the live gesture.
	-- A Touch InputObject is stable across Began/Changed/Ended for the same finger;
	-- the mouse keeps one persistent object per button, but its movement arrives as a
	-- separate MouseMovement object, so accept that too while a Button1 press is held.
	local function isActiveInput(input: InputObject): boolean
		if input == activeTouch then
			return true
		end
		return activeTouch ~= nil
			and activeTouch.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement
	end

	touchStart = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end
		
		if
			CameraUtils.isMovementTouch(input)
		then
			return
		end
		local hrp = character.PrimaryPart
		if not hrp then
			return
		end

		activeTouch = input
		startPos = hrp.Position
		touchPoint = Vector2.new(input.Position.X, input.Position.Y)
		touchPos = getAimPosition((touchPoint::Vector2))
		redraw()
	end)

	touchUpdate = UserInputService.InputChanged:Connect(function(input)
		-- Only the aim finger may move the reticle; the move finger is ignored.
		if not isActiveInput(input) then
			return
		end
		touchPoint = Vector2.new(input.Position.X, input.Position.Y)
	end)

	touchEnd = UserInputService.InputEnded:Connect(function(input)
		-- Only the aim finger's release throws. End the drag gesture, not the aimer:
		-- the player keeps the grenade, so the aimer stays live for the next drag
		-- (like PCPeephole after a click). Teardown is external via `finish`.
		if input ~= activeTouch then
			return
		end
		activeTouch = nil
		if touchPos then
			throwCallback(touchPos)
		end
	end)

	return cleanup
end

return MobilePeephole
