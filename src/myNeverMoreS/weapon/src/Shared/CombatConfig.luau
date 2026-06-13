local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local EffectTypes = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.EffectTypes)
local roll_vfx = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Server.Utils.roll_vfx)
-- Client-only grenade aimer (picks the touch or mouse peephole). Side-safe at
-- module scope, so requiring it here (CombatConfig is shared) does nothing on the
-- server; only `onEquipCBClient` ever calls into it, and that hook runs from the
-- *client* EquiTool.
local sightClass = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Client.Utils.sightClass)
local Constanst = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local Table = require(ReplicatedStorage.Nevermore.Quenty.table.Shared.Table)
local weaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Server.types.weaponTypes)
local sharedWeaponTypes = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.types.weaponTypes)

export type BaseAbility = weaponTypes.BaseAbility
export type BaseAbilityConstructor = weaponTypes.BaseAbilityConstructor

export type AttackBaseAbility = weaponTypes.AttackBaseAbility
export type AttackBaseAbilityConstructor = weaponTypes.AttackBaseAbilityConstructor

export type DefenseAbility = weaponTypes.DefenseAbility
export type DefenseAbilityConstructor = weaponTypes.DefenseAbilityConstructor

export type AbilitySpec = {
	config: BaseAbilityConstructor | DefenseAbilityConstructor | AttackBaseAbilityConstructor,
	endFx: ((ctx: BaseAbility) -> ())?,
	special_speed: number?,
	effect: ((ctx: BaseAbility) -> ())?,
}

export type effectHitCtx = EffectTypes.effectHitCtx
export type VFX = EffectTypes.VFX

export type HitboxesResult = {
	hitboxes: { weaponTypes.HitboxConfig },
	vfxs: { VFX }?,
	hit_effect_data: {}?,
}

export type hits = {
	hitPart: BasePart,
	target: Model,
}

export type after_hit_data = {
	vfxs: { VFX },
	hits: hits,
}

export type AttackAbilitySpec = {

	-- execution hooks
	createHitboxes: (ctx: AttackBaseAbility) -> HitboxesResult,
	delay_cb: ((ctx: AttackBaseAbility) -> () -> ())?,
	delay_cb_number: number?,
	custom_init: ((ctx: AttackBaseAbility) -> () -> ())?,
	after_hit: ((ctx: AttackBaseAbility, after_hit_data: after_hit_data) -> ())?,
	post_anim: (ctx: AttackBaseAbility) -> ()?,
	get_anim_name: (ctx: AttackBaseAbility) -> ()?,
} & AbilitySpec

export type DefenseAbilitySpec = {
	_process: (ctx: DefenseAbility, dmgCtx: any) -> (),
	_execute: (ctx: DefenseAbility) -> (),
	_additiona_deactivate: ((ctx: DefenseAbility) -> ())?,
} & AbilitySpec

export type Weapon = {
	attacks: {
		[string]: AttackAbilitySpec | DefenseAbilitySpec | AbilitySpec,
	},
}

local module = {}
local info = {}

local default_end_fx = function(data)
	for i, animName in ipairs(data.animNames) do
		data._animHandler:PreloadAnims({ animName })
		local hitEnd = function(track: AnimationTrack)
			data:resetAtt()
		end

		data._animHandler:OnSignal({
			callback = hitEnd,
			animationName = animName,
			animationEventName = "EndedCon",
		})
	end
end

local end_m1_fx = function(data)
	data:InitCDInst()
	data.character:SetAttribute("Combo", 1)

	for i, animName in ipairs(data.animNames) do
		if data._animHandler then
			data._animHandler:PreloadAnims({ animName })
			local hitEnd = function(track: AnimationTrack)
				if not data.character:GetAttribute("IsBlocking") then
					data.humanoid.WalkSpeed = 14
					data.humanoid.JumpHeight = 6.5
				end

				data.character:SetAttribute("Attacking", false)
				-- data:PlaySound("Swing", 2)
				data.character:SetAttribute("Swing", false)
			end
			data._animHandler:OnSignal({
				callback = hitEnd,
				animationName = animName,
				animationEventName = "EndedCon",
			})
		end
	end
end

--

type dash_movement_arg = {
	hrp: BasePart,
	dir: Vector3,
	time: number,
	distance: number,
}

