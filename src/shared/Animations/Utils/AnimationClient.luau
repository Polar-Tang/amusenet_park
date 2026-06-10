-- We play all the animation from here, because its RS, it reaplicate to all clients with no overloads to the server
local Debris = game:GetService("Debris")
local RS = game:GetService("ReplicatedStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local anim = {}
--||Animation Folder||--

------------------------------------------------------------------------------------------------------------------

--local function getHandler(char)
--	local animationHandler = PlayerAnimationHandler:GetHandler(char)
--	animationHandler
--end

local getBInder = function()
	local serviceBag = _G.ServiceBag or _G.ServiceBagClient
	local binderProvider = _G.BinderProvider or _G.BinderProviderClient
	local BinderProvider = serviceBag:GetService(binderProvider)
	local NPCAnimBinder = BinderProvider:Get("AnimationHandler")
	local WeaponBinder = BinderProvider:Get("Armed")
	return { NPCAnimBinder = NPCAnimBinder, WeaponBinder = WeaponBinder }
end

------------------ Equip ------------------
anim.Equip = function(char: Model)
	--print("AnimationsClient required by:", debug.info(2, "sln"))
	--StopAllAnimations(char)

	-- PENDING: an equipping animation should play, onEnded play the idle animation
	local binders = getBInder()
	local AnimationHandler = binders.NPCAnimBinder:Get(char)
	AnimationHandler:LoadAnimation(true, "Equip")

	--EquipAnim[char]:GetMarkerReachedSignal("Equipped"):Connect(
	-- make a higher order function that take the tanimation track as a parameter
	-- PENDING. SUPPORT AN EQUIP ANIMATION WHICH IS A TRASITION TO IDLE

	-- IN SUCH CASE PLAY THIS char:SetAttribute("Swing",true) --so the player can't attack while still equipping
	local onEquipp = function(animTrack)
		char:SetAttribute("Swing", false)
		AnimationHandler:LoadAnimation(true, "Idle")
	end
	AnimationHandler:OnSignal({
		callback = onEquipp,
		animationName = "Equip",
		animationEventName = "Equipped",
	})

	-- IDK WHY THE ORIGINAL AUTHOR MADE THIS, IT HAS NO SENSE, IT REPLAYS AN ANIMATION THAT SHOULD BE LOOPED
	--[[
		local onEnded = function(animTack) --we are actually still keeping the ended in case the player gets hit while equipping
			if char:FindFirstChildWhichIsA("Tool") and char:GetAttribute("Stunned") then --actually checking if we didnt just unequip the weapon while we still equipped it
				animTack:Play()
			end
		end
		
		AnimationHandler:OnSignal({
			callback = onEnded,
			animationName = "Equip",
			animationEventName = "EndedCon"
		})
	]]
end

anim.UnEquip = function(char: Model) --function for UnEquip animation
	local binders = getBInder()
	debug.traceback()
	-- local AnimationHandler = binders.NPCAnimBinder:Get(char)
	-- AnimationHandler:LoadAnimation(true, "UnEquip")
	-- local onUnEquipp = function(animTrack)
	-- 	char:SetAttribute("Swing", false)
	-- 	AnimationHandler:LoadAnimation(false, "Idle")
	-- 	AnimationHandler:LoadAnimation(false, "UnEquip")
	-- 	AnimationHandler:LoadAnimation(false, "Equip")
	-- 	AnimationHandler:ClearAllTheAnims()

	-- 	-- EquipSound.Parent = char:WaitForChild("HumanoidRootPart")
	-- 	-- EquipSound:Play()
	-- 	-- Debris:AddItem(EquipSound, 1)
	-- 	--animTrack:Play()
	-- end
	-- AnimationHandler:OnSignal({
	-- 	callback = onUnEquipp,
	-- 	animationName = "UnEquip",
	-- 	animationEventName = "EndedCon",
	-- })
end

anim.Blocking = function(char: Model)
	local binders = getBInder()

	local AnimationHandler = binders.NPCAnimBinder:Get(char)
	AnimationHandler:LoadAnimation(true, "Blocking")
end

anim.UnBlocking = function(char: Model)
	local binders = getBInder()

	local AnimationHandler = binders.NPCAnimBinder:Get(char)
	AnimationHandler:LoadAnimation(false, "Blocking")
end

anim.JustPlayAnim = function(char: Model, animName: string, state: boolean)
	local binders = getBInder()

	local AnimationHandler = binders.NPCAnimBinder:Get(char)
	AnimationHandler:LoadAnimation(state, animName)
end

anim.DashAnim = function(char, ctx)
	local animName = ctx.animName
	local binders = getBInder()

	-- AnimationHandler:LoadAnimation(true, animName)
	-- Need to use a start event for the dash animation cause there's a delay on preload and the callback starts pretty off

	-- AnimationHandler:OnSignal({
	-- 	callback = dashVFXUtil,
	-- 	animationName = animName,
	-- 	animationEventName = "Start",
	-- })
end

return anim
