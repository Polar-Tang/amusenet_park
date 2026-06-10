-- PromiseRegistry.lua
local PromiseRegistry = {}
PromiseRegistry.__index = PromiseRegistry

export type hitData = {
	target: Instance,
	hitPart: BasePart,
}

export type pendingPromise = {
	resolve: (hits: {hitData}) -> (),
	reject: (...any) -> (),
	scopeMaid: any,
	timestamp: number,
	hits: {hitData},
	processedTargets: {[Instance]: boolean},
}

function PromiseRegistry.new()
	local self = setmetatable({
		_pendingPromises = {} :: pendingPromise , -- [attackID] = {resolve, reject, scopeMaid}
	}, PromiseRegistry)

	return self
end

function PromiseRegistry:Register(data)
	self._pendingPromises[data.attackID] = {
		resolve = data.resolve,
		reject = data.reject,
		scopeMaid = data.scopeMaid,
		timestamp = os.clock(),
		hits = {},
		processedTargets = {},
		attackType = data.attackType, -- ✅ Store attack type
	}
	-- Timeout, resolve with the targets

	if data.attackType == "AOE" then
		if not data.delay_cb_number then 
			print("there's no delay_cb_number")
		end
		task.delay(data.delay_cb_number or 0.5, function()
			if self._pendingPromises[data.attackID] then
				self:Resolve(data.attackID)
			end
		end)
	end
end

function PromiseRegistry:Resolve(attackID)
	local promise = self._pendingPromises[attackID]
	if not promise then
		return false
	end

	promise.resolve(promise.hits)
	promise.scopeMaid:DoCleaning()
	self._pendingPromises[attackID] = nil

	return true
end

function PromiseRegistry:AddHit(attackID, hitTarget, hitPart)
	local promise = self._pendingPromises[attackID]
	if not promise then
		return false
	end

	if promise.processedTargets[hitTarget] then
		return false
	end
	promise.processedTargets[hitTarget] = true

	local hitData = {
		target = hitTarget,
		hitPart = hitPart,
	}

	table.insert(promise.hits, hitData)
	
	if promise.attackType == "ST" then
		self:Resolve(attackID)
	end

	return true
end

function PromiseRegistry:Reject(attackID, ...)
	local promise = self._pendingPromises[attackID]
	if not promise then
		return false
	end
	promise.reject(...)
	promise.scopeMaid:DoCleaning()
	self._pendingPromises[attackID] = nil

	return true
end

function PromiseRegistry:Cancel(attackID)
	local promise = self._pendingPromises[attackID]
	if promise then
		promise.scopeMaid:DoCleaning()
		self._pendingPromises[attackID] = nil
	end
end

function PromiseRegistry:CancelAll()
	for attackID, promise in pairs(self._pendingPromises) do
		promise.scopeMaid:DoCleaning()
	end
	self._pendingPromises = {}
end

return PromiseRegistry