local enfEffect = function(animName)
	return function(ctx: sharedWeaponTypes.MovementAbility)
		local onEnd = function()
			ctx._animHandler:LoadAnimation(false, animName)
			ctx:resetAtt()
			ctx.humanoid.WalkSpeed = 16
			ctx.humanoid.JumpHeight = 6.5
		end

		ctx._animHandler:OnSignal({
			callback = onEnd,
			override = true,
			animationName = animName,
			animationEventName = "EndedCon",
		})
	end
end

local function dash_movement(dash_movement_arg: dash_movement_arg)
	-- ALING THE CHARACTER TO THE PLAYER CAMERA ORIENTATION
	local hrp = dash_movement_arg.hrp
	local dashDir = dash_movement_arg.dir
	local timeShit = dash_movement_arg.time
	local distance = dash_movement_arg.distance

	-- testPart({Position = hrp.Position, Size = Vector3.new(50,50,50)})
	local dashSpeed = distance / timeShit
	local endPos = hrp.Position + (dashDir * dashSpeed) * timeShit
	-- local endPos2 = hrp.Position + dashDir * Constants.dashDistance

	local attachmentAlignPos = Instance.new("Attachment")
	attachmentAlignPos.Name = "attachmentDash"
	attachmentAlignPos.Visible = true
	attachmentAlignPos.Parent = hrp

	local alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = attachmentAlignPos
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.MaxForce = math.huge
	alignPos.MaxVelocity = math.huge
	alignPos.Position = endPos
	-- testPart({Position = endPos, Size = Vector3.new(5,5,5)})
	alignPos.Responsiveness = 20
	alignPos.ApplyAtCenterOfMass = true
	alignPos.Parent = hrp
	Debris:AddItem(alignPos, Constanst.dashTime)
	Debris:AddItem(attachmentAlignPos, Constanst.dashTime)
end

local slide_end = enfEffect("Slide")

local slide_end_fx = function(ctx: sharedWeaponTypes.MovementAbility)
	for i, animName in ipairs(ctx.animNames) do
		ctx._animHandler:PreloadAnims({ animName })
		slide_end(ctx)
	end
end

local SLIDE_INITIAL_SPEED = 40 -- studs / s  (tune to taste)
local SLIDE_DECEL = 1.3 -- exponential decay constant  (higher = faster stop)
local SLIDE_MIN_SPEED = 10
local MAX_FORCE = math.huge -- N  — cap so the constraint doesn't fight slopes infinitely

local slide_reset = function(ctx)
	ctx._isActive = false
	ctx._animHandler:LoadAnimation(false, ctx._animName)
	-- Slide has naturally decelerated to rest — clean up
	if ctx._slideConstraint then 
		ctx._slideConstraint:Destroy()
		ctx._slideConstraint = nil
		ctx._slideConnection:Disconnect()
		ctx._slideConnection = nil
	
	end
end
local slide_effect = function(ctx, params)
	-- ── Cancel path ──────────────────────────────────────────────────────────
	-- If slide_effect is invoked while a slide is already running, tear down
	-- the existing LinearVelocity and its update loop, then return.
	-- This is the "cancellable" guarantee: one Destroy() call is all it takes.
	if ctx._isActive or params.stop then
		slide_reset(ctx)
		return
	end

	ctx._animHandler:LoadAnimation(true, "Slide")

	-- ── Direction resolution ──────────────────────────────────────────────
	local hrp: BasePart = ctx.hrp
	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector

	-- ── Orient character to camera yaw ───────────────────────────────────
	local camYaw = math.atan2(-look.X, -look.Z)
	hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, camYaw, 0)

	-- ── Build the LinearVelocity constraint ───────────────────────────────
	--
	--   Line + Attachment0: velocity is driven along the attachment's X axis
	--   (primary axis) in world space.
	--
	--   After the yaw snap, hrp.LookVector = camera-forward on XZ.
	--   In local hrp space that is -Z = (0,0,-1).
	--   Rotating the attachment -90° around Y maps its X axis to local -Z
	--   (world-forward). +90° gives world-backward.
	--
	local lv: LinearVelocity = Instance.new("LinearVelocity")

	-- Find-or-create the "LV" attachment on the HRP. This runs client-side
	-- (slide is a client-only Movement ability), so it can't use the server
	-- EffectService:ChangeChildren helper — that module returns {} on clients.
	local a0: Attachment? = hrp:FindFirstChild("LV") :: Attachment?
	if not a0 then
		local att: Attachment = Instance.new("Attachment")
		att.Axis = Vector3.new(-0, 0, -1)
		att.SecondaryAxis = Vector3.new(0, 1, 0)
		att.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
		att.Name = "LV"
		att.Parent = hrp
		a0 = att
	end
	lv.Attachment0 = a0
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lv.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	lv.LineVelocity = SLIDE_INITIAL_SPEED
	lv.MaxForce = MAX_FORCE
	lv.Parent = hrp

	ctx._slideConstraint = lv
	ctx._isActive = true

	-- ── Heartbeat loop: constant deceleration ────────────────────────────
	--
	--   Each frame we subtract (SLIDE_DECEL * dt) from the target speed.
	--   When it reaches zero the constraint is destroyed and the loop stops.
	--   This gives a perfectly linear velocity-time curve regardless of
	--   surface or network conditions.
	slide_end_fx(ctx)

	ctx._slideConnection = RunService.Heartbeat:Connect(function(dt)
		if not ctx._slideConstraint or not ctx._slideConstraint.Parent then
			-- Constraint was destroyed externally (e.g. character reset)
			ctx._isActive = false
			ctx._slideConnection:Disconnect()
			ctx._slideConnection = nil
			return
		end

		local newSpeed = ctx._slideConstraint.LineVelocity * math.exp(-SLIDE_DECEL * dt)
		if newSpeed <= SLIDE_MIN_SPEED then
			slide_reset(ctx)
		else
			ctx._slideConstraint.LineVelocity = newSpeed
		end
	end)
