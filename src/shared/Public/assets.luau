local module = {}

module["brand"] = {
	["Full_logo"] = "rbxassetid://89797270636476",
}

module["crosshair"] = {

	["default_croshair"] = "rbxassetid://123216112921702",
	["default_LSup"] = "rbxassetid://79494722292090",
	["default_LSub"] = "rbxassetid://123740399475529",
	["default_RSup"] = "rbxassetid://119766150523863",
	["default_RSub"] = "rbxassetid://106343537336775",
}

module["mobile_buttons"] = {

	["slide"] = "rbxassetid://133125084307093",
	["shot"] = "rbxassetid://86052129606147",
	["crosshair"] = "rbxassetid://93504298175313",
	["charge"] = "rbxassetid://135878733586229",
	["run"] = "rbxassetid://112163155880552",

}

module["spin_roullete"] = {
	["wheel"] = "rbxassetid://71350965359699",
	["pointer"] = "rbxassetid://6034287551",
}

-- Overhead "carrying the flag" icon, one per team id (Crimson / Azure). The
-- FlagBillboard component picks by the carrier's team. PLACEHOLDER ids (reusing
-- the roulette pointer) — swap each for the real per-team art when it exists.
module["flag_carrier"] = {
	["Crimson"] = "rbxassetid://6034287551",
	["Azure"] = "rbxassetid://6034287551",
}

return module
