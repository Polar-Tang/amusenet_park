local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = RS.Shared.RemoteEvents
local swingEvent = Events.Swing
--||RemoteEvents||--
local Equipment = Events.Equipment

local characterCtxUtils = require(ReplicatedStorage.Shared.Helpers.shared_services.characterCtxUtils)
local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)

--local blockingEvent = Events.Blocking

local serviceBag = _G.ServiceBag

local BinderProvider = serviceBag:GetService(_G.BinderProvider)
local WeaponBinder = BinderProvider:Get("Armed")
local CombatMediator = {}

-- Combat attributes + peephole part tagging for ONE character Model.
-- Called from ServiceRoot's per-character setup, so it runs again on every
-- respawn (attributes/tags die with the old Model).
function CombatMediator.CharacterAdded(char: Model)
	char:SetAttribute("Combo", 1)
	char:SetAttribute("Stunned", false)
	char:SetAttribute("Swing", false)
	char:SetAttribute("Attacking", false)
	char:SetAttribute("IsRagdoll", false)
	char:SetAttribute("Iframes", false)
	char:SetAttribute("IsBlocking", false)
	char:SetAttribute("Blocking", 0)
	char:SetAttribute("Parrying", false)

	-- Tag every body part so the grenade aimer raycasts can exclude all players in
	-- one CollectionService:GetTagged call instead of looping players each frame.
	-- NonStatic marks the part as a moving combatant: the server-side shot
	-- validation (RangeAttack staticOnly cast) excludes everything NonStatic so
	-- its occlusion ray only ever finds real walls, never a latency-displaced
	-- character standing between the shooter and the claimed target.
	local function tagIfPart(descendant: Instance)
		if descendant:IsA("BasePart") then
			CollectionService:AddTag(descendant, Constants.peepholeExclude)
			CollectionService:AddTag(descendant, Constants.NON_STATIC_TAG)
		end
	end
	for _, descendant in char:GetDescendants() do
		tagIfPart(descendant)
	end
	char.DescendantAdded:Connect(tagIfPart)
end

local AttckInvoker = script.Parent.AttckInvoker

--||Event for combat||--
local combatServer = require(AttckInvoker)

swingEvent.OnServerEvent:Connect(combatServer.swingEvent)

--||Equipment||--

Equipment.OnServerEvent:Connect(function(player: Player, data)
	local tool = data.tool
	local has_to_equip = data.has_to_equip
	local char: Model = player.Character or player.CharacterAdded:Wait()

	if not has_to_equip then
		-- Route through the shared helper so client and server destroy
		-- the strategy through the same `UnequiTool` contract.
		characterCtxUtils:UnequipChar(char)
		return
	end

	local r6Name = tostring(tool.Name):lower()
	characterCtxUtils:InitChar(char, r6Name)
end)

local HitboxResponseRemote = Events.HitboxResponseRemote

HitboxResponseRemote.OnServerEvent:Connect(function(player, data)
	local attackID = data.attackID
	local hitTargets = data.character
	local hitPart = data.hitPart

	-- Get the attacker's character
	local character = player.Character
	if not character then
		-- warn("[HitboxServer] Player character not found")
		return
	end

	-- Get weapon binder for this character
	local weapon = WeaponBinder:Get(character)
	if not weapon then
		-- warn("[HitboxServer] Weapon not found for", player.Name)
		return
	end

	-- ✅ Route to the correct promise
	weapon:AddHitToPromise(attackID, hitTargets, hitPart)
end)

return CombatMediator
