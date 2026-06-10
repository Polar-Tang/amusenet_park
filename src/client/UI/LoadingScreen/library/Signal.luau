--!strict

local Signal = {}
Signal.ClassName = "Signal"
Signal.__index = Signal

export type Signal<T...> = any

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self._connected then
		return
	end

	self._connected = false

	local signal = self._signal
	self._signal = nil

	if signal then
		signal:_disconnect(self)
	end
end

Connection.Destroy = Connection.Disconnect

function Connection:IsConnected()
	return self._connected
end

function Signal.new()
	return setmetatable({
		_connections = {},
	}, Signal)
end

function Signal:_disconnect(connection)
	for index, current in ipairs(self._connections) do
		if current == connection then
			table.remove(self._connections, index)
			return
		end
	end
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Bad fn")

	local connection = setmetatable({
		_signal = self,
		_fn = fn,
		_connected = true,
	}, Connection)

	table.insert(self._connections, connection)
	return connection
end

function Signal:Fire(...)
	local snapshot = table.clone(self._connections)
	for _, connection in ipairs(snapshot) do
		if connection._connected then
			connection._fn(...)
		end
	end
end

function Signal:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return Signal