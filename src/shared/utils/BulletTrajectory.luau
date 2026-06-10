local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local testPart = require(ReplicatedStorage.Shared.test.testPart)
return function(origin, destiny, maxVelocity)
	local bullet = ReplicatedStorage.Shared.Effects.Bullet:Clone()
	bullet.Parent = workspace
	-- bullet:PivotTo(origin)

	local attachmentAlignPos = Instance.new("Attachment")
	attachmentAlignPos.Name = "attachmentDash"
	attachmentAlignPos.Visible = false
	attachmentAlignPos.Parent = bullet

	local alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = attachmentAlignPos
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.MaxForce = math.huge
	alignPos.MaxVelocity = maxVelocity
	alignPos.Position = destiny
	alignPos.Responsiveness = 200
	alignPos.ApplyAtCenterOfMass = true
	alignPos.Parent = bullet
	Debris:AddItem(alignPos, 1)
	Debris:AddItem(attachmentAlignPos, 1)
	-- Debris:AddItem(bullet)

	-- testPart({
	-- 	Position = destiny,
    --     Name = "testMe",
	-- 	Size = Vector3.new(5, 5, 5),
	-- 	Color3 = Color3.fromRGB(255, 0, 0),
	-- })
end
