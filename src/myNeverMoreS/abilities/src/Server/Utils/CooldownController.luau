local RunService = game:GetService("RunService")
-- CooldownController.lua
-- local SSS = game:GetService("ServerScriptService")

-------------- TESTING ZONE --------------
-- local RS = game:GetService("ReplicatedStorage")
local require = require(script.Parent.loader).load(script)

local Cooldown
if RunService:IsServer() then
	Cooldown = require("Cooldown")
else
	Cooldown = require("CooldownClient")
end

local CooldownController = {}
CooldownController.__index = CooldownController

function CooldownController.new(char: Model, serviceBag)
	-- Binder constructor
	local self = setmetatable({}, CooldownController)

	self._serviceBag = serviceBag
	self.char = char
	local coolDown = serviceBag:GetService(Cooldown)
	self._cooldown = coolDown
	return self
end

-- ...existing code...
function CooldownController:ResetTo(length: number)
	local ourBinder = self:getCD()
	if not ourBinder then
		warn("No cooldown found")
		return
	end

	local cooldown_model = ourBinder:GetCooldownModel()
	if not cooldown_model then
		warn("No cooldown model found")
		return
	end

	-- state.length + state.startTime - now (node_modules/@quenty/cooldown/src/Shared/Model/CooldownModel.lua) waitTIme is always length
	local now = os.clock() + length -- don't know why os.clock return incosistent values
	cooldown_model:SetClock(function()
		return now
	end)
	-- align start+length so remaining becomes remainTime from now
	cooldown_model:SetStartTime(now)

	cooldown_model:SetLength(length)
end

function CooldownController:Extend(duration)
	local ourBinder = self:getCD()
	if not ourBinder then
		warn("No cooldown found")
		return
	end
	local coldown_model = ourBinder:GetCooldownModel()
	if not ourBinder then
		warn("No cooldown found")
		return
	end
	local now = os.clock()
	local endTime = ourBinder:GetEndTime()

	local newEndTime = math.max(endTime, now) + duration
	local startTime = ourBinder:GetStartTime() or now

	coldown_model:SetStartTime(startTime)
	coldown_model:SetLength(newEndTime - startTime)
end

function CooldownController:SetLength(length: number)
	local ourBinder = self:getCD()
	if not ourBinder then
		warn("No cooldown found")
		return
	end
	local coldown_model = ourBinder:GetCooldownModel()
	if not ourBinder then
		warn("No cooldown found")
		return
	end
	coldown_model:SetLength(length)
end

function CooldownController:_createCD(cd: number?)
	local cooldownd = cd or 1
	local char = self.char

	self._inst = Instance.new("NumberValue")
	self._inst.Name = "AttackCooldown"
	self._inst.Value = cooldownd
	self._inst.Parent = char
	self._inst:AddTag("Cooldown")
end

--
function CooldownController:init(cd)
	self:_createCD(cd)
	task.defer(function()
		-- test with self._cooldown and getting directly by the service bag
		self._cooldown:Get(self._inst)
	end)
	--[[
		task.defer(function()
			local cd = Cooldown:Get(self._inst)
			print("Cooldown:", cd)
			print("self._inst.Parent ", self._inst.Parent)
		end)
	]]
end

function CooldownController:getCD()
	if not self._inst then
		return nil
	end
	local controller = self._cooldown:Get(self._inst)
	return controller
end

function CooldownController:isCd()
	return self._inst
end

function CooldownController:Cancel()
	local ourBinder = self:getCD()
	if not ourBinder then
		warn("wtf ")
		return
	end
	-- ourBinder:GetObject():Destroy()
	ourBinder:GetCooldownModel():SetLength(0)
end

function CooldownController:IsReady(): boolean
	local CD = self:getCD()
	return self.currentCD - CD:GetTimePassed() >= 0
end

function CooldownController:Destroy()
	print("AAAAAAAAAAAAAAAAh!")
end

return CooldownController
