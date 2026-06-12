local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefenseBaseAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Abilities.DefenseBaseAbility)
local AttackBaseAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Abilities.AttackBaseAbility)
local MovementAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Abilities.MovementAbility)
local RangeAttack = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Abilities.RangeAttack)
local ReloadAbility = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Abilities.ReloadAbility)
local RangeAttackClient = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Client.Abilities.RangeAttackClient)
local ReloadAbilityClient = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Client.Abilities.ReloadAbilityClient)
local MovementAbillityClient = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Client.Abilities.MovementAbillityClient)
local AttackBaseClient = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Client.Abilities.AttackBaseClient)

local SharedWeaponBase = {}
SharedWeaponBase.__index = SharedWeaponBase

function SharedWeaponBase.new(data)
	local damn_data = table.clone(data)

	local self = setmetatable(damn_data, SharedWeaponBase)
	return self
end

-- Combat-attribute backstop. Abilities normally clear their own state on the
-- animation's `Ended` signal (see `BaseAbility.resetAtt` and the EndedCon
-- callbacks in CombatConfig). But when an animation is *interrupted* — e.g. a
-- weapon swap tears the descriptor down before `Ended` fires — that cleanup
-- never runs and the attribute stays stuck (the character can end up frozen as
-- "Attacking" / "IsDefending"). A strategy calls this on `Destroy`, so any
-- in-flight combat attribute is forced back to neutral on every swap / unequip
-- / despawn. The weapon spans every ability type, so it clears all of them
-- rather than branching on a single `type`.
function SharedWeaponBase:resetCombatAttributes()
	local character = self.character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and not character:GetAttribute("IsBlocking") then
		humanoid.WalkSpeed = 14
		humanoid.JumpHeight = 6.5
	end

	character:SetAttribute("Attacking", false)
	character:SetAttribute("Swing", false)
	character:SetAttribute("IsDefending", false)
end

function SharedWeaponBase:_createAbilities(attacks)
	local newAttacks = {}
	local isServer = RunService:IsServer()

	for _, spec in pairs(attacks) do
		local config = table.clone(spec.config)
		local externalMethods = table.clone(spec)
		config.character = self.character
		config._serviceBag = self._serviceBag

		local skill

		if isServer then
			config.tool = self.tool

			if config.type == "Movement" then
				continue
			elseif config.type == "Defense" then
				skill = DefenseBaseAbility.new(config)
			elseif config.type == "Attack" then
				skill = AttackBaseAbility.new(config)
			elseif config.type == "Others" then
				skill = MovementAbility.new(config)
			elseif config.type == "Range" then
				skill = RangeAttack.new(config)
			elseif config.type == "Reload" then
				skill = ReloadAbility.new(config)
			else
				continue
			end
		else
			local tool = self.character:FindFirstChildWhichIsA("Tool")
			config.tool = tool

			if config.type == "Range" then
				skill = RangeAttackClient.new(config)
			elseif config.type == "Movement" then
				skill = MovementAbillityClient.new(config)
			elseif config.type == "Attack" then
				skill = AttackBaseClient.new(config)
			elseif config.type == "Reload" then
				skill = ReloadAbilityClient.new(config)
			else
				print("unknown ability ", spec)
				continue
			end
		end

		local key = config.keyCode and config.keyCode.Name or config.key and config.key.Name
		assert(key, "abilty has no key ", config)
		assert(typeof(key) == "string", "'key'", key, "is not string")

		if isServer then
			assert(attacks[key], key .. " is not present in the attacks ", attacks)
		else
			assert(attacks[key] or self.skills[key], key .. " is not present in 'attacks' or 'skills'")
		end

		skill.spec = externalMethods
		for methodName, methodValue in pairs(externalMethods) do
			if methodName ~= "config" and typeof(methodValue) == "function" then
				skill[methodName] = methodValue
			end
		end

		skill:Init(externalMethods)
		self._maid:GiveTask(skill)
		newAttacks[key] = skill
	end
	return newAttacks
end

return SharedWeaponBase
