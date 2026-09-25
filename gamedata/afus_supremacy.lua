local M = {}

local AFUS_NAMES = {
	armafus = true,
	corafus = true,
	legafus = true,
}

local function sourceName(name, unitDef)
	local cp = unitDef.customparams or {}
	return string.lower(cp.rg_team_tweak_source or name)
end

local function isAFUS(name, unitDef)
	return AFUS_NAMES[sourceName(name, unitDef)] == true
end

local function payloadBase(unitDef)
	return {
		avoidfeature = false,
		avoidfriendly = false,
		collideenemy = false,
		collidefeature = false,
		collidefriendly = false,
		cegtag = "NUKETRAIL",
		flighttime = 40,
		model = unitDef.objectname,
		reloadtime = 1,
		smokecolor = 0.85,
		smokeperiod = 8,
		smokesize = 32,
		smoketime = 130,
		smoketrail = true,
		smoketrailcastshadow = true,
		tolerance = 10000,
		tracks = true,
		turnrate = 12000,
		weaponacceleration = 300,
		weapontimer = 8,
		weapontype = "StarburstLauncher",
		weaponvelocity = 1800,
	}
end

function M.Apply()
	for name, unitDef in pairs(UnitDefs) do
		if isAFUS(name, unitDef) then
			local source = sourceName(name, unitDef)
			unitDef.weapondefs = unitDef.weapondefs or {}
			unitDef.weapons = unitDef.weapons or {}
			unitDef.customparams = unitDef.customparams or {}

			local launcher = payloadBase(unitDef)
			launcher.areaofeffect = 1920
			launcher.edgeeffectiveness = 0.15
			launcher.explosiongenerator = "custom:afusexplxl"
			launcher.impulsefactor = 1
			launcher.name = "AFUS Supremacy Launcher"
			launcher.range = 10000
			launcher.soundhit = "xplonuk3"
			launcher.soundstart = "largegun"
			launcher.targetable = 2
			launcher.customparams = {
				afus_supremacy = 1,
				afus_supremacy_role = "launcher",
				afus_source_unit = source,
				kamikaze_mode = "consume",
			}
			launcher.damage = {
				commanders = 3000,
				default = 12800,
			}

			local interceptor = payloadBase(unitDef)
			interceptor.areaofeffect = 420
			interceptor.coverage = 3500
			interceptor.edgeeffectiveness = 0.15
			interceptor.explosiongenerator = "custom:antinuke"
			interceptor.impulsefactor = 0.123
			interceptor.interceptor = 2
			interceptor.name = "AFUS Supremacy Interceptor"
			interceptor.range = 3500
			interceptor.soundhit = "xplomed4"
			interceptor.soundstart = "antinukelaunch"
			interceptor.customparams = {
				afus_supremacy = 1,
				afus_supremacy_role = "interceptor",
				afus_source_unit = source,
				kamikaze_mode = "consume",
			}
			interceptor.damage = {
				default = 1500,
			}

			unitDef.weapondefs.afus_supremacy_launcher = launcher
			unitDef.weapondefs.afus_supremacy_interceptor = interceptor

			-- Only the interceptor needs to be mounted. This gives the UnitDef a real
			-- interceptor weapon (and therefore engine/UI coverage) while the gadget
			-- spawns both projectile types directly so the AFUS COB scripts need no
			-- weapon callbacks.
			unitDef.weapons[#unitDef.weapons + 1] = {
				def = "AFUS_SUPREMACY_INTERCEPTOR",
				onlytargetcategory = "NONE",
			}

			unitDef.customparams.afus_supremacy = 1
			unitDef.customparams.afus_supremacy_source = source
		end
	end
end

return M
