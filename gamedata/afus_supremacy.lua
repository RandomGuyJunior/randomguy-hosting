local M = {}

local AFUS_NAMES = {
	armafus = true,
	corafus = true,
	legafus = true,
}

local function isAFUS(name, unitDef)
	if AFUS_NAMES[name] then
		return true
	end
	local cp = unitDef.customparams or unitDef.customParams
	local source = cp and cp.rg_team_tweak_source
	return source and AFUS_NAMES[string.lower(source)] or false
end

function M.Apply()
	for name, unitDef in pairs(UnitDefs) do
		if isAFUS(name, unitDef) then
			unitDef.canattack = false
			unitDef.noautofire = true
			unitDef.weapondefs = unitDef.weapondefs or {}
			unitDef.weapons = unitDef.weapons or {}

			unitDef.weapondefs.afus_supremacy_payload = {
				areaofeffect = 1920,
				avoidfeature = false,
				avoidfriendly = false,
				collideenemy = false,
				collidefeature = false,
				collidefriendly = false,
				coverage = 3500,
				edgeeffectiveness = 0.15,
				explosiongenerator = "custom:afusexplxl",
				flighttime = 40,
				impulsefactor = 1,
				interceptor = 2,
				model = unitDef.objectname,
				name = "AFUS Supremacy Payload",
				range = 10000,
				reloadtime = 1,
				soundhit = "xplonuk3",
				soundstart = "largegun",
				targetable = 2,
				tolerance = 10000,
				tracks = true,
				turnrate = 12000,
				weaponacceleration = 300,
				weapontimer = 8,
				weapontype = "StarburstLauncher",
				weaponvelocity = 1800,
				customparams = {
					afus_supremacy = 1,
					kamikaze_mode = "consume",
				},
				damage = {
					commanders = 3000,
					default = 12800,
				},
			}

			unitDef.weapons[#unitDef.weapons + 1] = {
				def = "AFUS_SUPREMACY_PAYLOAD",
				onlytargetcategory = "NONE",
			}

			unitDef.customparams = unitDef.customparams or {}
			unitDef.customparams.afus_supremacy = 1
		end
	end
end

return M
