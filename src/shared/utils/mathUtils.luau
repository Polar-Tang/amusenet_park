local module = {}

function module.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

module.getPercentage = function(T, fr)
	--[[
					1000 -> 100
					200  -> (200*100)/1000
					
					100 -> 1000
					0.5 -> 100/(1000*0.5)
				]]
	return T * fr / 100
end

return module