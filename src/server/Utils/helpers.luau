local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = {}

-- Runs `action` in a protected call. On failure it pushes the error message to
-- the client debug console (a specific player, or everyone when `player` is nil)
-- so it can be read from a published-game client, then returns nothing. On
-- success it returns `true, <action's first return value>`.
function module.returnDataOrError(player: Player?, action: () -> ...any)
	local ok, dataOrErr = pcall(action)
	if not ok then
		local message = `[error] {tostring(dataOrErr)}`
		if player then
			ReplicatedStorage.Shared.RemoteEvents.clientDebugConsole:FireClient(player, message)
		else
			ReplicatedStorage.Shared.RemoteEvents.clientDebugConsole:FireAllClients(message)
		end

		return
	end
	return ok, dataOrErr
end

return module