local SoundService = game:GetService("SoundService")
local SoundFolder = SoundService.SFX

--checking if the player has the heavy sound, if yes then we know that he is currently using his heavy attack
return function(char)
	local tool: Tool = char:FindFirstChildWhichIsA("Tool")
	local WeaponSoundFolder = SoundFolder.Weapons[tool.Name]
	
	char.HumanoidRootPart:FindFirstChild(WeaponSoundFolder.Heavy.Name)
end
