local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local windVFX = RS.Shared.Effects.winds
local Power_dome = windVFX.power_up_dome
local winds = windVFX.winds


function ThrowOctagonalWinds(currentPosition)
	for i = 1, 8 do
		local wind = winds:Clone()

		-- Horizontal angle around the circle
		local horizontalAngle = (i / 8) * math.pi * 2

		-- Vertical angle for hemisphere (0 to 90 degrees)
		-- You can adjust this to control how high up the dome the winds appear
		local verticalAngle = math.pi / 4 -- 45 degrees - adjust between 0 and math.pi/2

		-- Calculate position on hemisphere surface
		local radius = 5
		local offset = Vector3.new(
			math.cos(horizontalAngle) * math.cos(verticalAngle) * radius,
			math.sin(verticalAngle), -- Y component for height
			math.sin(horizontalAngle) * math.cos(verticalAngle) * radius
		)

		wind.Position = currentPosition + offset

		-- Orient the wind to point outward along the dome surface
		-- The wind should face away from center, tangent to the sphere
		local outwardDirection = (wind.Position - currentPosition).Unit
		wind.CFrame = CFrame.lookAt(wind.Position, wind.Position + outwardDirection)
		wind.Parent = workspace

		-- Animate wind moving outward along the hemisphere trajectory
		local finalOffset = offset.Unit * (radius * 10)
		local windTween =
			TweenService:Create(wind, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = currentPosition + finalOffset,
				Transparency = 1,
			})
		windTween:Play()

		game:GetService("Debris"):AddItem(wind, 0.6)
	end
end

local function _ExpandDomePart(part, dome)
	local originalSizes = {
		["Base"] = Vector3.new(84.957, 4.96, 91.099),
		["DustWind"] = Vector3.new(65.868, 34.496, 72.463),
		["Dome"] = Vector3.new(64.967, 32.483, 66.633),
	}
	dome.Parent = workspace

	local DUR = 0.5
	local tweenInfo = TweenInfo.new(DUR, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local goal = {
		Size = originalSizes[part.Name],
		Transparency = 1,
	}

	local tween = TweenService:Create(part, tweenInfo, goal)
	tween:Play()
end

return function(currentPosition)
    -- First set the dome clone
	local dome = Power_dome:Clone()
	dome:ScaleTo(0.1)
	

	--_SetDomePosition()
    do
        for _, part in ipairs(dome:GetDescendants()) do
            task.spawn(function()
                if part:IsA("Part") or part:IsA("MeshPart") then
                    part.Position = currentPosition
                end
            end)
        end
    end
	-- dome.Parent = Workspace
    

    for _, part in ipairs(dome:GetDescendants()) do
		task.spawn(function()
			if part:IsA("Part") or part:IsA("MeshPart") then
				_ExpandDomePart(part, dome)
			end
		end)
	end
	ThrowOctagonalWinds(currentPosition)
	game:GetService("Debris"):AddItem(dome, 0.5)
end
