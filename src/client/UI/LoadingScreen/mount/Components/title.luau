local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Public.assets)
local Roact = require(ReplicatedStorage.Shared.Roact)
local screen = Roact.Component:extend("CustomProximityPrompts")

function screen:render()
    return Roact.createElement("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
    }, {
        Padding = Roact.createElement("UIPadding", {
            PaddingTop = UDim.new(0, 20),
        }),
        Layout = Roact.createElement("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Top,
            Padding = UDim.new(0, 16),
        }),
        ImageCard = Roact.createElement("ImageLabel", {
            Size = UDim2.new(0.75, 0, 0.6, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = assets.brand.Full_logo,
            LayoutOrder = 1,
        }),
    })
end

return screen
