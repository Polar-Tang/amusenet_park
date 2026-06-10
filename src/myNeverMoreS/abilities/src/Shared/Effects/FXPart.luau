-- FXPart.lua
-- Reusable VFX Part with extendable behaviors

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local FXPart = {}
FXPart.__index = FXPart

local function assignTo(props, part)
	for k, v in pairs(props) do
		-- if props.Parent then 
		-- 	continue
		-- end
		if v ~= nil then
			part[k] = v
		end
	end
end

function FXPart.new(params)
	local self = setmetatable({}, FXPart)
	local part
	params = params or {}
	self.Params = params
	if params.template then
		part = params.template:Clone()
	else
		part = Instance.new("Part")
	end
	if params.props then
		assignTo(params.props, part)
		-- part.Parent = params.props.Parent -- Ensure doing this last
	end

	self.Part = part

	-- Optional lifetime
	if params.lifetime then
		Debris:AddItem(part, params.lifetime)
	end

	-- Optional behaviors
	self:_applyBehaviors()
	return self
end

function FXPart:_applyBehaviors()
	local p = self.Params

	if p.sink then
		self:Sink(p.sink)
	end

	if p.fade then
		self:Fade(p.fade)
	end
	if p.scale then
		self:Scale(p.scale)
	end
end

function FXPart:Sink(options)
	options = options or {}

	local delayTime = options.delay or 3
	local depth = options.depth or 2
	local duration = options.duration or 1

	task.delay(delayTime, function()
		if not self.Part or not self.Part.Parent then
			return
		end

		local goal = {
			Position = self.Part.Position - Vector3.new(0, depth, 0),
		}

		local tween = TweenService:Create(
			self.Part,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			goal
		)

		tween:Play()
	end)
end

function FXPart:Fade(options)
	options = options or {}

	local delayTime = options.delay or 0
	local duration = options.duration or 1

	task.delay(delayTime, function()
		if not self.Part or not self.Part.Parent then
			return
		end

		TweenService:Create(self.Part, TweenInfo.new(duration), { Transparency = 1 }):Play()
	end)
end

function FXPart:Scale(options)
	options = options or {}

	local delayTime = options.delay or 0
	local duration = options.duration or 1
	local easingStyle = options.easingStyle or Enum.EasingStyle.Quad
	local easingDirection = options.easingDirection or Enum.EasingDirection.Out
	task.delay(delayTime, function()
		local tweenInfo = TweenInfo.new(duration, easingStyle, easingDirection)
		TweenService:Create(self.Part, tweenInfo, { Size = self.Part.Size * options.scaleBy }):Play()
	end)
end

return FXPart
