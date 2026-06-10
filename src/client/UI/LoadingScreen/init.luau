local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Roact = require(ReplicatedStorage.Shared.Roact)
local assetsRegistry = require(ReplicatedStorage.Shared.Public.assets)

local Signal = {}
Signal.__index = Signal

local SignalConnection = {}
SignalConnection.__index = SignalConnection

function SignalConnection:Disconnect()
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

SignalConnection.Destroy = SignalConnection.Disconnect

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
	}, SignalConnection)

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

local ValueObject = {}
ValueObject.__index = ValueObject

function ValueObject.new(baseValue, checkType)
	if type(checkType) == "string" then
		if typeof(baseValue) ~= checkType then
			error(string.format("Expected value of type %q, got %q instead", checkType, typeof(baseValue)))
		end
	elseif type(checkType) == "function" then
		assert(checkType(baseValue))
	end

	return setmetatable({
		_value = baseValue,
		_default = baseValue,
		_checkType = checkType,
		Changed = Signal.new(),
	}, ValueObject)
end

function ValueObject.__index(self, key)
	if key == "Value" then
		return rawget(self, "_value")
	end

	return ValueObject[key]
end

function ValueObject.__newindex(self, key, value)
	if key == "Value" then
		ValueObject._applyValue(self, value)
		return
	end

	rawset(self, key, value)
end

function ValueObject._applyValue(self, value)
	local previous = rawget(self, "_value")
	local checkType = rawget(self, "_checkType")

	if type(checkType) == "string" then
		if typeof(value) ~= checkType then
			error(string.format("Expected value of type %q, got %q instead", checkType, typeof(value)))
		end
	elseif type(checkType) == "function" then
		assert(checkType(value))
	end

	if previous ~= value then
		rawset(self, "_value", value)
		local changed = rawget(self, "Changed")
		if changed then
			changed:Fire(value, previous)
		end
	end
end

function ValueObject:Observe()
	return {
		Subscribe = function(_, fireCallback)
			if fireCallback then
				fireCallback(self.Value)
			end

			return self.Changed:Connect(function(newValue)
				if fireCallback then
					fireCallback(newValue)
				end
			end)
		end,
	}
end

--[[
	Need to change a little bit the lifecycle of this. Currently init initialize the variables and then needs :Start to redner the loading screen, the deal is Start is called to late and the loading screen last to render. We need to require the mounting local mounting = require(script.mount.mounting) on Init method. In order to do that and not break things, first the progress needs to freeze at 0 until Start is called, then we need to use signals in fired in every registryObserver so the Loading screen component is connected to this signal and update its table of registry values to calculate the percentage with. The correct usage of LoadingScreen calls Start once all the registryObserver have been called, meaning the internal table used by src/client/UI/LoadingScreen/mount/App.luau is by its latest version
]]
-- call Roact.unmount(thisScript)
-- handler
export type heavyness = "light" | "normal" | "heavy" | "veryheavy"

export type Handler = {
	finishSignal: any,
	progress: any,
	register: { [string]: any },
	registryWeights: { [string]: number },
	registryLoaded: { [string]: boolean },
	_pendingMarks: { [string]: boolean },
	assetIds: { string },
	assetTotal: number,
	assetLoaded: number,
	registryTotalWeight: number,
	registryLoadedWeight: number,
	_started: boolean,
	_didFinish: boolean,
	Init: (self: Handler) -> (),
	_recalculateProgress: (self: Handler) -> (),
	mount: any?,
	Start: (self: Handler) -> (),
	_finish: (self: Handler) -> (),
	registryObserver: (self: Handler, key: string, heavyness: heavyness?) -> (),
	markObserver: (self: Handler, key: string, isLoaded: boolean) -> (),
	registerFinishCB: (self: Handler, cb: () -> ()) -> (),
	_initialized: boolean,
}

local HEAVYNESS_WEIGHT = {
	light = 1,
	normal = 2,
	heavy = 10,
	veryheavy = 20,
}

local function flattenAssets(input: any, out: { string })
	if type(input) == "string" then
		table.insert(out, input)
		return
	end

	if type(input) == "table" then
		for _, value in pairs(input) do
			flattenAssets(value, out)
		end
	end
end

local function clamp(value: number, minValue: number, maxValue: number): number
	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local handler = {
	finishSignal = Signal.new(),
	progress = ValueObject.new(0),
	register = {},
	registryWeights = {},
	registryLoaded = {},
	_pendingMarks = {},
	assetIds = {},
	assetTotal = 0,
	assetLoaded = 0,
	registryTotalWeight = 0,
	registryLoadedWeight = 0,
	_started = false,
	_didFinish = false,
	_initialized = false,
}
handler.__index = handler


handler.mount = nil

