return function(char, enemyChar): boolean
	local RootPart = enemyChar.HumanoidRootPart
	local AttackDirection = (char.HumanoidRootPart.Position - RootPart.Position).Unit
	local FrontDirection = RootPart.CFrame.LookVector
	local Direction = math.acos(AttackDirection:Dot(FrontDirection)) < math.rad(90)

	if not Direction then
		--print("anywhere else")
		return false
	else
		--print("Ifront")
		return true
	end
end