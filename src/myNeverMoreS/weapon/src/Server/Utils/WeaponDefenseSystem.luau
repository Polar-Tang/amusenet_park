--[=[
    WeaponDefenseSystem using Observables
]=]
local require = require(script.Parent.loader).load(script)
local Maid = require("Maid")
local Rx = require("Rx")
local Signal = require("Signal")

local WeaponDefenseSystem = {}
WeaponDefenseSystem.__index = WeaponDefenseSystem

function WeaponDefenseSystem.new(weapon)
	local self = setmetatable({}, WeaponDefenseSystem)

	self._weapon = weapon
	self._maid = Maid.new()

	-- Active defense abilities (with their observables)
	self._activeDefenses = {} -- { [defenseAbility] = true }

	return self
end


-- Process attack through active defenses
function WeaponDefenseSystem:ProcessAttack(initialContext)
	local ctx = initialContext
	for _, modifier in ipairs(self._activeDefenses) do 
		ctx = modifier:Process(ctx)
		if ctx.blocked then 
			return
		end
	end
	self._weapon:TakeHit(ctx)
	-- every ability of type Defense has ObserveDefense method
	--[[
	-- If no defenses, go straight to damage
	if #defenseObservables == 0 then
		self:ObserveIncomingAttacks()
			:Pipe({
				Rx.take(1),
			})
			:Subscribe(function(ctx)
				self._weapon:TakeHit(ctx)
			end)

		self._incomingAttackSignal:Fire(initialContext)
		return
	end
	print("defenseObservables ", defenseObservables)
	--|| DEFENSE CHAIN ||--
	Rx.from(self._activeDefenses)
	:Pipe({
		Rx.reduce(function(context, modifier)
			return modifier:Process(context)
		end, initialContext)
	})
	:Subscribe(function(finalContext)
		print(finalContext)
	end)
	]]

	-- self._incomingAttackSignal:Fire(initialContext)
end

-- Add active defense
function WeaponDefenseSystem:ActivateDefense(defenseAbility)
	self._activeDefenses[defenseAbility] = true
end

-- Remove active defense
function WeaponDefenseSystem:DeactivateDefense(priority)
	for index, desc in ipairs(self._activeDefenses) do
		if desc.priority == priority then
			table.remove(self._activeDefenses, index)
		end
	end
end

function WeaponDefenseSystem:SetActiveDefense(defenseAbility)
	-- Just store the ability directly, sorted by priority
	table.insert(self._activeDefenses, defenseAbility)

	table.sort(self._activeDefenses, function(a, b)
		return a.priority < b.priority
	end)
end

function WeaponDefenseSystem:Destroy()
	self._maid:DoCleaning()
end

return WeaponDefenseSystem
