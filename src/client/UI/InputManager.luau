local UserInputSer: UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)

local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
char:WaitForChild("Humanoid")

type InputManagerInit = {
	serviceBag: any,
}

local InputManager = {}

local BinderProviderInitialized
local WeaponBinderStarted
local weapon: weaponTypes.WeaponContext

-- One live hold per input so a second InputBegan can't stack heartbeats.
local activeHolds: { [EnumItem]: RBXScriptConnection } = {}

local function isInputHeld(inputType: EnumItem): boolean
	if inputType.EnumType == Enum.UserInputType then
		return UserInputSer:IsMouseButtonPressed(inputType :: any)
	end
	return UserInputSer:IsKeyDown(inputType :: any)
end

-- Runs `onToggle` on press, then again the moment `inputType` is released.
-- Lets a press-and-hold drive a plain toggle from the input layer, so the
-- toggled class (CameraMediator, the Run ability) never learns about hold
-- state. `inputType` may be a mouse button or a keyboard key.
local function holdToToggle(inputType: EnumItem, onToggle: () -> ())
	if activeHolds[inputType] then
		return
	end

	onToggle()

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not isInputHeld(inputType) then
			onToggle()
			connection:Disconnect()
			activeHolds[inputType] = nil
		end
	end)
	activeHolds[inputType] = connection
end

local function ensureWeapon()
	if not _G.BinderProvider then
		return false
	end
	if not BinderProviderInitialized then
		BinderProviderInitialized = _G.ServiceBag:GetService(_G.BinderProvider)
	end
	if not WeaponBinderStarted then
		WeaponBinderStarted = BinderProviderInitialized:Get("Armed")
	end
	-- Respawn replaces the character Model; the old bound class is destroyed
	-- on untag, so a cached context must be re-resolved against the live char.
	if not weapon or weapon.Char ~= plr.Character then
		weapon = WeaponBinderStarted:Get(plr.Character)
		_G.PlayerWeaponBinder = weapon
	end
	if not weapon or not weapon:GetStrategy() then
		return false
	end
	return true
end

function InputManager.Init(data: InputManagerInit)
	local m1Hold = Instance.new("BoolValue")
	m1Hold.Name = "m1Hold"
	m1Hold.Value = false
	m1Hold.Parent = plr

	debug.profilebegin("inputManage")
	UserInputSer.InputBegan:Connect(function(input: InputObject, IsTyping)
		if IsTyping then
			return
		end

		if not ensureWeapon() then
			return
		end

		-- Q modifier for movement skills
		if UserInputSer:IsKeyDown(Enum.KeyCode.LeftControl) then
			weapon:Execute(Enum.KeyCode.LeftControl, { direction = "forward" })
			return
		end
		if UserInputSer:IsKeyDown(Enum.KeyCode.Space) then
			weapon:Execute(Enum.KeyCode.LeftControl, { stop = true })
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			holdToToggle(Enum.UserInputType.MouseButton2, function()
				weapon:ToggleFirstPerson()
			end)
			return
		end

		if input.KeyCode == Enum.KeyCode.LeftShift then
			holdToToggle(Enum.KeyCode.LeftShift, function()
				weapon:Execute(Enum.KeyCode.LeftShift)
			end)
			return
		end

		local command = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			m1Hold.Value = true
			command = input.UserInputType
		end
		weapon:Execute(command)
	end)

	UserInputSer.InputEnded:Connect(function(input, isTyping)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			m1Hold.Value = false
		end
	end)
	debug.profileend()

end

return InputManager
