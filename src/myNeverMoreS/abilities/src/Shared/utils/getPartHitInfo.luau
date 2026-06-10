local HitPartInfo = {}
HitPartInfo.__index = HitPartInfo

export type HitPartInfo = {
	-- fields
	inst: BasePart,
	parentModel: Model,
	lastParent: Instance,
	limb: Instance,
	limbName: string,
	humanoid: Humanoid,
	-- methods
	checkAccesoryLimb: (self: HitPartInfo, instance: Instance) -> string?,
	findParentHumanoid: (self: HitPartInfo) -> Humanoid?,
	findLimb: (self: HitPartInfo) -> Instance?,
	Destroy: (self: HitPartInfo) -> (),
}

function HitPartInfo.new(part: BasePart): HitPartInfo
	local self = setmetatable({}, HitPartInfo)
	self.inst = part
	self.parentModel = nil
	self.lastParent = nil
	self.limb = nil
	self.limbName = nil
	self.humanoid = nil
	return self
end

local R6Limbs = {
	["Head"] = true,
	["Torso"] = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
	["HumanoidRootPart"] = true,
}

local function isR6Limb(instance): boolean
	return R6Limbs[instance.Name] == true
end

function HitPartInfo.checkAccesoryLimb(self: HitPartInfo, instance: Instance): string?
	if instance:IsA("Accessory") then
		local isHead = instance.AccessoryType == Enum.AccessoryType.Hair
			or instance.AccessoryType == Enum.AccessoryType.Hat
			or instance.AccessoryType == Enum.AccessoryType.Face
			or instance.AccessoryType == Enum.AccessoryType.Eyebrow
			or instance.AccessoryType == Enum.AccessoryType.Eyelash
		if isHead then
			self.limbName = "Head"
			return "Head"
		end
	end
	return nil
end

-- look if the part is at least three times nested, if its more than that fuck up
function HitPartInfo.init(self: HitPartInfo)
	local lastParent
	if isR6Limb(self.inst) then
		self.limb = self.inst
	end
	self:checkAccesoryLimb(self.inst)
	-- Try to find humanoid for nested instances
	for i = 1, 3 do
		if not lastParent then
			lastParent = self.inst.Parent
		end
		local hum = lastParent:FindFirstChildOfClass("Humanoid")
		self:checkAccesoryLimb(lastParent)

		-- We get the model assuming its parented to the humanoid
		if hum then
			self.parentModel = lastParent
			self.humanoid = hum
			return
		else
			if isR6Limb(lastParent) then
				self.limb = lastParent
			end
		end
		-- We assume the last part that is not the model is the limb
		self.lastParent = lastParent
		lastParent = lastParent.Parent
	end
	return nil
	-- inst.Parent:FindFirstChildOfClass("Humanoid")
end

function HitPartInfo.findParentHumanoid(self: HitPartInfo): Humanoid?
	return self.humanoid
end
-- Please do a bolean that check if instance.Name is equal to any limb name a r6 should have
function HitPartInfo.findLimb(self: HitPartInfo)
	if self.limbName and not self.limb then
		self.limb = self.parentModel:FindFirstChild(self.limbName)
	end
	return self.limb
end

function HitPartInfo.Destroy(self: HitPartInfo)
	setmetatable(self, nil)
	self = nil
end

return HitPartInfo
