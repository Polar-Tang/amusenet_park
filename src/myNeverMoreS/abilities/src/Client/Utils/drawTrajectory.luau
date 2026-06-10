--[=[
	@class drawTrajectory

	Shared (PC + mobile) parabola renderer for the grenade aimer. Plots the
	predicted arc of a thrown projectile as neon markers under a single
	`TrajectoryMarkers` folder, dropping a larger lit marker at the landing spot.

	DRY'd out of the old `TrajectoryAimer`: both `PCPeephole` and `MobilePeephole`
	share this so the marker styling and the kinematics live in one place. The
	kinematics MUST stay in lockstep with the server throw in `CombatConfig.grenade`
	so the previewed arc matches the real flight:
	  s(t) = s0 + v0*t + 0.5*G*t^2

	Side-safe: nothing here touches `LocalPlayer`/mouse/`RenderStepped`; the markers
	are only built when a peephole calls `drawTrajectory`, so requiring it on the
	server (CombatConfig is shared) does nothing.
]=]

local drawTrajectory = {}

-- Marker every DELTA_TIME seconds of simulated flight.
local DELTA_TIME = 0.05
-- Don't draw arc markers whose Y is within this many studs of the launch height
-- (the player's HRP Y): those sit in front of the camera and obstruct the view.
-- The landing marker is exempt -- it's the actual target.
local HEIGHT_CLEARANCE = 4

-- One folder reused across redraws; lazily created and cleared each draw.
local folder: Folder? = nil

local function ensureFolder(): Folder
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "TrajectoryMarkers"
		newFolder.Parent = workspace
		folder = newFolder
	end
	return folder :: Folder
end

local function createMarker(pos: Vector3): BasePart
	local marker = Instance.new("Part")
	marker.Size = Vector3.new(0.4, 0.4, 0.4)
	marker.Shape = Enum.PartType.Ball
	marker.Color = Color3.fromRGB(255, 255, 255)
	marker.Material = Enum.Material.Neon
	marker.Anchored = true
	marker.CanCollide = false
	marker.Position = pos
	marker.Parent = ensureFolder()
	return marker
end

local function createLandingMarker(pos: Vector3)
	local marker = createMarker(pos)
	marker.Size = Vector3.new(2, 2, 2)

	local spotLight = Instance.new("SpotLight")
	spotLight.Face = Enum.NormalId.Top
	spotLight.Color = Color3.fromRGB(0, 170, 0)
	spotLight.Angle = 30
	spotLight.Brightness = 100
	spotLight.Parent = marker
end

--[=[
	Plot the parabola from `startPos` with `initialVelocity` under gravity until
	`flightTime`, dropping a marker every DELTA_TIME. The landing marker is placed
	at `landingPos` when supplied (the real aim point), otherwise at the last
	simulated point.
]=]
function drawTrajectory.drawTrajectory(
	startPos: Vector3,
	initialVelocity: Vector3,
	flightTime: number,
	landingPos: Vector3?
)
	local markerFolder = ensureFolder()
	markerFolder:ClearAllChildren()

	local gravity = Vector3.new(0, -workspace.Gravity, 0)
	local t = 0
	while t < flightTime do
		local currentPos = startPos + initialVelocity * t + 0.5 * gravity * (t ^ 2)
		if t + DELTA_TIME >= flightTime then
			createLandingMarker(landingPos or currentPos)
		elseif math.abs(currentPos.Y - startPos.Y) >= HEIGHT_CLEARANCE then
			-- Skip markers at roughly the player's height -- they block the camera.
			createMarker(currentPos)
		end
		t += DELTA_TIME
	end
end

--[=[
	Remove the marker folder. Idempotent (safe when never drawn).
]=]
function drawTrajectory.destroyTrajectory()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return drawTrajectory
