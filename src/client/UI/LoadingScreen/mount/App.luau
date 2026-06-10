local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- COMPONENTS
local components = script.Parent.Components
local loadingProgressBar = require(components.lib.loadingProgressBar)
local title = require(components.title)
local background = require(components.background)
local Roact = require(ReplicatedStorage.Shared.Roact)

local App = Roact.Component:extend("App")
function App:init()
	self:setState({
		running = true,
	})

	-- Set up a signal for progress updates based on the registry
    
    self.progressConnection = self.props.progress:Observe():Subscribe(function(progress)
		self:setState({progress = progress})
	end)

end

-- local Context = script.Parent.Context
-- local useContext = require(Context.Utils.useContext)

function App:render()
	return Roact.createFragment({
		background = Roact.createElement(background),
		title = Roact.createElement(title),
		loadingProgressBar = Roact.createElement(loadingProgressBar, {
			percentage = self.state.progress
		}),

	})
end

function App:didMount()
	self.running = true
end

function App:unMount()
	self.running = true
end

return App
