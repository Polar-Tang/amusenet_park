local RS = game:GetService("ReplicatedStorage")
local EffectTypes = require(script.Parent.EffectTypes)
local VFXAllClients = RS.Shared.RemoteEvents.VFX
export type VFX = EffectTypes.VFX

return function(vfxs: { VFX })
	if not vfxs then
		print("Calling roll_vfx with no vfx arg")
	end
	for _, vfx in ipairs(vfxs) do
		VFXAllClients:FireAllClients({
			Attacker = vfx.Attacker,
			Defender = vfx.Defender,
			action = vfx.action,
			dashDir = vfx.dashDir,
			camYaw = vfx.camYaw,
			animName = vfx.animName,
			["Pos"] = vfx.Pos,
			attackId = vfx.attackId,
			destroy = vfx.destroy,
			["CF"] = vfx.CF,
			life_time = vfx.life_time,
			dir = vfx.dir,
			src = vfx.src,
			create_point = vfx.create_point,
			camera_location = vfx.camera_location,
			look_to = vfx.look_to,
			src2 = vfx.src2,
			Size = vfx.Size,
			Size2 = vfx.Size2,
			src_model = vfx.src_model,
			src_model2 = vfx.src_model2,
			scaleTo = vfx.scaleTo,
			rayResults = vfx.rayResults,
			-- Kinematic projectile flight (grenade): replicated so every client
			-- pivots the model along the same predicted arc.
			startPosition = vfx.startPosition,
			initialVelocity = vfx.initialVelocity,
			flightTime = vfx.flightTime,
		})
	end
end
