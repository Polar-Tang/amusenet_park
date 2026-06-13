--[=[
	@function resolveHitParts

	Allocation-free replacement for the old per-ray `getPartHitInfo` object.

	Given the BasePart a ray hit, walks up to three parents looking for the
	owning Humanoid and identifies the limb that was struck (an R6 limb part, or
	the "Head" limb when a head accessory was hit). Returns `(humanoid, limb)` —
	no table, no metatable, no `:Destroy()`. This runs once per ray on the
	hottest combat path, so it must not churn garbage.

	Behavior mirrors the previous `getPartHitInfo:init()/findParentHumanoid()/
	findLimb()` exactly: the limb falls back to `parentModel:FindFirstChild(name)`
	only when a humanoid (and therefore the model) was found.
]=]

local R6Limbs = {
	["Head"] = true,
	["Torso"] = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
	["HumanoidRootPart"] = true,
}

local function isR6Limb(instance: Instance): boolean
	return R6Limbs[instance.Name] == true
end

-- A head accessory (hair/hat/face/...) counts as a Head hit even though the
-- accessory part itself is not an R6 limb.
local function accessoryLimbName(instance: Instance): string?
	if instance:IsA("Accessory") then
		local accessoryType = instance.AccessoryType
		local isHead = accessoryType == Enum.AccessoryType.Hair
			or accessoryType == Enum.AccessoryType.Hat
			or accessoryType == Enum.AccessoryType.Face
			or accessoryType == Enum.AccessoryType.Eyebrow
			or accessoryType == Enum.AccessoryType.Eyelash
		if isHead then
			return "Head"
		end
	end
	return nil
end

local function resolveHitParts(part: BasePart): (Humanoid?, BasePart?)
	local limb: BasePart? = if isR6Limb(part) then part else nil
	local limbName: string? = accessoryLimbName(part)

	local current: Instance? = part.Parent
	local parentModel: Instance? = nil
	local humanoid: Humanoid? = nil

	for _ = 1, 3 do
		if not current then
			break
		end

		local hum = current:FindFirstChildOfClass("Humanoid")
		limbName = accessoryLimbName(current) or limbName

		if hum then
			parentModel = current
			humanoid = hum
			break
		elseif isR6Limb(current) then
			limb = current :: BasePart
		end

		current = current.Parent
	end

	if limbName and not limb and parentModel then
		limb = parentModel:FindFirstChild(limbName) :: BasePart?
	end

	return humanoid, limb
end

return resolveHitParts
