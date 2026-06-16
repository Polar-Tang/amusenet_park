--[=[
	@class weaponConstants
	The canonical set of weapon ids — the SAME strings CombatConfig keys its
	strategies by (`info["fist"]`, `info["gun"]`, `info["ak-47"]`, `info["grenade"]`)
	and that the equip path lowercases off a Tool's Name. This is the single place
	the "what weapons exist" list is spelled out, so the strict `WeaponId` type and
	the loadout system can't drift from the strategies.

	`WEAPON_IDS` is the membership form (CombatConfig asserts every strategy key is
	in here, so a new strategy without a matching `WeaponId` entry fails loud).
	`LOADOUT_WEAPON_IDS` is the backpack-insertable subset — every weapon EXCEPT
	the default fist, which is a strategy-only weapon that must never enter a
	Backpack/StarterGear (it equips with no Tool; see characterCtxUtils
	EquipDefaultWeapon). It doubles as the direct-join loadout fallback.
]=]

-- The fist is a real strategy but is NEVER a loadout Tool, so it is intentionally
-- absent from `LoadoutWeaponId` / `LOADOUT_WEAPON_IDS`.
export type WeaponId = "fist" | "gun" | "ak-47" | "grenade"
export type LoadoutWeaponId = "gun" | "ak-47" | "grenade"
export type LoadoutProfile = { LoadoutWeaponId }

local weaponConstants = {}

-- Every weapon strategy CombatConfig ships. Keep in lockstep with `WeaponId`;
-- CombatConfig asserts each `info` key is present here at module load.
weaponConstants.WEAPON_IDS = {
	fist = true,
	gun = true,
	["ak-47"] = true,
	grenade = true,
} :: { [string]: boolean }

-- Backpack-insertable weapons (no fist), in display/insert order. Also the
-- direct-join loadout fallback: a player who arrives with no TeleportData
-- loadout (a direct join, not a lobby teleport) is handed all of these.
weaponConstants.LOADOUT_WEAPON_IDS = { "gun", "ak-47", "grenade" } :: { LoadoutWeaponId }

-- True only for ids that may be cloned into a Backpack/StarterGear: a real weapon
-- id that is not the strategy-only fist. Used to validate a TeleportData loadout.
function weaponConstants.isLoadoutWeapon(id: string): boolean
	return weaponConstants.WEAPON_IDS[id] == true and id ~= "fist"
end

return weaponConstants
