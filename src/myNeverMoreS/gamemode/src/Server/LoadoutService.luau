--[=[
	@class LoadoutService
	Hands a real player their weapon loadout: clones the Tools named by the
	player's PROFILE out of `ServerStorage.<LOADOUT_FOLDER>` into both their
	`StarterGear` (so the loadout survives every respawn — the engine re-copies
	StarterGear into the Backpack on each spawn) and their live Backpack (for the
	current life, since StarterGear set after a spawn doesn't retroactively fill
	that life's Backpack).

	This REPLACES StarterPack as the weapon source. StarterPack is copied by the
	engine into EVERY player's Backpack on every spawn — it is global, so it can't
	express a per-player profile loadout. `StarterGear` is the per-player
	equivalent and is what gives us "survives respawn" for free.

	Where the profile comes from: a player teleported in from the lobby carries a
	`loadoutByUserId` map in TeleportData (the same pattern as the quest snapshot
	ServiceRoot reads). A direct join (no lobby payload) has no profile, so it
	falls back to the full arsenal (`weaponConstants.LOADOUT_WEAPON_IDS`).

	The default fist is NEVER handed out here: it is a strategy-only weapon that
	equips with no Tool (characterCtxUtils.EquipDefaultWeapon), and putting a fist
	Tool in a Backpack would both break that contract and show in the backpack UI.
	`weaponConstants.isLoadoutWeapon` enforces this — fist can never be a loadout id.

	Server-only. Bots are untouched: an NPC rig ships its own Tool child
	(NPCServer.Init equips it), so this is exclusively the real-player loadout.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local weaponConstants = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.weaponConstants)

local LoadoutService = {}

-- Reads the player's loadout profile from TeleportData. Mirrors ServiceRoot's
-- quest snapshot read: the lobby packs each player's loadout under their userId
-- in `loadoutByUserId`. Returns the validated id list, or the direct-join
-- fallback (the full arsenal) when there is no lobby payload. `GetJoinData` does
-- not yield and is pcall'd because it can throw before the player is fully ready.
function LoadoutService.ResolveLoadout(player: Player): weaponConstants.LoadoutProfile
	local joinOk, joinData = pcall(player.GetJoinData, player)
	if joinOk and type(joinData) == "table" then
		local teleportData = joinData.TeleportData
		if type(teleportData) == "table" and type(teleportData.loadoutByUserId) == "table" then
			local record = teleportData.loadoutByUserId[tostring(player.UserId)]
			if type(record) == "table" then
				-- Crosses TeleportData as `any` — validate each id at this boundary so
				-- a typo'd / spoofed / fist entry can't reach a Backpack clone.
				local loadout: weaponConstants.LoadoutProfile = {}
				for _, id in record do
					if weaponConstants.isLoadoutWeapon(id) then
						table.insert(loadout, id :: weaponConstants.LoadoutWeaponId)
					else
						warn(`[LoadoutService] {player.Name} loadout has unknown/illegal weapon id "{tostring(id)}" — skipped`)
					end
				end
				return loadout
			end
		end
	end

	-- Direct join (no lobby teleport payload): hand the full arsenal.
	return table.clone(weaponConstants.LOADOUT_WEAPON_IDS)
end

--[=[
	Clones the player's profile loadout into their StarterGear (respawn
	persistence) and current Backpack (this life). A no-op for bots (no owning
	Player). Idempotent: a re-fired onCharacterAdded (the match-start sweep
	overlapping CharacterAdded, or the engine's own StarterGear -> Backpack copy on
	respawn) must not stack duplicates, so every clone is guarded by name.
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

	-- StarterGear always exists on a Player; Backpack only while a character is
	-- alive (absent between death and respawn). Tolerate a missing Backpack — the
	-- StarterGear write still seeds the next spawn.
	local starterGear = player:FindFirstChildOfClass("StarterGear")
	local backpack = player:FindFirstChildOfClass("Backpack")

	for _, weaponId in LoadoutService.ResolveLoadout(player) do
		local template = folder:FindFirstChild(weaponId)
		if not template or not template:IsA("Tool") then
			-- A profile id with no matching Tool template is an authoring gap (the
			-- artist hasn't placed that weapon), not a wiring bug — warn, don't crash.
			warn(`[LoadoutService] no Tool "{weaponId}" in ServerStorage.{GameModeConstants.LOADOUT_FOLDER} — skipped for {player.Name}`)
			continue
		end

		if starterGear and not starterGear:FindFirstChild(weaponId) then
			template:Clone().Parent = starterGear
		end
		if
			backpack
			and not backpack:FindFirstChild(weaponId)
			and not character:FindFirstChild(weaponId)
		then
			template:Clone().Parent = backpack
		end
	end
end

return LoadoutService
