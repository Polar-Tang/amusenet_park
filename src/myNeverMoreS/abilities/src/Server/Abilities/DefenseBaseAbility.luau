local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EffectTypes = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectTypes)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Server.types.weaponTypes)
-- Abstract class for Defense abilities
local require = require(script.Parent.loader).load(script)
local BaseAbility = require("BaseAbility")
local Signal = require("Signal")

local DefenseAbility = setmetatable({}, BaseAbility)
DefenseAbility.__index = DefenseAbility
export type BaseAbilityConstructor = weaponTypes.BaseAbilityConstructor
export type DefenseAbility = weaponTypes.DefenseAbility

function DefenseAbility.new(config: BaseAbilityConstructor)
	local self = setmetatable(BaseAbility.new(config), DefenseAbility)

	-- Observable for defense state
	self._activeSignal = Signal.new()
	self._maid:GiveTask(self._activeSignal)

	self.isActive = false
	return self :: DefenseAbility
end

function DefenseAbility.Deactivate(self: DefenseAbility)
	self.isActive = false
	self._activeSignal:Fire(false)

	-- Remove from weapon's defense chain
	self._weaponHandler:DeactivateDefense(self)
end

function DefenseAbility.SetAttributes(self: DefenseAbility)
	local CHAR = self.character
	local HUM = self.humanoid

	CHAR:SetAttribute("IsDefending", true)

	HUM.WalkSpeed = 7
	HUM.JumpHeight = 0
end

function DefenseAbility.Execute(self: DefenseAbility, params)
	local CHAR = self.character
	if params.check(self) then
		return
	end

	if CHAR:GetAttribute("Attacking") or CHAR:GetAttribute("Swing") or CHAR:GetAttribute("IsDefending") then
		return
	end

	if self:GetCD() then
		return
	end
	-- start attack
	self:StartCD()
	--Settin attr
	self:SetAttributes()

	self:_countAttack()

	local animHandler = self._animHandler

	local animName = params.get_anim_name and params.get_anim_name() or self._animName
	animHandler:LoadAnimation(true, animName)

	self._additiona_deactivate = params._additiona_deactivate(self)

	self._process = params._execute(self)
end

-- link the handler to the chain, should be called in every :Execute()
function DefenseAbility.Activate(self: DefenseAbility)
	self.isActive = true

	self._weaponHandler:SetActiveDefense(self)
end

function DefenseAbility.Process(self: DefenseAbility, context: EffectTypes.effectHitCtx)
	return self:_process(context)
end

function DefenseAbility._GuardBreak(self: DefenseAbility): boolean?
	local char = self.character

	local animHandler = self._animHandler
	animHandler:LoadAnimation(true, "GuardBreak")

	-- CHANGE THE PLAYER UI
	local enemyPlr = game:GetService("Players"):GetPlayerFromCharacter(char)
	if enemyPlr then
		ReplicatedStorage.Shared.RemoteEvents.VFX:FireClient(enemyPlr, "GuardBreakCamera")
		enemyPlr.PlayerGui.BlockingUi.MainFrame.Visible = false
		enemyPlr.PlayerGui.BlockingUi.MainFrame.Bar.Size = UDim2.new(0, 0, 1, 0)
	end

	-- print("enemyH ", enemyH)
	-- stunt_client(selfHumanoid, 3)
	print("stunt comming soon")

	self:Stop()
	return true
end

function DefenseAbility.Stop(self: DefenseAbility)
	self:_deactivate()
	-- TODO set this as a needed argument for the defense abilities
	self:resetAtt()
end

function DefenseAbility._deactivate(self: DefenseAbility)
	self.isActive = false
	self._weaponHandler:ClearActiveDefense(self.priority)
	-- Stop animation, etc.
	self:_additiona_deactivate()
end

function DefenseAbility.Destroy(self: DefenseAbility)
	self:Deactivate()
	self._maid:DoCleaning()
end

return DefenseAbility
