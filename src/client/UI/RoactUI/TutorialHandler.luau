local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local TutorialOverlay = require(script.Parent.components.TutorialOverlay)

export type TutorialSpec = TutorialOverlay.TutorialSpec
export type TutorialHighlight = TutorialOverlay.TutorialHighlight
export type TutorialHand = TutorialOverlay.TutorialHand

--[=[
	Imperative driver for tutorial steps. Owns its own Roact tree (mounted
	straight into PlayerGui, above the App ScreenGui via DisplayOrder) so
	tutorial flow code can run it without touching the App component:

	```lua
	local tutorial = TutorialHandler.new()
	tutorial:Start({
		highlight = {
			position = UDim2.new(0.5, -110, 0.6, -28), -- top-left of the window
			size = UDim2.fromOffset(220, 56),
		},
		hand = {
			image = "rbxassetid://<hand asset>",
			startPosition = UDim2.fromScale(0.62, 0.72),
			endPosition = UDim2.fromScale(0.56, 0.66),
			startRotation = -20,
			endRotation = 0,
		},
	})
	-- ... player performed the step ...
	tutorial:Destroy() -- unmounts, cancels the hand tween, screen back to normal
	```

	Calling `Start` again replaces the current step (the maid slot unmounts
	the previous tree first), and the handler is reusable after `Destroy`.

	@class TutorialHandler
]=]
local TutorialHandler = {}
TutorialHandler.__index = TutorialHandler

export type TutorialHandler = typeof(setmetatable(
	{} :: {
		_maid: any,
		_playerGui: PlayerGui,
	},
	TutorialHandler
))

function TutorialHandler.new(): TutorialHandler
	local self = setmetatable({}, TutorialHandler)

	self._maid = Maid.new()
	self._playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	return self
end

function TutorialHandler.Start(self: TutorialHandler, spec: TutorialSpec)
	assert(spec.highlight or spec.hand, "TutorialHandler.Start: spec needs a highlight and/or a hand")

	local mount = Roact.mount(Roact.createElement(TutorialOverlay, spec), self._playerGui, "TutorialOverlay")

	-- Named maid slot: re-assigning on the next Start (or DoCleaning on
	-- Destroy) unmounts the previous tree, which cascades into the
	-- component's willUnmount -> its maid cancels the hand tween.
	self._maid._mount = function()
		Roact.unmount(mount)
	end
end

function TutorialHandler.Destroy(self: TutorialHandler)
	self._maid:DoCleaning()
end

return TutorialHandler