end

SLideKey = Enum.KeyCode.LeftControl
local Slide = {
	config = {
		animNames = { "Slide" },
		type = "Movement",
		cooldown = 1,
		key = SLideKey,
	},
	effect = slide_effect,
	endFx = slide_end_fx,
}

local RUN_SPEED = 24 -- studs/s while sprinting

-- Press/release toggle: each Execute flips `_isActive`. Driven by the
-- press-and-hold heartbeat in InputManager, so holding LeftShift sprints
-- and releasing it restores the default walk speed.
local run_effect = function(ctx: sharedWeaponTypes.MovementAbility)
	if ctx._isActive then
		ctx.humanoid.WalkSpeed = 16
		ctx._isActive = false
	else
		ctx.humanoid.WalkSpeed = RUN_SPEED
		ctx._isActive = true
	end
end

local RunKey = Enum.KeyCode.LeftShift
local Run = {
	config = {
		animNames = { "Run" },
		type = "Movement",
		key = RunKey,
	},
	effect = run_effect,
}

-- Weapons

-- Stink Fist

local function create_m1_hitboxes(configData: weaponTypes.HixboxDataConfig)
	return function(ctx, params)
		-- SET THE COMBO ATT
		local char = ctx.character
		local max_combo = 4

		local function getWeapon(): BasePart
			local char = ctx.character
			local combo = char:GetAttribute("Combo")

			if combo % 2 == 0 then
				return ctx:_resolveWeaponGrip("fist", "getRightGrip", char)
			end

			return ctx:_resolveWeaponGrip("fist", "getLeftGrip", char)
		end

		local current_combo = char:GetAttribute("Combo")

		local hit_effect = {
			damage = 10,
			attacker = ctx.character,
			attackId = ctx.attackId,
		}
		if current_combo == max_combo then
			hit_effect.strength = 30
			hit_effect.groundSmash = {
				position = nil,
				amount = 14,
				velocity = 70,
				material = Enum.Material.Slate,
				dust = true,
				shockwave = true,
				sizeRange = Vector2.new(1, 2.5),
				lifetime = 2.5,
			}
		end
		hit_effect.strikes_hit = true

		local weapon = getWeapon()

		local detectionInfo = {
			Time = configData.Time,
			Size = configData.Size,
			CFrame = configData.CFrame,
			HitMode = configData.HitMode,
			Shape = configData.Shape,
			attackId = ctx.attackId,
			strikes_hit = configData.strikes_hit,
			Weapon = weapon,
			referenceVector = ctx.character.PrimaryPart.CFrame.LookVector,
			sourcePosition = ctx.character.PrimaryPart.Position,
			Attacker = ctx.character,
		}

		return {
			hitboxes = { detectionInfo },
			hit_effect_data = hit_effect,
		}
	end
end

local fist_stats: sharedWeaponTypes.WeaponStatsBase = {
	damage = 5,
	criticalDamage = 20,
	unanchoredImpulseForce = 5,
	viewModel = "Blaster",
}

