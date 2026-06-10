local Players = game:GetService("Players")
local Attkcs = {}

local anim_names = {

	["FrontDash"] = "rbxassetid://132739372863099",
	-- ["Kafka -BackDash"] = "rbxassetid://85575014339192",
	["DashLeft"] = "rbxassetid://79328523085486",
	["DashRight"] = "rbxassetid://92616275644680",
}

export type AttackGroup = {
	[string]: string, -- any key inside groups maps to an animationId string
}

export type Weapon = {
	Attacking: AttackGroup,
	Hit: AttackGroup,
	Sprint: string,
	Equip: string,
	Idle: string,
	UnEquip: string,
}

export type Attkcs = {
	[string]: Weapon,
}
Attkcs["fist"] = {
	["Heavy"] = "rbxassetid://70389048224933",
	["Swing1"] = "rbxassetid://91603464878080",
	["Swing2"] = "rbxassetid://94784293010682",
	["Swing3"] = "rbxassetid://84658758864339",
	["Swing4"] = "rbxassetid://118704582043779",

	["Sprint"] = "rbxassetid://130609866336149",
	["Equip"] = "rbxassetid://91567634616046",
	["Idle"] = "rbxassetid://91567634616046",
	["UnEquip"] = "rbxassetid://76401194937920",
	["Blocking"] = "rbxassetid://109266615151969",
	["GuardBreak"] = "rbxassetid://70952470480164",
}

Attkcs["gun"] = {
	["Equip"] = "rbxassetid://78370442833784",
	["Equiped"] = "rbxassetid://90507630054028",

	
}
Attkcs["ak-47"] = {
	["Equip"] = "rbxassetid://70796249478633",
	["Equiped"] = "rbxassetid://127661744213520",
	
}

Attkcs["grenade"] = {
	["Equip"] = "rbxassetid://98397669915947",
	["Equiped"] = "rbxassetid://98760522260087",

	["Throw"] = "rbxassetid://131063559134926",
	
}


return Attkcs :: Attkcs
