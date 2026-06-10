-- MovementLock.lua
local require = require(script.Parent.loader).load(script)

local CooldownController = require("CooldownController")

local MovementLock = setmetatable({}, CooldownController)
MovementLock.__index = MovementLock

function MovementLock.new(character: Model, serviceBag)
	local hrp = character:WaitForChild("HumanoidRootPart")
	local self = setmetatable(CooldownController.new(character, serviceBag), MovementLock)
	self._hrp = hrp
	return self
end

function MovementLock:Add(duration)
	local cd = self:getCD()
	if not cd then
		self:_createCD(cd)
		task.delay(0.2,function()
			local controller = self:getCD()
			controller.Done:Connect(function()
				self:Remove(cd)
			end)
			self._hrp.Anchored = true
		end)
	else
		self:Extend(duration)
	end
end

function MovementLock:Remove()
	local cd = self:getCD()
	if not cd then return end
	self:Cancel()
	self._hrp.Anchored = false
end

return MovementLock