local m1 = {
	config = {
		life_time = 1.4,
		keyCode = Enum.UserInputType.MouseButton1,
		animNames = { "Swing1", "Swing2", "Swing3", "Swing4" },
		type = "Attack",
		attackType = "ST",
		cooldown = 0.5,
	},
	get_anim_name = function(ctx)
		local char = ctx.character
		local combo = char:GetAttribute("Combo")
		return "Swing" .. combo
	end,

	preAnimFx = function(ctx)
		local char = ctx.character
		local max_combo = 4
		-- SET THE COMBO ATT
		-- If the last hit was after 3 seconds, reset the combo
		if not ctx._comboController:isCd() then
			-- print("current combo ", char:GetAttribute("Combo"))
			char:SetAttribute("Combo", 1)
			ctx._comboController:init(3)

			return
		end

		ctx._comboController:init(3)

		local combo = char:GetAttribute("Combo")
		if combo >= max_combo then
			char:SetAttribute("Combo", 1)
		else
			char:SetAttribute("Combo", combo + 1)
		end
	end,
	createHitboxes = create_m1_hitboxes({
		Time = 2,
		Size = Vector3.new(5, 5, 5),
		CFrame = Vector3.new(0, 0, 3),
		Shape = "Box",
		HitMode = "Strong",
		strikes_hit = true,
	}),
	endFx = end_m1_fx,
}

local Fist: sharedWeaponTypes.MeleeSpec = {
	skills = {
		[SLideKey.Name] = Slide,
		[RunKey.Name] = Run,
	},
	weapon_stats = fist_stats,

	attacks = {
		[Enum.UserInputType.MouseButton1.Name] = m1,
	},
	walk_speed_normal = 14,
	walk_speed_blocking = 6,
	walk_speed_counter = 3,
	required_damage = 120,
	getLeftGrip = function(model)
		return model:FindFirstChild("Left Arm")
	end,
	getRightGrip = function(model)
		return model:FindFirstChild("Right Arm")
	end,
	getHead = function(model)
		return model:FindFirstChild("Head")
	end,
	gripC0 = CFrame.identity,
	gripC1 = CFrame.identity,
	-- run_speed = 18,
}

info["fist"] = Fist

-- Gun
do
	local ak_stats: sharedWeaponTypes.WeaponStatsRange = {
		_ammo = 10,
		_reloading = false,

		aimAssistCenteringStrength = 0,
		aimAssistFov = 20,
		aimAssistFrictionStrength = 0.5,
		aimAssistRange = 100,
		aimAssistTrackingStrength = 0.5,

		damage = 10,
		criticalDamage = 40,
		fireMode = "Semi",
		magazineSize = 10,
		bulletVelocity = 1000,

		range = 400,
		rateOfFire = 600,
		rayRadius = 0.4,
		raysPerShot = 1,
		maxDistance = 400,

		recoilMax = Vector2.new(5, 20),
		recoilMin = Vector2.new(0, 15),
		recoilRise = 1.5,

		reloadTime = 1,
		spread = 2,
		unanchoredImpulseForce = 5,

		viewModel = "Blaster",
	}

	-- Range attack: the shot is fully driven by RangeAttack / RangeAttackClient
	-- (rays + recoil from `weapon_stats`). It plays no swing animation, so it
	-- carries no `animNames`/`endFx`/`get_anim_name`/`createHitboxes` — those are
	-- the melee-only hooks that preload Swing tracks the gun doesn't own.
	local shot = {
		config = {
			life_time = 1.4,
			keyCode = Enum.UserInputType.MouseButton1,
			animNames = {},
			type = "Range",
			attackType = "ST",
			cooldown = 0.4, -- A basic gun can shoot
			weapon_stats = table.clone(ak_stats),
		},
	}

	-- Reload (R): refills the magazine after `reloadTime`. Dispatched by the
	-- generic ReloadAbility / ReloadAbilityClient pair; the Tool's `_ammo` /
	-- `_reloading` attributes are the only contract with the m1 shot, so the
	-- two abilities never reference each other. `cooldown` matches
	-- `reloadTime` so Execute can't be spammed while a reload is in flight.
	local reload = {
		config = {
			keyCode = Constanst.KEYBOARD_RELOAD_KEY_CODE,
			animNames = {},
			type = "Reload",
			cooldown = ak_stats.reloadTime,
			weapon_stats = table.clone(ak_stats),
		},
	}

	local gun: sharedWeaponTypes.MeleeSpec = {
		weapon_name = "gun",
		weapon_stats = table.clone(ak_stats),

		attacks = {
			[Enum.UserInputType.MouseButton1.Name] = shot,
		},
		skills = {
			[SLideKey.Name] = Slide,
			[RunKey.Name] = Run,
			[Constanst.KEYBOARD_RELOAD_KEY_CODE.Name] = reload,
		},

		walk_speed_normal = 14,
		walk_speed_blocking = 6,
		walk_speed_counter = 3,
		required_damage = 120,

		getLeftGrip = function(model)
			return model:FindFirstChild("Left Arm")
		end,
		getRightGrip = function(model)
			return model:FindFirstChild("Right Arm")
		end,
		getHead = function(model)
			return model:FindFirstChild("Head")
		end,

		gripC0 = CFrame.new(-0.364, -1.12, -0.381) * CFrame.Angles(0, math.rad(90), math.rad(-90)),
		gripC1 = CFrame.identity,
	}

	info["gun"] = gun
