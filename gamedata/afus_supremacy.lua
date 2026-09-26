local M = {}

local AFUS_NAMES = {
	armafus = "Units/armafus_projectile.s3o",
	corafus = "Units/corafus_projectile.s3o",
	legafus = "Units/legafus_projectile.s3o",
}

local function getSourceName(name, unitDef)
	local cp = unitDef.customparams or {}
	return string.lower(cp.rg_team_tweak_source or name)
end

local function makeLauncher(model)
	return {
		areaofeffect = 1920,
		avoidfeature = false,
		avoidfriendly = false,
		cegtag = "NUKETRAIL",
		collideenemy = false,
		collidefeature = false,
		collidefriendly = false,
		commandfire = true,
		edgeeffectiveness = 0.15,
		explosiongenerator = "custom:afusexplxl",
		flighttime = 12,
		impulsefactor = 1,
		model = model,
		name = "AFUS Supremacy Launcher",
		range = 10000,
		reloadtime = 10,
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
		turnrate = 18000,
		weapontimer = 4,
				weaponacceleration = 600,
		weapontype = "StarburstLauncher",
		weaponvelocity = 2200,
		customparams = {
			afus_supremacy = 1,
			afus_supremacy_role = "launcher",
		},
		damage = {
			commanders = 3000,
			default = 12800,
		},
	}
end

local function makeInterceptor(model)
	return {
		areaofeffect = 420,
		avoidfeature = false,
		avoidfriendly = false,
		cegtag = "NUKETRAIL",
		collideenemy = false,
		collidefeature = false,
		collidefriendly = false,
		coverage = 3500,
		edgeeffectiveness = 0.15,
		explosiongenerator = "custom:antinuke",
		flighttime = 12,
		impulsefactor = 0.123,
		interceptor = 2,
		model = model,
		name = "AFUS Supremacy Interceptor",
		range = 3500,
		reloadtime = 2,
		smokecolor = 0.85,
		smokeperiod = 8,
		smokesize = 32,
		smoketime = 130,
		smoketrail = true,
		smoketrailcastshadow = true,
		soundhit = "xplomed4",
		soundstart = "antinukelaunch",
		tolerance = 10000,
		tracks = true,
		turnrate = 18000,
		weapontimer = 2,
				weaponacceleration = 600,
		weapontype = "StarburstLauncher",
		weaponvelocity = 2200,
		customparams = {
			afus_supremacy = 1,
			afus_supremacy_role = "interceptor",
		},
		damage = {
			default = 1500,
		},
	}
end

local function shouldApply(unitDef, globalEnabled, teamOptions)
	if globalEnabled then
		return true
	end

	local cp = unitDef.customparams or {}
	local slot = tonumber(cp.rg_team_tweak_slot)
	return slot ~= nil and teamOptions.TeamHasFeature(slot, "afus_supremacy")
end

function M.Apply(globalEnabled, teamOptions)
	for name, unitDef in pairs(UnitDefs) do
		local source = getSourceName(name, unitDef)
		local projectileModel = AFUS_NAMES[source]

		if projectileModel and shouldApply(unitDef, globalEnabled, teamOptions) then
			unitDef.weapondefs = unitDef.weapondefs or {}
			unitDef.weapons = unitDef.weapons or {}
			unitDef.customparams = unitDef.customparams or {}

			unitDef.canmanualfire = true
			unitDef.script = "Units/afus_supremacy.lua"

			unitDef.weapondefs.afus_supremacy_launcher = makeLauncher(projectileModel)
			unitDef.weapondefs.afus_supremacy_interceptor = makeInterceptor(projectileModel)

			unitDef.weapons[#unitDef.weapons + 1] = {
				def = "AFUS_SUPREMACY_LAUNCHER",
				onlytargetcategory = "NOTSUB",
			}
			unitDef.weapons[#unitDef.weapons + 1] = {
				def = "AFUS_SUPREMACY_INTERCEPTOR",
				badtargetcategory = "ALL",
			}

			unitDef.customparams.afus_supremacy = 1
		end
	end
end

return M
