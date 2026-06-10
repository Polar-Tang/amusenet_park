--[=[
	@class PCPeephole

	Mouse-and-keyboard grenade aimer. The predicted arc follows the mouse every frame
	(a `mouse.UnitRay` raycast that excludes all player characters, so it lands on the
	world rather than a body); left-click hands the current aim point back through
	`throwCallback`. The
	aimer stays live after a throw (hold the grenade -> keep aiming) -- teardown is
	driven externally by `finish` on unequip/swap, which is why this returns its
	connection cleanup for `sightClass` to call.

	This is the old `TrajectoryAimer` logic, now sharing `drawTrajectory` with
	`MobilePeephole`. Side-safe: `LocalPlayer`/mouse/`RenderStepped` are only touched
	inside the call, never at module scope, so requiring it on the server is inert.

	The kinematics MUST match `CombatConfig.grenade` (FLIGHT_TIME) so the previewed
	arc equals the real flight: v0 = (P1 - P0 - 0.5*G*T^2) / T
]=]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local drawTrajectory = require(
	game:GetService("ReplicatedStorage").Nevermore.Custom.abilities.src.Client.Utils.drawTrajectory
)
local Constants = require(
	game:GetService("ReplicatedStorage").Nevermore.Custom.abilities.src.Shared.Constanst
)

-- Fixed flight time, shared with the server throw (see CombatConfig.grenade).
local FLIGHT_TIME = 0.5
-- Only redraw when the aim point moves more than this; avoids per-frame churn.
local REAIM_DISTANCE = 2
-- Aim raycast reach.
local RAY_LENGTH = 500

--[=[
	Start the PC aimer. `throwCallback(landingPos)` runs on left-click; `finish`
	is the external teardown (unused by the PC gesture -- it stays live). Returns a
	cleanup that disconnects every connection, called by `sightClass.finish`.
]=]
local function PCPeephole(throwCallback: (Vector3) -> (), _finish: () -> ()): () -> ()
	local player = Players.LocalPlayer
	local mouse = player:GetMouse()
	local gravity = Vector3.new(0, -workspace.Gravity, 0)

	-- Ignore every player character so the aim ray lands on the world, not on a
	-- body. The grenade is thrown *at* other players, so their characters (and our
	-- own back when aiming close) must not catch the aim point -- which is why we
	-- raycast `mouse.UnitRay` instead of reading `mouse.Hit`, which hits everything.
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Rebuilt each raycast so respawns / joins / leaves stay covered. The parts are
	-- tagged server-side in CombatMediator.PlayerAdded.
	local function refreshCharacterFilter()
		raycastParams.FilterDescendantsInstances = CollectionService:GetTagged(Constants.peepholeExclude)
	end

	local function getAimPosition(): Vector3
		refreshCharacterFilter()
		local unitRay = mouse.UnitRay
		local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * RAY_LENGTH, raycastParams)
		if result then
			return result.Position
		end
		return unitRay.Origin + unitRay.Direction * RAY_LENGTH
	end

	local lastAim: Vector3? = nil
	local renderConnection: RBXScriptConnection? = nil
	local clickConnection: RBXScriptConnection? = nil

	local function cleanup()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		if clickConnection then
			clickConnection:Disconnect()
			clickConnection = nil
		end
	end

	clickConnection = mouse.Button1Down:Connect(function()
		if lastAim then
			throwCallback(lastAim)
		end
	end)

	renderConnection = RunService.RenderStepped:Connect(function()
		local character = player.Character
		local hrp = character and character.PrimaryPart
		if not hrp then
			return
		end

		local aim = getAimPosition()
		if lastAim and (aim - lastAim).Magnitude <= REAIM_DISTANCE then
			return
		end
		lastAim = aim

		local startPos = hrp.Position
		local initialVelocity = (aim - startPos - 0.5 * gravity * FLIGHT_TIME ^ 2) / FLIGHT_TIME
		drawTrajectory.drawTrajectory(startPos, initialVelocity, FLIGHT_TIME, aim)
	end)

	return cleanup
end

return PCPeephole