end

do
	local ak_47 = table.clone(info["gun"])
	ak_47.weapon_stats = {
		_ammo = 30,
		_reloading = false,

		aimAssistCenteringStrength = 0,
		aimAssistFov = 20,
		aimAssistFrictionStrength = 0.5,
		aimAssistRange = 100,
		aimAssistTrackingStrength = 0.5,

		damage = 15,
		criticalDamage = 40,
		fireMode = "Auto",
		magazineSize = 30,
		range = 1000,
		rateOfFire = 600,
		maxDistance = 600,

		rayRadius = 0.4,
		raysPerShot = 1,

		recoilMax = Vector2.new(2, 7),
		recoilMin = Vector2.new(-2, 5),
		recoilRise = 0.5,

		reloadTime = 1.5,
		spread = 2,
		unanchoredImpulseForce = 2,
		viewModel = "Auto Blaster",
	}

	local shot_m1 = table.clone(m1)
	shot_m1.config = {
		life_time = 1.4,
		keyCode = Enum.UserInputType.MouseButton1,
		animNames = { "Swing1", "Swing2", "Swing3", "Swing4" },
		type = "Range",
		attackType = "ST",
		cooldown = 0.1, -- A basic gun can shot
		weapon_stats = table.clone(ak_47.weapon_stats),
	}
	-- Remove all shits about animation for the moment
	shot_m1.endFx = nil
	shot_m1.preAnimFx = nil

	ak_47.attacks = {
		[Enum.UserInputType.MouseButton1.Name] = shot_m1,
	}
	-- table.clone(info["gun"]) is shallow: without this reassignment the ak-47
	-- would share the gun's skills table — and its 10-round / 1s reload.
	local ak_reload = {
		config = {
			keyCode = Constanst.KEYBOARD_RELOAD_KEY_CODE,
			animNames = {},
			type = "Reload",
			cooldown = ak_47.weapon_stats.reloadTime,
			weapon_stats = table.clone(ak_47.weapon_stats),
		},
	}
	ak_47.skills = {
		[SLideKey.Name] = Slide,
		[RunKey.Name] = Run,
		[Constanst.KEYBOARD_RELOAD_KEY_CODE.Name] = ak_reload,
	}
	ak_47.gripC0 = CFrame.identity
	ak_47.gripC1 = CFrame.new(0.374, -0.7, 1.6) * CFrame.Angles(math.rad(90), -0, 0) -- TODO: tune for AK-47 geometry
	ak_47.centerAimToCamera = true
	info["ak-47"] = ak_47
end

