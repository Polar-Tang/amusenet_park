-- Animate (refactored)
--
-- Originally the per-character StarterCharacterScripts LocalScript. It now runs
-- as an injectable module: ServiceRoot.client requires it and `task.spawn`s it
-- with the character's AnimationHandler binder + character once the handler is
-- ready. Only the play/stop mechanics changed -- the pose state machine
-- (onRunning/move/...) is untouched. Every animation is played by name through
-- the handler, so the ids live in OtherAnims and are editable there.
--
-- A tiny empty "Animate" LocalScript stub stays in StarterCharacterScripts so
-- Roblox does not insert its own default Animate; the PlayEmote BindableFunction
-- lives on that stub.
--[[
	### What changed vs. what didn't (surgical refactor)

- **Changed**: only the play/stop mechanics — `playAnimation` / `stopAllAnimations` / `playToolAnimation` / `stopToolAnimations` / `setAnimationSpeed` now call `animationHandler:LoadAnimation(state, key)`. The dead weighted-roll machinery (`animTable` / `animNames` / `configureAnimationSet`) was deleted (it only fed the old play path).
- **Untouched**: the pose state machine (`onRunning` / `onJumping` / `move` / emote chat hook, etc.) is verbatim. Globals became `local` (forward-declared at the top) only because a shared module can't use globals safely.
- **Name mapping**: the script's internal lowercase names map to PascalCase handler/OtherAnims keys via the `ANIM_KEYS` table (`idle`→`Idle`, `walk`→`Walk`, …). `currentAnim` stays lowercase for the pose logic; mapping happens only at the handler boundary.
- **Self-heal after equip**: `characterCtxUtils:InitCharAnim` calls `registryAnims`, which now swaps **only the weapon set** and leaves the protected `OtherAnims` defaults in place — so the default poses are no longer torn down on equip at all. `playAnimation` still self-heals if a descriptor it was driving gets rebuilt (it compares the returned track to the cached one), so locomotion resumes instead of freezing.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OtherAnims = require(ReplicatedStorage.Shared.Animations.OtherAnims)

local EMOTE_TRANSITION_TIME = 0.1

-- At/above this Humanoid.WalkSpeed the character is sprinting and locomotion
-- plays "run" instead of "walk". The Run ability (LeftShift) toggles WalkSpeed
-- between 16 (walk) and 24 (sprint); combat states drop it to 14/7 -- all well
-- below this, so WalkSpeed alone cleanly distinguishes a sprint.
local RUN_SPEED_THRESHOLD = 20

-- Maps the Animate state machine's internal (lowercase) names to the keys the
-- handler/OtherAnims use (PascalCase). Names not present fall through unchanged.
local ANIM_KEYS = {
	idle = "Idle",
	walk = "Walk",
	run = "Run",
	jump = "Jump",
	fall = "Fall",
	climb = "Climb",
	sit = "Sit",
	toolnone = "Toolnone",
	toolslash = "Toolslash",
	toollunge = "Toollunge",
	wave = "Wave",
	point = "Point",
	dance1 = "Dance1",
	dance2 = "Dance2",
	dance3 = "Dance3",
	laugh = "Laugh",
	cheer = "Cheer",
}

local function handlerKey(animName)
	return ANIM_KEYS[animName] or animName
end

return function(animationHandler, character)
	local Figure = character
	local Torso = Figure:WaitForChild("Torso")
	local RightShoulder = Torso:WaitForChild("Right Shoulder")
	local LeftShoulder = Torso:WaitForChild("Left Shoulder")
	local RightHip = Torso:WaitForChild("Right Hip")
	local LeftHip = Torso:WaitForChild("Left Hip")
	local Neck = Torso:WaitForChild("Neck")
	local Humanoid = Figure:WaitForChild("Humanoid")

	-- Make every name this script plays resolvable on the handler. registryAnims
	-- (on weapon equip) wipes the set but re-adds OtherAnims, so these survive.
	animationHandler:AddAnimations(OtherAnims)

	local pose = "Standing"

	local currentAnim = ""
	local currentAnimInstance = nil
	local currentAnimTrack = nil
	local currentAnimKeyframeHandler = nil
	local currentAnimSpeed = 1.0

	local dances = { "dance1", "dance2", "dance3" }
	-- Existance in this list signifies that it is an emote, the value indicates if it is a looping emote
	local emoteNames =
		{ wave = false, point = false, dance1 = true, dance2 = true, dance3 = true, laugh = false, cheer = false }

	-- Forward declarations so each character's closure captures its own state
	-- (these were globals in the standalone script; as a shared module they must
	-- be locals or every character would clobber the same functions).
	local getRigScale
	local isRunning
	local stopAllAnimations
	local setAnimationSpeed
	local keyFrameReachedFunc
	local playAnimation
	local toolKeyFrameReachedFunc
	local playToolAnimation
	local stopToolAnimations
	local onRunning, onDied, onJumping, onClimbing, onGettingUp, onFreeFall, onFallingDown, onSeated, onPlatformStanding, onSwimming
	local getTool, getToolAnim, animateTool, moveSit, move

	function getRigScale()
		return Figure:GetScale()
	end

	-- Sprint detection for locomotion. The Run ability toggles Humanoid.WalkSpeed
	-- (16 walk / 24 sprint), so WalkSpeed is the stable run signal shared by
	-- onRunning and move() -- using the same signal in both keeps them from
	-- fighting over walk-vs-run from one frame to the next.
	function isRunning()
		return Humanoid.WalkSpeed >= RUN_SPEED_THRESHOLD
	end

	-- declarations
	local toolAnim = "None"
	local toolAnimTime = 0
	local jumpAnimTime = 0
	local jumpAnimDuration = 0.3
	local toolTransitionTime = 0.1
	local fallTransitionTime = 0.3
	local jumpMaxLimbVelocity = 0.75

	local toolAnimName = ""
	local toolAnimTrack = nil
	local toolAnimInstance = nil
	local currentToolAnimKeyframeHandler = nil

	function stopAllAnimations()
		local oldAnim = currentAnim
		local playingName = currentAnim

		-- return to idle if finishing an emote
		if emoteNames[oldAnim] ~= nil and emoteNames[oldAnim] == false then
			oldAnim = "idle"
		end

		currentAnim = ""
		currentAnimInstance = nil
		if currentAnimKeyframeHandler ~= nil then
			currentAnimKeyframeHandler:disconnect()
			currentAnimKeyframeHandler = nil
		end

		if playingName ~= "" then
			animationHandler:LoadAnimation(false, handlerKey(playingName))
		end
		currentAnimTrack = nil
		return oldAnim
	end

	function setAnimationSpeed(speed)
		if speed ~= currentAnimSpeed then
			currentAnimSpeed = speed
			if currentAnimTrack then
				currentAnimTrack:AdjustSpeed(currentAnimSpeed)
			end
		end
	end

	function keyFrameReachedFunc(frameName)
		if frameName == "End" then
			-- A looped track re-loops itself, so manually replaying it on its End
			-- keyframe only restarts/re-fades it -- that re-fade is the Idle "pop"
			-- seen while standing still. The End re-trigger is only needed to loop
			-- non-looped clips, so bail for looped ones and let the engine loop.
			if currentAnimTrack and currentAnimTrack.Looped then
				return
			end

			local repeatAnim = currentAnim
			-- return to idle if finishing an emote
			if emoteNames[repeatAnim] ~= nil and emoteNames[repeatAnim] == false then
				repeatAnim = "idle"
			end

			local animSpeed = currentAnimSpeed
			playAnimation(repeatAnim, 0.0, Humanoid)
			setAnimationSpeed(animSpeed)
		end
	end

	-- Routes play through the handler. Plays only on a real name change (the
	-- guard below). Locomotion lives in the protected OtherAnims defaults, which
	-- a weapon equip never stops or tears down (InitCharAnim no longer StopAll's
	-- them), so the cached track stays playing across an equip and there is
	-- nothing to "resume" -- skipping the redundant replay is always correct.
	function playAnimation(animName, transitionTime, humanoid)
		local changed = animName ~= currentAnim

		-- Original Animate only (re)played on an actual animation change. The
		-- move() loop (every 0.1s while pose == "Running") and repeated
		-- Humanoid.Running events both ask for the SAME locomotion anim many
		-- times a second; re-issuing LoadAnimation(true) calls :Play() again on
		-- an already-playing track, which re-fades it -- that re-fade is the
		-- continuity-breaking "replay" seen while moving (walk/run) and right
		-- after stopping. Locomotion anims live in the protected OtherAnims
		-- defaults, which registryAnims never tears down, so there is no
		-- torn-down track to self-heal: skipping the redundant replay when
		-- nothing changed cannot freeze locomotion.
		if not changed then
			return
		end

		if changed and currentAnim ~= "" then
			animationHandler:LoadAnimation(false, handlerKey(currentAnim))
		end

		local track = animationHandler:LoadAnimation(true, handlerKey(animName))

		if changed then
			currentAnimSpeed = 1.0
		end

		if changed or track ~= currentAnimTrack then
			if currentAnimKeyframeHandler ~= nil then
				currentAnimKeyframeHandler:disconnect()
				currentAnimKeyframeHandler = nil
			end
			currentAnimTrack = track
			currentAnimInstance = track and track.Animation or nil
			if track then
				track.Priority = Enum.AnimationPriority.Core
				currentAnimKeyframeHandler = track.KeyframeReached:connect(keyFrameReachedFunc)
			end
		end

		currentAnim = animName
	end

	function toolKeyFrameReachedFunc(frameName)
		if frameName == "End" then
			playToolAnimation(toolAnimName, 0.0, Humanoid)
		end
	end

	function playToolAnimation(animName, transitionTime, humanoid, priority)
		local changed = animName ~= toolAnimName

		if changed and toolAnimName ~= "" then
			animationHandler:LoadAnimation(false, handlerKey(toolAnimName))
		end

		local track = animationHandler:LoadAnimation(true, handlerKey(animName))

		if changed or track ~= toolAnimTrack then
			if currentToolAnimKeyframeHandler ~= nil then
				currentToolAnimKeyframeHandler:disconnect()
				currentToolAnimKeyframeHandler = nil
			end
			toolAnimTrack = track
			toolAnimInstance = track and track.Animation or nil
			if track then
				if priority then
					track.Priority = priority
				end
				currentToolAnimKeyframeHandler = track.KeyframeReached:connect(toolKeyFrameReachedFunc)
			end
		end

		toolAnimName = animName
	end

	function stopToolAnimations()
		local oldAnim = toolAnimName

		if currentToolAnimKeyframeHandler ~= nil then
			currentToolAnimKeyframeHandler:disconnect()
			currentToolAnimKeyframeHandler = nil
		end

		local playingName = toolAnimName
		toolAnimName = ""
		toolAnimInstance = nil
		if playingName ~= "" then
			animationHandler:LoadAnimation(false, handlerKey(playingName))
		end
		toolAnimTrack = nil

		return oldAnim
	end

	function onRunning(speed)
		speed /= getRigScale()

		if speed > 0.01 then
			if isRunning() then
				playAnimation("run", 0.1, Humanoid)
			else
				playAnimation("walk", 0.1, Humanoid)
				if
					currentAnimInstance
					and currentAnimInstance.AnimationId == "http://www.roblox.com/asset/?id=180426354"
				then
					setAnimationSpeed(speed / 14.5)
				end
			end
			pose = "Running"
		else
			-- Leave pose == "Running" set and move() will keep re-driving walk
			-- every 0.1s -- that is the "animation replayed after walking" bug.
			-- Transition to Standing and play idle ONCE; idle is looped so the
			-- engine loops it and the playAnimation change-guard stops any replay.
			if emoteNames[currentAnim] == nil then
				playAnimation("idle", 0.1, Humanoid)
				pose = "Standing"
			end
		end
	end

	function onDied()
		pose = "Dead"
	end

	function onJumping()
		playAnimation("jump", 0.1, Humanoid)
		jumpAnimTime = jumpAnimDuration
		pose = "Jumping"
	end

	function onClimbing(speed)
		speed /= getRigScale()

		playAnimation("climb", 0.1, Humanoid)
		setAnimationSpeed(speed / 12.0)
		pose = "Climbing"
	end

	function onGettingUp()
		pose = "GettingUp"
	end

	function onFreeFall()
		if jumpAnimTime <= 0 then
			playAnimation("fall", fallTransitionTime, Humanoid)
		end
		pose = "FreeFall"
	end

	function onFallingDown()
		pose = "FallingDown"
	end

	function onSeated()
		pose = "Seated"
	end

	function onPlatformStanding()
		pose = "PlatformStanding"
	end

	function onSwimming(speed)
		if speed > 0 then
			pose = "Running"
		else
			pose = "Standing"
		end
	end

	function getTool()
		for _, kid in ipairs(Figure:GetChildren()) do
			if kid.className == "Tool" then
				return kid
			end
		end
		return nil
	end

	function getToolAnim(tool)
		for _, c in ipairs(tool:GetChildren()) do
			if c.Name == "toolanim" and c.className == "StringValue" then
				return c
			end
		end
		return nil
	end

	function animateTool()
		if toolAnim == "None" then
			playToolAnimation("toolnone", toolTransitionTime, Humanoid, Enum.AnimationPriority.Idle)
			return
		end

		if toolAnim == "Slash" then
			playToolAnimation("toolslash", 0, Humanoid, Enum.AnimationPriority.Action)
			return
		end

		if toolAnim == "Lunge" then
			playToolAnimation("toollunge", 0, Humanoid, Enum.AnimationPriority.Action)
			return
		end
	end

	function moveSit()
		RightShoulder.MaxVelocity = 0.15
		LeftShoulder.MaxVelocity = 0.15
		RightShoulder:SetDesiredAngle(3.14 / 2)
		LeftShoulder:SetDesiredAngle(-3.14 / 2)
		RightHip:SetDesiredAngle(3.14 / 2)
		LeftHip:SetDesiredAngle(-3.14 / 2)
	end

	local lastTick = 0

	function move(time)
		local amplitude = 1
		local frequency = 1
		local deltaTime = time - lastTick
		lastTick = time

		local climbFudge = 0
		local setAngles = false

		if jumpAnimTime > 0 then
			jumpAnimTime = jumpAnimTime - deltaTime
		end

		if pose == "FreeFall" and jumpAnimTime <= 0 then
			playAnimation("fall", fallTransitionTime, Humanoid)
		elseif pose == "Seated" then
			playAnimation("sit", 0.5, Humanoid)
			return
		elseif pose == "Running" then
			playAnimation(isRunning() and "run" or "walk", 0.1, Humanoid)
		elseif
			pose == "Dead"
			or pose == "GettingUp"
			or pose == "FallingDown"
			or pose == "Seated"
			or pose == "PlatformStanding"
		then
			stopAllAnimations()
			amplitude = 0.1
			frequency = 1
			setAngles = true
		end

		if setAngles then
			local desiredAngle = amplitude * math.sin(time * frequency)

			RightShoulder:SetDesiredAngle(desiredAngle + climbFudge)
			LeftShoulder:SetDesiredAngle(desiredAngle - climbFudge)
			RightHip:SetDesiredAngle(-desiredAngle)
			LeftHip:SetDesiredAngle(-desiredAngle)
		end

		-- Tool Animation handling
		local tool = getTool()
		if tool and tool:FindFirstChild("Handle") then
			local animStringValueObject = getToolAnim(tool)

			if animStringValueObject then
				toolAnim = animStringValueObject.Value
				-- message recieved, delete StringValue
				animStringValueObject.Parent = nil
				toolAnimTime = time + .3
			end

			if time > toolAnimTime then
				toolAnimTime = 0
				toolAnim = "None"
			end

			animateTool()
		else
			stopToolAnimations()
			toolAnim = "None"
			toolAnimInstance = nil
			toolAnimTime = 0
		end
	end

	-- connect events
	Humanoid.Died:connect(onDied)
	Humanoid.Running:connect(onRunning)
	Humanoid.Jumping:connect(onJumping)
	Humanoid.Climbing:connect(onClimbing)
	Humanoid.GettingUp:connect(onGettingUp)
	Humanoid.FreeFalling:connect(onFreeFall)
	Humanoid.FallingDown:connect(onFallingDown)
	Humanoid.Seated:connect(onSeated)
	Humanoid.PlatformStanding:connect(onPlatformStanding)
	Humanoid.Swimming:connect(onSwimming)

	-- setup emote chat hook. This connects to the player (not the character), so
	-- it is disconnected explicitly once the character despawns to avoid stacking
	-- a new connection every respawn.
	local chattedConn = Players.LocalPlayer.Chatted:connect(function(msg)
		local emote = ""
		if msg == "/e dance" then
			emote = dances[math.random(1, #dances)]
		elseif string.sub(msg, 1, 3) == "/e " then
			emote = string.sub(msg, 4)
		elseif string.sub(msg, 1, 7) == "/emote " then
			emote = string.sub(msg, 8)
		end

		if pose == "Standing" and emoteNames[emote] ~= nil then
			playAnimation(emote, 0.1, Humanoid)
		end
	end)

	-- emote bindable hook -- the PlayEmote BindableFunction lives on the
	-- in-character "Animate" stub so external emote invokers still reach
	-- character.Animate.PlayEmote.
	local animateStub = Figure:WaitForChild("Animate", 10)
	local playEmote: RemoteFunction = animateStub and animateStub:FindFirstChild("PlayEmote")
	if playEmote then
		playEmote.OnClientInvoke = function(emote)
			-- Only play emotes when idling
			if pose ~= "Standing" then
				return
			end
			if emoteNames[emote] ~= nil then
				-- Default emotes
				playAnimation(emote, EMOTE_TRANSITION_TIME, Humanoid)
				return true, currentAnimTrack
			end

			-- Return false to indicate that the emote could not be played
			return false
		end
	end

	-- main program

	-- initialize to idle
	playAnimation("idle", 0.1, Humanoid)
	pose = "Standing"

	while Figure.Parent ~= nil do
		local _, time = wait(0.1)
		move(time)
	end

	if chattedConn then
		chattedConn:disconnect()
	end
end
