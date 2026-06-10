--||Service||--
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Listen for tools added to the backpack

-- initial backpack tools

local HitboxClass = require(ReplicatedStorage.Shared.HitboxClass)
-- Remotes events (i got the code smell to migrate this)
local Events = ReplicatedStorage.Shared.RemoteEvents
local HitboxResponseRemote = Events.HitboxResponseRemote

local _ = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()

-- This event is called in the server after it has Execute() the ability
HitboxResponseRemote.OnClientEvent:Connect(function(attackInfo)
	local hitboxes = attackInfo.hitboxes
	for _, hitbox in ipairs(hitboxes) do
		local weapon = hitbox.Weapon

		if typeof(weapon) == "table" then
			local pos = weapon.Pos
			local root_hitbox = Instance.new("Part")
			root_hitbox.Transparency = 1
			root_hitbox.Position = pos
			root_hitbox.CanCollide = false
			root_hitbox.Anchored = true
			root_hitbox.Size = hitbox.Size
			root_hitbox.Parent = workspace
			if weapon.CF then
				root_hitbox.CFrame = weapon.CF
			end
			weapon = root_hitbox
			Debris:AddItem(root_hitbox, hitbox.Time)
			-- print(weapon)
		end

		-- Create overlapParams
		local newParmas = OverlapParams.new()
		newParmas.FilterType = Enum.RaycastFilterType.Exclude
		newParmas.FilterDescendantsInstances = { hitbox.Attacker }
		local newHitbox = HitboxClass.new(hitbox.Shape, {
			root = weapon,
			size = hitbox.Size,
			duration = hitbox.Time,
			interval = 0.05,
			velocityPrediction = true,
			dotProductFilter = {
				dotProduct = 0.1,
				referenceVector = hitbox.referenceVector,
				sourcePosition = hitbox.sourcePosition,
			},
			-- debug = true,
			hitboxId = hitbox.attackID,
			HitMode = hitbox.HitMode,
			overlapParams = newParmas,
		})
		newHitbox.OnHit:Connect(function(character, hitPart)
			-------TEST-------

			HitboxResponseRemote:FireServer({ attackID = attackInfo.attackID, character = character, hitPart = hitPart })
		end)

		newHitbox:Start()
	end
end)

return {}
--[[
Allright, please start with the fix plan, i totally agree with, i'm not sure the way you call this mispelled method `UnequiTool` and destroy strategy but we can explicitly call it from CharactersCTXUtils because this way we can dry, but server and client must agree about interface
### Server
THere's a lot of old code you may find and deson't make sense, it's okay if you remove it, please ensure to keep updated the WeaponContext type, there's a src/myNeverMoreS/weapon/src/Server/types/weaponTypes.luau but as i previously said, both must share shape so this type should actually extends from src/myNeverMoreS/weapon/src/Shared/types/weaponTypes.luau's WeaponContext but i'm not sure if this is duplicating the source of thruth with mismatched fields or something, anyway as both types may (slightly) differ we should have a base shared WeaponContext from which server and client do extend from. Please enforce the explicit types in self arguments method if needed, this way we can be sure if we need to add a new field. 
### CLient
I agree with you've said, go ahead with your plan and please document it with small comments
]]