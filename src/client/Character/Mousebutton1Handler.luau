local Mousebutton1Handler = {}
Mousebutton1Handler.__index = Mousebutton1Handler
local bool: BoolValue = Instance.new("BoolValue")

Mousebutton1Handler.M1PressedValueObject = bool
function Mousebutton1Handler.InputBegan()
	print("bool.Value ", bool.Value)
	bool.Value = true
end

function Mousebutton1Handler.InputEnded()
	print("bool.Value ", bool.Value)

	bool.Value = false
end

return Mousebutton1Handler
