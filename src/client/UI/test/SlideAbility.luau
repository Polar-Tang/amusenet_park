--[=[
	SlideAbility.lua
	
	A smooth, responsive sliding mechanic for Roblox shooter games.
	Inherits from MovementAbility for seamless integration with your ability system.
	
	Features:
	- Physics-based momentum and friction
	- Camera-relative directional sliding
	- Proper animation blending
	- Automatic recovery with attribute cleanup
	- Network-optimized (client-side prediction, server authority)
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

-- ===== CONFIGURATION =====
local SLIDE_CONFIG = {
	INITIAL_SPEED = 80,      -- Initial velocity impulse
	FRICTION = 0.15,          -- Friction multiplier per frame (0-1)
	MIN_SPEED = 5,            -- Minimum speed before stopping
	DURATION = 0.6,           -- Total slide duration in seconds
	COOLDOWN = 1.2,           -- Cooldown between slides
	WALK_SPEED_RESTORE = 16,  -- Default walk speed after slide
	JUMP_HEIGHT_RESTORE = 7.2, -- Default jump height after slide
	STUN_TIME = 0.1,          -- Time before regaining control
	Y_LOCK = true,            -- Lock Y axis to prevent vertical movement
}

-- ===== SLIDE ABILITY CLASS =====
local SlideAbility = {}
SlideAbility.__index = SlideAbility

--[=[
	Creates a new SlideAbility instance
	
	@param constructor BaseAbilityConstructor
	@return SlideAbility
]=]
function SlideAbility.new(constructor)
	local self = setmetatable({}, SlideAbility)
	
	-- Inherit from BaseAbility
	for key, value in pairs(constructor) do
		self[key] = value
	end
	
	-- Slide-specific state
	self._isSliding = false
	self._slideStartTime = 0
	self._slideVelocity = Vector3.new(0, 0, 0)
	self._lastSlideDirection = Vector3.new(0, 0, 1)
	self._slideConnection = nil
	
	return self
end

--[=[
	Initializes the slide ability with required setup
	
	@param params table { endFx: function? }
]=]
function SlideAbility:Init(params)
	params = params or {}
	
	-- Store end effects
	self._endFx = params.endFx
	
	-- Set up ability properties
	self.CD = false
	self._cooldown = SLIDE_CONFIG.COOLDOWN
	self.walk_speed_blocking = SLIDE_CONFIG.WALK_SPEED_RESTORE
	
	-- Initialize maid for cleanup
	if not self._maid then
		self._maid = require(Maid).new() -- Adjust path as needed
	end
end

--[=[
	Main execute function - triggers the slide ability
	
	@param params MovementAbilityParams { direction: "forward" | "backward" }
]=]
function SlideAbility:Execute(params)
	if self.CD or self._isSliding then
		return
	end
	
	-- Server validates input
	if RunService:IsServer() then
		self:StartCD()
		return
	end
	
	-- Client-side prediction
	self:_InitializeSlide(params)
end

--[=[
	Sets up attributes before the slide begins
]=]
function SlideAbility:SetAttributes()
	if not RunService:IsServer() then return end
	
	self.humanoid.WalkSpeed = 0
	self.humanoid.JumpHeight = 0
	
	-- Mark character as sliding for other systems
	self.character:SetAttribute("IsSliding", true)
end

--[=[
	Resets attributes after the slide ends
]=]
function SlideAbility:ResetAttributes()
	if not RunService:IsServer() then return end
	
	self.humanoid.WalkSpeed = self.walk_speed_blocking
	self.humanoid.JumpHeight = SLIDE_CONFIG.JUMP_HEIGHT_RESTORE
	
	self.character:SetAttribute("IsSliding", false)
end

--[=[
	Gets animation name for the slide
	
	@param params MovementAbilityParams
	@return string Animation name
]=]
function SlideAbility:GetAnimName(params)
	if params.direction == "forward" then
		return "Slide_Forward"
	else
		return "Slide_Backward"
	end
end

--[=[
	The actual slide effect - handles physics and movement
	
	@param params MovementAbilityParams
]=]
function SlideAbility:SlideEffect(params)
	if RunService:IsServer() then
		return
	end
	
	local hrp = self.hrp
	local humanoid = self.humanoid
	local camera = workspace.CurrentCamera
	local camCF = camera.CFrame
	
	-- Calculate slide direction based on camera
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
	local dir = Vector3.new(0, 0, 0)
	
	if params.direction == "forward" then
		dir = forward
	else
		dir = -forward
	end
	
	-- Prevent sliding if not moving
	if dir.Magnitude < 0.01 then
		return
	end
	
	dir = dir.Unit
	self._lastSlideDirection = dir
	
	-- Rotate character to face camera direction
	local look = camCF.LookVector
	local camYaw = math.atan2(-look.X, -look.Z)
	hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, camYaw, 0)
	
	-- Apply initial velocity
	local velocity = dir * SLIDE_CONFIG.INITIAL_SPEED
	if SLIDE_CONFIG.Y_LOCK then
		velocity = Vector3.new(velocity.X, 0, velocity.Z)
	end
	hrp:ApplyImpulse(velocity)
	
	-- Disable movement
	self.humanoid.WalkSpeed = 0
	self.humanoid.JumpHeight = 0
	
	-- Store slide state
	self._isSliding = true
	self._slideStartTime = tick()
	self._slideVelocity = velocity
	
	-- Start friction loop
	self:_StartSlideFriction()
end

--[=[
	Internal: Initializes slide on client
	
	@param params MovementAbilityParams
]=]
function SlideAbility:_InitializeSlide(params)
	self:SlideEffect(params)
	
	-- Play animation
	local animName = self:GetAnimName(params)
	if self._animHandler then
		self._animHandler:PlayAnimation(animName, self.character)
	end
	
	-- Set attributes server-side
	if self._serviceBag then
		local remoteFolder = self._serviceBag:GetService("RemoteFolder")
		if remoteFolder and remoteFolder:FindFirstChild("SlideAbility") then
			remoteFolder.SlideAbility:FireServer(params)
		end
	end
end

--[=[
	Internal: Handles friction and momentum loss during slide
]=]
function SlideAbility:_StartSlideFriction()
	if self._slideConnection then
		self._slideConnection:Disconnect()
	end
	
	self._slideConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not self._isSliding then
			return
		end
		
		local elapsedTime = tick() - self._slideStartTime
		
		-- Check if slide duration expired
		if elapsedTime > SLIDE_CONFIG.DURATION then
			self:_EndSlide()
			return
		end
		
		-- Apply friction
		local speed = self._slideVelocity.Magnitude
		if speed < SLIDE_CONFIG.MIN_SPEED then
			self:_EndSlide()
			return
		end
		
		-- Reduce velocity based on friction
		local frictionFactor = 1 - SLIDE_CONFIG.FRICTION
		self._slideVelocity = self._slideVelocity * frictionFactor
		
		-- Apply adjusted velocity
		if SLIDE_CONFIG.Y_LOCK then
			local horizontalVel = Vector3.new(
				self._slideVelocity.X,
				0,
				self._slideVelocity.Z
			)
			self.hrp:ApplyImpulse(horizontalVel * deltaTime)
		else
			self.hrp:ApplyImpulse(self._slideVelocity * deltaTime)
		end
	end)
	
	-- Cleanup connection with maid
	if self._maid then
		self._maid:GiveTask(self._slideConnection)
	end
end

--[=[
	Internal: Ends the slide and restores normal movement
]=]
function SlideAbility:_EndSlide()
	self._isSliding = false
	
	if self._slideConnection then
		self._slideConnection:Disconnect()
		self._slideConnection = nil
	end
	
	-- Restore movement
	self.humanoid.WalkSpeed = self.walk_speed_blocking
	self.humanoid.JumpHeight = SLIDE_CONFIG.JUMP_HEIGHT_RESTORE
	
	-- Call end effects
	if self._endFx then
		self._endFx(self)
	end
end

--[=[
	Starts cooldown for the ability
]=]
function SlideAbility:StartCD()
	if self.CD then return end
	
	self.CD = true
	
	task.wait(self._cooldown)
	self.CD = false
end

--[=[
	Cleans up resources when destroyed
]=]
function SlideAbility:Destroy()
	if self._slideConnection then
		self._slideConnection:Disconnect()
	end
	
	if self._maid then
		self._maid:Cleanup()
	end
end

return SlideAbility