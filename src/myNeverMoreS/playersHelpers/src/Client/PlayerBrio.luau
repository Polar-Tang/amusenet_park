--[[ PlayerBrio.lua ]]
local Players = game:GetService("Players")
local require = require(script.Parent.loader).load(script)
local RxCharacterUtils = require("RxCharacterUtils")
local Maid = require("Maid")

local PlayerBrio = {}
PlayerBrio.__index = PlayerBrio

function PlayerBrio.new()
    local self = setmetatable({}, PlayerBrio)
    
    self._maid = Maid.new()
    self._observable = RxCharacterUtils.observeLastCharacterBrio(Players.LocalPlayer)
    
    return self
end

-- Each module can call this to add their own logic
function PlayerBrio:Subscribe(callback)
    -- Each Subscribe call creates an independent subscription
    local connection = self._observable:Subscribe(callback)
    
    -- Return the connection so caller can clean it up if needed
    return connection
end

function PlayerBrio:Destroy()
    self._maid:Destroy()
end

return PlayerBrio