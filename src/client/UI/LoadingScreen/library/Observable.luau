--!strict

local Observable = {}
Observable.ClassName = "Observable"
Observable.__index = Observable

function Observable.new(onSubscribe)
	assert(type(onSubscribe) == "function", "Bad onSubscribe")

	return setmetatable({
		_onSubscribe = onSubscribe,
	}, Observable)
end

function Observable:Subscribe(fireCallback, failCallback, completeCallback)
	local cleanup = self._onSubscribe(fireCallback, failCallback, completeCallback)
	if cleanup == nil then
		return nil
	end

	if type(cleanup) == "function" then
		return {
			Destroy = cleanup,
		}
	end

	return cleanup
end

return Observable