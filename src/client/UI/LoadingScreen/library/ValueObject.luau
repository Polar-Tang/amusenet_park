--!strict

local Observable = require(script.Parent.Observable)
local Signal = require(script.Parent.Signal)

local ValueObject = {}
ValueObject.ClassName = "ValueObject"
ValueObject.__index = ValueObject

export type ValueObject<T> = any

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

function ValueObject:GetValue()
	return rawget(self, "_value")
end

function ValueObject:SetValue(value)
	ValueObject._applyValue(self, value)
	return function()
	end
end

function ValueObject:Observe()
	return Observable.new(function(fireCallback)
		if fireCallback then
			fireCallback(self.Value)
		end

		return self.Changed:Connect(function(newValue)
			if fireCallback then
				fireCallback(newValue)
			end
		end)
	end)
end

return ValueObject