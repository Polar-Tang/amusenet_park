local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage.Shared.RemoteEvents
local swingEvent = remotes.Swing

local module = {}
module.execute = function(action, params)
	if not action then
		return
	end
	if action == Enum.KeyCode.F then
		local connection
		connection = RunService.RenderStepped:Connect(function()
			if not game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.F) then
				connection:Disconnect()
				local newParams = params and table.clone(params) or {}
				newParams.stop = true
				swingEvent:FireServer(action, params)
			end
		end)
	end
	swingEvent:FireServer(action, params)
end

return module
