return function(enemyChar)
	if enemyChar.HumanoidRootPart:FindFirstChildWhichIsA("BodyVelocity") then
		enemyChar.HumanoidRootPart:FindFirstChildWhichIsA("BodyVelocity"):Destroy()
	end
	local backForce = Instance.new("BodyVelocity")
	backForce.MaxForce = Vector3.new(1, 0, 1) * 30000
	backForce.Velocity = enemyChar.HumanoidRootPart.CFrame.lookVector * -6
	backForce.Parent = enemyChar.HumanoidRootPart
	for count = 1, 4 do
		task.wait(0.1)
		backForce.Velocity *= 0.7
	end
	backForce:Destroy()
end
