local M = {}

local AFUS_NAMES = {
	armafus = true,
	corafus = true,
	legafus = true,
}

local function isAFUS(name)
	return AFUS_NAMES[name] == true
end

function M.Apply()
	for name, unitDef in pairs(UnitDefs) do
		if isAFUS(name) then
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
				cegtag = "NUKETRAIL",
				edgeeffectiveness = 0.15,
				explosiongenerator = "custom:afusexplxl",
				flighttime = 40,
				impulsefactor = 1,
				interceptor = 2,
				model = unitDef.objectname,
				name = "AFUS Supremacy Payload",
				range = 10000,
				reloadtime = 1,
				smokecolor = 0.85,
				smokeperiod = 8,
				smokesize = 32,
				smoketime = 130,
				smoketrail = true,
				smoketrailcastshadow = true,
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
					afus_source_unit = name,
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
