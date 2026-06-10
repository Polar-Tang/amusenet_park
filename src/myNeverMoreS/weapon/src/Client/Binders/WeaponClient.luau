--[=[
	@class WeaponClient

	The "Armed" binder, client side. One instance per tagged character; it
	owns the *context* (camera mediator) and delegates per-weapon behavior
	to the currently-equipped `WeaponStrategy` stored in `self._weapon`.

	Same lifecycle contract as the server `Weapon` binder:
	  * `EquiTool(name)` destroys the previous strategy before installing
	    the new one (otherwise every ability's `_inputConnection`,
	    `m1Hold` listener, recoil controller etc. leaks until the
	    character is untagged).
	  * `UnequiTool()` destroys the current strategy and clears `_weapon`.
	  * `Destroy()` runs when the character is untagged.

	Called from `characterCtxUtils:InitChar` / `UnequipChar` so both
	sides stay symmetric.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)
local CombatConfig = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.CombatConfig)
-- Must resolve the SAME live Instance that ServiceRoot registers with the
-- serviceBag (the PlayerScripts copy), not the StarterPlayer template tree.
-- A ModuleScript is cached per Instance, so requiring it from the template
-- yields a different table -> serviceBag sees an unregistered service and
-- throws "Cannot initialize service after start" when this binder constructs.
local CameraMediator =
	require(Players.LocalPlayer.PlayerScripts.Client.cameraHandlers.camerasStates.CameraMediator)

local require = require(script.Parent.loader).load(script)

local BaseObject = require("BaseObject")
local Weapon = {}
Weapon.__index = Weapon

local Strategies = {
	["fist"] = require("FistClient"),
	["gun"] = require("GunClient"),
	["ak-47"] = require("Ak_47Client"),
	grenade = require("GrenadeClient"),
}

function Weapon.new(char: Model, serviceBag): weaponTypes.WeaponContextClient
	local self = setmetatable(BaseObject.new(char), Weapon)
	self.Char = char
	self._weapon = nil
	self._tool = nil
	self._aimPosition = nil
	self._serviceBag = serviceBag
	self._cameraMediator = serviceBag:GetService(CameraMediator)
	self.Humanoid = char:WaitForChild("Humanoid")

	self._rigtArm = char:WaitForChild("Right Arm")

	return (self :: any) :: weaponTypes.WeaponContextClient
end

function Weapon.ToggleFirstPerson(self: weaponTypes.WeaponContextClient)
	local currentStrategy = self._weapon
	if not currentStrategy then
		return
	end
	local mainAttack = currentStrategy.attacks[Enum.UserInputType.MouseButton1.Name]

	-- we'll use this as long as it does fit well
	if mainAttack and mainAttack.type == "Range" then
		self._cameraMediator:ToggleFirstPerson()
	end
end

function Weapon.Execute(self: weaponTypes.WeaponContextClient, action, params)
	if not self._weapon then
		return
	end
	self._weapon:Execute(action, params)
end

-- Install a new strategy. Tears down any previously-installed strategy
-- first to avoid stacking ability connections across swaps.
function Weapon.EquiTool(self: weaponTypes.WeaponContextClient, toolName: string)
	if not toolName or typeof(toolName) ~= "string" then
		warn("invalid weapon ", toolName)
		return
	end
	if not Strategies[toolName] then
		warn("Weapon " .. toolName .. " not found")
		return
	end

	-- Tear down the previous strategy. Each ability is `GiveTask`'d into
	-- the strategy's `_maid` by `SharedWeaponBase._createAbilities`, so its
	-- `Destroy` cascades into every ability's `_maid:DoCleaning()`.
	if self._weapon then
		self._weapon:Destroy()
		self._weapon = nil
	end

	-- Run the previous weapon's equip-cleanup (e.g. the grenade aimer teardown)
	-- before installing the next strategy.
	if self._onEquipCleanup then
		self._onEquipCleanup()
		self._onEquipCleanup = nil
	end

	self.tool_name = toolName
	self._weapon = Strategies[toolName].new(self.Char, self._serviceBag)
	if self._weapon and self._weapon.Init then
		self._weapon:Init()
	end
	-- Init only constructs the abilities; Start kicks off their always-on
	-- runtime (e.g. the gun's continuous auto-aim scan). Separate phase so
	-- construction stays side-effect-free — see AbstractStrategy:Start.
	if self._weapon and self._weapon.Start then
		self._weapon:Start()
	end

	-- Capture the Tool + its AimPosition attachment once on equip so per-frame
	-- consumers (handHeadCamera) can read them without walking the character
	-- tree every step.
	self._tool = self.Char:FindFirstChildOfClass("Tool")
	self._aimPosition = self._tool and self._tool:FindFirstChild("AimPosition", true) or nil

	-- Per-weapon client equip hook (CombatConfig.onEquipCBClient). May return a
	-- teardown closure that we run on the next swap / unequip / destroy.
	local config = CombatConfig:getweapon(toolName)
	if config and config.onEquipCBClient then
		self._onEquipCleanup = config.onEquipCBClient(self)
	end
end

-- Destroy the current strategy without re-installing one. Used when the
-- player drops their tool; safe to call when no strategy is equipped.
function Weapon.UnequiTool(self: weaponTypes.WeaponContextClient)
	if self._onEquipCleanup then
		self._onEquipCleanup()
		self._onEquipCleanup = nil
	end
	if not self._weapon then
		return
	end
	self._weapon:Destroy()
	self._weapon = nil
	self.tool_name = nil
	self._tool = nil
	self._aimPosition = nil
end

function Weapon.GetAimPosition(self: weaponTypes.WeaponContextClient): Attachment?
	return self._aimPosition
end

function Weapon.GetTool(self: weaponTypes.WeaponContextClient): Tool?
	return self._tool
end

-- Reads gripC0 from CombatConfig rather than the live RightGrip Motor6D.
-- RightGrip does not exist yet when EquiTool runs (Roblox creates it async
-- when Tool is parented), so reading Motor6D.C0 there always errors.
function Weapon.GetGripC0(self: weaponTypes.WeaponContextClient): CFrame
	if not self.tool_name then
		return CFrame.identity
	end
	local data = CombatConfig:getweapon(self.tool_name)
	return (data and data.gripC0) or CFrame.identity
end

function Weapon.GetCenterAimToCamera(self: weaponTypes.WeaponContextClient): boolean
	if not self.tool_name then
		return false
	end
	local data = CombatConfig:getweapon(self.tool_name)
	return data ~= nil and data.centerAimToCamera == true
end

function Weapon.GetAction(self: weaponTypes.WeaponContextClient, action)
	if not self._weapon then
		return nil
	end
	return self._weapon:GetAction(action)
end

function Weapon.GetStrategy(self: weaponTypes.WeaponContextClient)
	return self._weapon
end

function Weapon.registryTool(self: weaponTypes.WeaponContextClient, toolName: string)
	self.tool_name = toolName
end

-- Called by the binder when the character is untagged (player despawn /
-- respawn). `MaidTaskUtils.doTask` in the binder dispatches here.
function Weapon.Destroy(self: weaponTypes.WeaponContextClient)
	if self._onEquipCleanup then
		self._onEquipCleanup()
		self._onEquipCleanup = nil
	end
	if self._weapon then
		self._weapon:Destroy()
		self._weapon = nil
	end
	self._tool = nil
	self._aimPosition = nil
end

return Weapon
