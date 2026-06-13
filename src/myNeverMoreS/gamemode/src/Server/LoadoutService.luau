--[=[
	@class LoadoutService
	Hands a real player their weapon loadout by cloning every Tool under
	`ServerStorage.<LOADOUT_FOLDER>` into the player's Backpack.

	This REPLACES StarterPack as the weapon source. StarterPack is copied by the
	engine into every player's Backpack on every spawn, in every mode — so a mode
	could never opt out. Driving the loadout from `ModeConfig.giveLoadout` instead
	lets Last Man Standing leave players on the default fist (giveLoadout = false)
	while the team modes still arm everyone (giveLoadout = true). Empty StarterPack
	in Studio and move the weapon Tools into ServerStorage.<LOADOUT_FOLDER>.

	Server-only. Bots are untouched: an NPC rig ships its own Tool child
	(NPCServer.Init equips it), so this is exclusively the real-player loadout.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)

local LoadoutService = {}

--[=[
	Clones the loadout Tools into `character`'s player Backpack. A no-op for bots
	(no owning Player) and idempotent: a re-fired onCharacterAdded (the
	match-start sweep overlapping the CharacterAdded signal) must not stack
	duplicates. A respawn gets a fresh empty Backpack, so the skip below only ever
	guards a true double-call within one life.
]=]
function LoadoutService.GiveLoadout(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local folder = ServerStorage:FindFirstChild(GameModeConstants.LOADOUT_FOLDER)
	if not folder then
		warn(`[LoadoutService] ServerStorage.{GameModeConstants.LOADOUT_FOLDER} is missing — no weapons handed out`)
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	for _, template in folder:GetChildren() do
		if
			template:IsA("Tool")
			and not backpack:FindFirstChild(template.Name)
			and not character:FindFirstChild(template.Name)
		then
			template:Clone().Parent = backpack
		end
	end
end

return LoadoutService
