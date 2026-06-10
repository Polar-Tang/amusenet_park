-- shared functionalities between the client and server service bag
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponsAnims = require(ReplicatedStorage.Shared.Animations.WeaponsAnims)

local module = {}

function module.createCharNameIns(char: Model, char_name: string)
	local charNameInst = Instance.new("StringValue")
	charNameInst.Value = char_name
	charNameInst.Parent = char
	charNameInst.Name = "CharName"

	return charNameInst
end

function module:InitCharWeapon(char, char_name, binder)
	local weaponHandler = binder
	if not binder then
		local serviceBag = _G.ServiceBag or _G.ServiceBagClient
		local binderProvider = _G.BinderProvider or _G.BinderProviderClient
		local BinderProvider = serviceBag:GetService(binderProvider)

		local WeaponBinder = BinderProvider:Get("Armed")

		if WeaponBinder then
			weaponHandler = WeaponBinder:Get(char)
		end
	end
	
	weaponHandler:registryTool(char_name)
	weaponHandler:EquiTool(char_name)
	local instance = char:FindFirstChild("CharName") or module.createCharNameIns(char, char_name)
	instance.Value = char_name
end

function module:InitCharAnim(char, char_name, binder)
	if not WeaponsAnims[char_name] then
		return
	end

	local animHandler = binder
	if not binder then
		local serviceBag = _G.ServiceBag or _G.ServiceBagClient
		local binderProvider = _G.BinderProvider or _G.BinderProviderClient
		local BinderProvider = serviceBag:GetService(binderProvider)

		local AnimationHandler = BinderProvider:Get("AnimationHandler")
		animHandler = AnimationHandler:Get(char)
	end
	-- Do NOT StopAll here. It stops *every* playing track, including the
	-- protected default locomotion (Run/Walk/Idle), behind Animate's back --
	-- Animate keeps `currentAnim` in sync only for plays/stops it issues itself,
	-- so a track stopped here leaves `currentAnim` stale. The move() loop then
	-- asks for that same anim, the change-guard in playAnimation sees no change
	-- and skips the replay, and locomotion freezes mid-walk on equip.
	-- registryAnims already tears down (and thus stops) the weapon anims it
	-- swaps, and leaves the protected defaults playing uninterrupted (v_07).
	animHandler:registryAnims(WeaponsAnims[char_name])
	-- animHandler:PreloadAnims({ "ADash", "SDash", "WDash", "DDash" })
	char:SetAttribute("char_name", char_name)
end

function module:InitChar(char, char_name)
	self:InitCharAnim(char, char_name) -- init anim handler first
	self:InitCharWeapon(char, char_name)
end

-- Symmetric counterpart of `InitCharWeapon`. Looks up the "Armed" binder
-- for this character and calls `UnequiTool`, which destroys the current
-- strategy and all of its abilities/connections. Both client and server
-- expose the same `UnequiTool` shape (see `WeaponContextBase`), so this
-- works on either side without branching.
function module:UnequipCharWeapon(char, binder)
	local weaponHandler = binder
	if not weaponHandler then
		local serviceBag = _G.ServiceBag or _G.ServiceBagClient
		local binderProvider = _G.BinderProvider or _G.BinderProviderClient
		local BinderProvider = serviceBag:GetService(binderProvider)

		local WeaponBinder = BinderProvider:Get("Armed")
		if WeaponBinder then
			weaponHandler = WeaponBinder:Get(char)
		end
	end
	if not weaponHandler then
		return
	end
	weaponHandler:UnequiTool()

	local instance = char:FindFirstChild("CharName")
	if instance then
		instance.Value = ""
	end
	char:SetAttribute("char_name", nil)
end

function module:UnequipChar(char)
	self:UnequipCharWeapon(char)
end

function module:GetHumanoid()
	local character = self:GetCharacter()
	return character:WaitForChild("Humanoid")
end

return module
