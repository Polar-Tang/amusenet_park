local Players = game:GetService("Players")
export type OtherAnims = {
	[string]: string,
}

-- Single editable registry for weapon-agnostic abilities (Slide/Run) and the
-- character's default locomotion / pose / emote / tool animations. The
-- refactored Animate module (src/client/UI/Animate.luau) plays these by name
-- through the AnimationHandler, so editing an id here changes the in-game
-- animation. These are registered once via AnimationHandler:AddAnimations and
-- become *protected defaults*: a weapon equip (registryAnims) can never
-- overwrite them. NOTE: "Idle" is also a key in WeaponsAnims (fist); because
-- this default is protected, the OtherAnims idle always wins and the weapon's
-- own idle is skipped on equip.
local otherAnims: OtherAnims = {
	Slide = "rbxassetid://100441892870847",
	Run = "rbxassetid://139870969802945",

	-- locomotion / pose
	Climb = "http://www.roblox.com/asset/?id=180436334",
	Fall = "http://www.roblox.com/asset/?id=180436148",
	Idle = "rbxassetid://132675939954946",
	Jump = "http://www.roblox.com/asset/?id=125750702",
	Sit = "http://www.roblox.com/asset/?id=178130996",
	Walk = "http://www.roblox.com/asset/?id=180426354",

	-- classic Tool poses
	Toolnone = "http://www.roblox.com/asset/?id=182393478",
	Toolslash = "http://www.roblox.com/asset/?id=129967390",
	Toollunge = "http://www.roblox.com/asset/?id=129967478",

	-- emotes
	Wave = "http://www.roblox.com/asset/?id=128777973",
	Point = "http://www.roblox.com/asset/?id=128853357",
	Dance1 = "http://www.roblox.com/asset/?id=182435998",
	Dance2 = "http://www.roblox.com/asset/?id=182436842",
	Dance3 = "http://www.roblox.com/asset/?id=182436935",
	Laugh = "http://www.roblox.com/asset/?id=129423131",
	Cheer = "http://www.roblox.com/asset/?id=129423030",
}

local function loadAllAnimations(animationController)
	local loadedAnimations = {}

	for animationName, animId in pairs(otherAnims) do
		local animationInstance = Instance.new("Animation")
		animationInstance.Name = animationName
		animationInstance.AnimationId = animId

		loadedAnimations[animationName] = animationController:LoadAnimation(animationInstance)
	end
	print("load anim")
	return loadedAnimations
end

local player_char = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
local animator = player_char:WaitForChild("Humanoid"):WaitForChild("Animator")
loadAllAnimations(animator)

return otherAnims
