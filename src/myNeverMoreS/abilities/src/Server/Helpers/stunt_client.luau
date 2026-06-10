local require = require(script.Parent.loader).load(script)
local stunHandler = require("StunHandlerV2")

return function(Hum: Humanoid, dur: number)
	Hum.WalkSpeed = 14
	Hum.JumpHeight = 6.5
	stunHandler.Stun(Hum,dur)
end