-- Grenade (thrown AOE)
do
	-- Fixed flight time the projectile takes to reach the click point. MUST match
	-- FLIGHT_TIME in the peephole aimers (drawTrajectory callers) so the previewed
	-- arc equals the real flight.
	local FLIGHT_TIME = 0.5
	local GRAVITY = Vector3.new(0, -workspace.Gravity, 0)

	local grenade_stats: sharedWeaponTypes.WeaponStatsBase = {
		damage = 40,
		criticalDamage = 60,
		unanchoredImpulseForce = 10,
		viewModel = "Blaster",
	}

	-- Solve the throw velocity that carries the grenade from `fromPos` to
	-- `toPos` in exactly FLIGHT_TIME under gravity: v0 = (P1 - P0 - 0.5*G*T^2)/T
	local function solveThrowVelocity(fromPos: Vector3, toPos: Vector3): Vector3
		return (toPos - fromPos - 0.5 * GRAVITY * FLIGHT_TIME ^ 2) / FLIGHT_TIME
	end

	local grenade_throw = {
		config = {
			life_time = 1,
			key = { Name = "Grenade" }, -- synthetic key: driven by the aimer's click, not InputManager
			animNames = { "Throw" },
			type = "Attack",
			attackType = "AOE",
			cooldown = 1.5,
			-- AOE resolve + impact-VFX delay. Slightly past the flight time so the
			-- box has caught everyone and the explosion lands as the grenade does.
			delay_cb_number = FLIGHT_TIME + 0.05,
		},
		get_anim_name = function()
			return "Throw"
		end,
		-- Runs on the "Hit" anim marker (the release frame). `params` is the
		-- frontend payload `{ clickPosition = P1 }` forwarded from the aimer.
		createHitboxes = function(ctx, params)
			local hrp = ctx.character.PrimaryPart
			local startPos = hrp.Position
			local landingPos = (params and params.clickPosition) or (startPos + hrp.CFrame.LookVector * 20) -- fallback if no aim point

			local initialVelocity = solveThrowVelocity(startPos, landingPos)

			-- Grenade model flies the predicted arc on every client (VFX only --
			-- the server never pivots it). Fired immediately at release.
			roll_vfx({
				{
					action = "grenade_flight",
					attackId = ctx.attackId,
					Attacker = ctx.character,
					startPosition = startPos,
					initialVelocity = initialVelocity,
					flightTime = FLIGHT_TIME,
				},
			})

			-- Immediate long-lived TimedBox parked at the landing point. The
			-- source sits below the box with an up reference vector so the dot
			-- filter passes for targets in every horizontal direction (AOE).
			local detectionInfo = {
				Time = FLIGHT_TIME + 1.5,
				Size = Vector3.new(16, 14, 16),
				CFrame = CFrame.new(0, 0, 0),
				Shape = "TimedBox",
				HitMode = "Strong",
				strikes_hit = true,
				attackId = ctx.attackId,
				Attacker = ctx.character,
				Weapon = { Pos = landingPos + Vector3.new(0, 4, 0) },
				referenceVector = Vector3.yAxis,
				sourcePosition = landingPos - Vector3.new(0, 5, 0),
			}

			local hit_effect = {
				damage = 40,
				stun_time = 1.5,
				strength = 30,
				isUpside = true,
				up = 14,
				strikes_hit = true,
				ragdoll = {
					isRag = true,
					duration = 1.2,
				},
			}

			local impact_vfx = {
				{
					action = "grenade_explosion",
					attackId = ctx.attackId,
					Attacker = ctx.character,
					Pos = landingPos,
					life_time = 1,
				},
			}

			return {
				hitboxes = { detectionInfo },
				vfxs = impact_vfx,
				hit_effect_data = hit_effect,
			}
		end,
		-- Fired after delay_cb_number (~landing): explosion at the landing point.
		delay_cb = function(_ctx, vfxs)
			return function()
				roll_vfx(vfxs)
			end
		end,
		endFx = default_end_fx,
	}

	local grenade: sharedWeaponTypes.MeleeSpec = {
		weapon_name = "grenade",
		weapon_stats = grenade_stats,

		attacks = {
			["Grenade"] = grenade_throw,
		},
		skills = {
			[SLideKey.Name] = Slide,
			[RunKey.Name] = Run,
		},

		walk_speed_normal = 14,
		walk_speed_blocking = 6,
		walk_speed_counter = 3,
		required_damage = 120,

		getLeftGrip = function(model)
			return model:FindFirstChild("Left Arm")
		end,
		getRightGrip = function(model)
			return model:FindFirstChild("Right Arm")
		end,
		getHead = function(model)
			return model:FindFirstChild("Head")
		end,

		gripC0 = CFrame.identity,
		gripC1 = CFrame.identity,

		-- Equip hook: turn the trajectory aimer on while the grenade is held.
		-- Left-click hands the landing point back through Execute (synthetic
		-- "Granade" key). Returns the teardown the context runs on unequip/swap.
		onEquipCBClient = function(context)
			sightClass.init(function(landingPos)
				context:Execute({ Name = "Grenade" }, { clickPosition = landingPos })
			end)
			return function()
				sightClass.finish()
			end
		end,
	}

	info["grenade"] = grenade
end

module.info = Table.errorOnNilIndex(info)

function module:getweapon(WeaponName: string)
	return info[WeaponName]
end

return module
