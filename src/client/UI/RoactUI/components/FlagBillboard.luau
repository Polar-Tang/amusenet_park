local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Roact = require(ReplicatedStorage.Shared.Roact)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)

local FlagCarrierRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.FlagCarrier

--[=[
	Over-head "carrying the flag" marker. The server (Flag binder) fires
	FlagCarrier with `(character, isCarrying)` whenever a flag is picked up or
	returned; this component raises a BillboardGui adorned to that character's
	head while it carries.

	Two independent unmount paths, so the marker can never linger:
	  * the server's `isCarrying = false` (a live return-to-base — the carrier is
	    still in the world, so AncestryChanged never fires);
	  * the adornee's own `AncestryChanged` to a nil parent (death / despawn —
	    "automatically unmounts when the adornee leaves the world"), which the
	    server's ReturnToBase-on-death may not beat.

	BillboardGuis are rendered through a Portal into PlayerGui (they adorn to a
	world part, so they must NOT nest inside the App ScreenGui's 2D tree).

	@class FlagBillboard
]=]
local FlagBillboard = Roact.Component:extend("FlagBillboard")

function FlagBillboard:init()
	self._maid = Maid.new()
	self._nextId = 0
	-- Model -> string id, so a repeat "carrying" for the same character reuses
	-- its billboard instead of stacking a second one.
	self._idByChar = {}

	-- state.carriers: id -> Model, the live set Roact renders one billboard each.
	self:setState({ carriers = {} })
end

function FlagBillboard._addCarrier(self, character: Model)
	if self._idByChar[character] then
		return
	end

	self._nextId += 1
	local id = tostring(self._nextId)
	self._idByChar[character] = id

	-- Auto-unmount when the adornee leaves the world (parent goes nil).
	self._maid[id] = character.AncestryChanged:Connect(function(_, parent: Instance?)
		if not parent then
			self:_removeCarrier(character)
		end
	end)

	self:setState(function(state)
		local carriers = table.clone(state.carriers)
		carriers[id] = character
		return { carriers = carriers }
	end)
end

function FlagBillboard._removeCarrier(self, character: Model)
	local id = self._idByChar[character]
	if not id then
		return
	end
	self._idByChar[character] = nil
	self._maid[id] = nil -- drop the AncestryChanged watch

	self:setState(function(state)
		local carriers = table.clone(state.carriers)
		carriers[id] = nil
		return { carriers = carriers }
	end)
end

function FlagBillboard:didMount()
	self._maid:GiveTask(FlagCarrierRemote.OnClientEvent:Connect(function(character: Model?, isCarrying: boolean)
		if typeof(character) ~= "Instance" then
			return
		end
		if isCarrying then
			self:_addCarrier(character)
		else
			self:_removeCarrier(character)
		end
	end))
end

function FlagBillboard:willUnmount()
	self._maid:DoCleaning()
end

-- The adornee part: the head reads best, falling back to the root so a rig
-- without a Head still shows the marker.
local function adorneePart(character: Model): BasePart?
	return (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

function FlagBillboard:render()
	local billboards: { [string]: any } = {}

	for id, character in self.state.carriers do
		local adornee = adorneePart(character)
		if not adornee then
			continue
		end

		billboards[id] = Roact.createElement("BillboardGui", {
			Adornee = adornee,
			Size = UDim2.fromOffset(48, 48),
			StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
			AlwaysOnTop = true,
			MaxDistance = 250,
		}, {
			Icon = Roact.createElement("ImageLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = GameModeConstants.CTF_BILLBOARD_IMAGE,
			}),
		})
	end

	-- Portal into PlayerGui: a BillboardGui adorns a world part and must live
	-- outside the App ScreenGui's 2D layout.
	return Roact.createElement(Roact.Portal, {
		target = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}, billboards)
end

return FlagBillboard