function handler.Init(self: Handler)
	self._initialized = true
	self._started = false
	self._didFinish = false

	self.register = {}
	self.registryWeights = {}
	self.registryLoaded = {}
	self._pendingMarks = {}
	self.registryTotalWeight = 0
	self.registryLoadedWeight = 0

	local rawAssets = {}
	flattenAssets(assetsRegistry, rawAssets)
	local seen = {}
	local assets = {}
	for _, id in ipairs(rawAssets) do
		if not seen[id] then
			seen[id] = true
			table.insert(assets, id)
		end
	end
	self.assetIds = assets
	self.assetTotal = #assets
	self.assetLoaded = 0

	self.progress.Value = 0
end

function handler._recalculateProgress(self: Handler)
	local totalWork = self.assetTotal + self.registryTotalWeight
	local finishedWork = self.assetLoaded + self.registryLoadedWeight

	if totalWork <= 0 then
		self.progress.Value = 100
	else
		self.progress.Value = clamp((finishedWork / totalWork) * 100, 0, 100)
	end

	if self._started and not self._didFinish then
		if self.assetLoaded >= self.assetTotal and self.registryLoadedWeight >= self.registryTotalWeight then
			self._didFinish = true
			self.finishSignal:Fire(nil)
		end
	end
end

function handler.Start(self: Handler)
	if not self._initialized then
		warn("Loading handler should call Init() before Start(); calling Init() automatically")
		self:Init()
	end

	self._initialized = false
	self._started = true

	if self.mount then
		warn("Handler already started")
		return
	end
	self.finishSignal:Connect(function() 
		self:_finish()
	end)

	local mounting = require(script.mount.mounting)
	self.mount = mounting({
		progress = self.progress,
		finishSignal = self.finishSignal,
		finnishSignal = self.finishSignal,
	})

	game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	if self.assetTotal <= 0 then
		self.assetLoaded = 0
		self:_recalculateProgress()
		return
	end

	task.spawn(function()
		local instances = {}
		for _, id in ipairs(self.assetIds) do
			local img = Instance.new("ImageLabel")
			img.Image = id
			table.insert(instances, img)
		end

		local loaded = 0
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(instances, function(_contentId: string, _status)
				loaded += 1
				self.assetLoaded = math.min(loaded, self.assetTotal)
				print("_contentId ", _contentId)
				self:_recalculateProgress()
			end)
		end)

		for _, img in ipairs(instances) do
			img:Destroy()
		end

		if not ok then
			warn("PreloadAsync failed", err)
			self.assetLoaded = self.assetTotal
			self:_recalculateProgress()
		end
	end)

	self:_recalculateProgress()
end

function handler._finish(self: Handler)
	if not self.mount then
		warn("Handler not started")
		return
	end
	Roact.unmount(self.mount)
	
	self.mount = nil
	-- _G.loaging_registry = nil
	game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
end

function handler.registerFinishCB(self: Handler, cb: () -> ())
	self.finishSignal:Connect(function(a0: nil)  
		cb()
	end)
end


function handler:registryObserver(key: string, heavyness: heavyness?)
	if not self._initialized then 
		warn("'registryObserver' should be used during Init")
		return
	end

	if self.register[key] ~= nil then
		warn("Registry key already exists", key)
		return
	end

	local normalizedHeavyness = heavyness or "normal"
	local weight = HEAVYNESS_WEIGHT[normalizedHeavyness]
	if weight == nil then
		warn("Invalid heavyness, defaulting to 'normal'", normalizedHeavyness)
		normalizedHeavyness = "normal"
		weight = HEAVYNESS_WEIGHT.normal
	end

	local valueObject = ValueObject.new(false, "boolean")
	self.register[key] = valueObject
	self.registryLoaded[key] = false
	self.registryWeights[key] = weight
	self.registryTotalWeight += weight

	if self._pendingMarks[key] ~= nil then
		local pendingValue = self._pendingMarks[key]
		self._pendingMarks[key] = nil
		self:markObserver(key, pendingValue)
	end

	self:_recalculateProgress()
end

function handler:markObserver(key: string, isLoaded: boolean)
	if self.register[key] == nil then
		if self._initialized then
			self._pendingMarks[key] = isLoaded
		end
		warn("Unknown registry key", key)
		return
	end

	local wasLoaded = self.registryLoaded[key] == true
	if wasLoaded == isLoaded then
		return
	end

	self.registryLoaded[key] = isLoaded
	self.register[key].Value = isLoaded

	local weight = self.registryWeights[key] or 0
	if isLoaded then
		self.registryLoadedWeight += weight
	else
		self.registryLoadedWeight -= weight
	end

	self.registryLoadedWeight = clamp(self.registryLoadedWeight, 0, self.registryTotalWeight)
	self:_recalculateProgress()
end


return handler :: Handler