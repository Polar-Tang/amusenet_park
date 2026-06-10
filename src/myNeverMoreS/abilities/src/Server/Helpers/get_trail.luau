return function(CHAR)
	print()
	local tool: Tool = CHAR:FindFirstChildWhichIsA("Tool")
	if not tool then
		return
	end
	return CHAR:WaitForChild(tool.Name):WaitForChild("BodyAttach"):FindFirstChild("Trail")
end
