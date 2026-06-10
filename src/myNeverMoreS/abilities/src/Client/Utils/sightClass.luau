--[=[
	@class sightClass

	Grenade-aimer front door. Picks the touch or mouse aimer at `init` time and
	exposes the same `init(throwCallback)` / `finish()` surface the old
	`TrajectoryAimer` had, so the grenade's `onEquipCBClient` in `CombatConfig` can
	drive it without caring about the input device.

	Both peepholes own no networking: they hand the landing point back through
	`throwCallback`, which the weapon strategy turns into an `Execute`. The picked
	peephole returns its connection cleanup; `finish` runs it (so an external
	unequip/swap fully tears down) and clears the markers. Both `init` and `finish`
	are idempotent via `isRendering`.

	Side-safe: nothing here touches the player at module scope, so requiring it from
	the shared `CombatConfig` (server included) is inert.
]=]

local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local drawTrajectory = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Client.Utils.drawTrajectory)
local MobilePeephole = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Client.Utils.MobilePeephole)
local PCPeephole = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Client.Utils.PCPeephole)

local sightClass = {}

local isRendering = false
local activeCleanup: (() -> ())? = nil

--[=[
	Tear the active aimer down: disconnect the peephole's connections, clear the
	markers, reset state. Idempotent (safe when never initialized). Passed to the
	peephole as its `finish`, and also called by the equip hook's cleanup closure.
]=]
function sightClass.finish()
	if not isRendering then
		return
	end
	isRendering = false

	-- Capture-then-nil so a peephole calling finish() from inside its own gesture
	-- can't re-enter the cleanup.
	if activeCleanup then
		local cleanup = activeCleanup
		activeCleanup = nil
		cleanup()
	end
	drawTrajectory.destroyTrajectory()
end

--[=[
	Activate the device-appropriate aimer. `throwCallback(landingPos)` runs when the
	player commits a throw. No-op if already active (guards a double equip).
]=]
function sightClass.init(throwCallback: (Vector3) -> ())
	if isRendering then
		return
	end
	isRendering = true

	local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	if isTouch then
		activeCleanup = MobilePeephole(throwCallback, sightClass.finish)
	else
		activeCleanup = PCPeephole(throwCallback, sightClass.finish)
	end
end

return sightClass
