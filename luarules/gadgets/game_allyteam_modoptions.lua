local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Team Options",
		desc = "Provides team-specific modoptions and tweak configuration",
		author = "RandomGuyJunior",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = -1000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

--------------------------------------------------------------------------------
-- Spring aliases
--------------------------------------------------------------------------------

local spGetModOptions = Spring.GetModOptions
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetTeamList = Spring.GetTeamList
local spSetUnitRulesParam = Spring.SetUnitRulesParam
local spSetUnitBuildParams = Spring.SetUnitBuildParams
local spSetUnitMetalExtraction = Spring.SetUnitMetalExtraction
local spSetUnitResourcing = Spring.SetUnitResourcing
local spSetUnitStorage = Spring.SetUnitStorage
local spSetUnitSensorRadius = Spring.SetUnitSensorRadius
local spSetUnitWeaponState = Spring.SetUnitWeaponState
local spSetUnitWeaponDamages = Spring.SetUnitWeaponDamages
local spSetUnitMaxRange = Spring.SetUnitMaxRange

--------------------------------------------------------------------------------
-- Team mapping
--------------------------------------------------------------------------------

local playableAllyTeams = {}
local teamSlotToAllyTeam = {}
local allyTeamToTeamSlot = {}
local teamIDToTeamSlot = {}

--------------------------------------------------------------------------------
-- Parsed options
--------------------------------------------------------------------------------

local teamOptions = {}

--------------------------------------------------------------------------------
-- Feature state
--------------------------------------------------------------------------------

local globalScavUnits = false
local globalExperimentalUnits = false

local teamScavFeatureActive = false
local teamExperimentalFeatureActive = false

local teamScavEnabled = {}
local teamExperimentalEnabled = {}

-- Numeric BAR cheat/modoption multipliers that can be applied per unit at runtime.
-- Each option independently defers to BAR's normal global implementation whenever
-- the corresponding global modoption differs from its default value (1).
local numericOptionKeys = {
	"multiplier_buildpower",
	"multiplier_builddistance",
	"multiplier_resourceincome",
	"multiplier_metalextraction",
	"multiplier_energyconversion",
	"multiplier_energyproduction",
	"multiplier_maxvelocity",
	"multiplier_turnrate",
	"multiplier_losrange",
	"multiplier_radarrange",
	"multiplier_weaponrange",
	"multiplier_weapondamage",
	"multiplier_shieldpower",
}

local globalNumericOverride = {}
local teamNumericValues = {}
local teamNumericFeatureActive = false

--------------------------------------------------------------------------------
-- Build option definitions
--------------------------------------------------------------------------------

-- These reproduce BAR's:
-- unitbasedefs/scavenger_units_for_players.lua
--
-- builder name -> units added to that builder
local scavBuildOptions = {
	armaca = {
		"armapt3",
		"armminivulc",
		"armbotrail",
		"armannit3",
		"armafust3",
		"armmmkrt3",
	},
	armack = {
		"armapt3",
		"armminivulc",
		"armbotrail",
		"armannit3",
		"armafust3",
		"armmmkrt3",
	},
	armacv = {
		"armapt3",
		"armminivulc",
		"armbotrail",
		"armannit3",
		"armafust3",
		"armmmkrt3",
	},

	armasy = {
		"armdronecarry",
		"armptt2",
		"armdecadet3",
		"armpshipt3",
		"armserpt3",
		"armtrident",
	},

	armshltx = {
		"armrattet4",
		"armsptkt4",
		"armpwt4",
		"armvadert4",
		"armdronecarryland",
	},

	armshltxuw = {
		"armrattet4",
		"armsptkt4",
		"armpwt4",
		"armvadert4",
	},

	corlab = {
		"corkark",
	},

	coraca = {
		"corapt3",
		"corminibuzz",
		"corhllllt",
		"cordoomt3",
		"corafust3",
		"cormmkrt3",
	},
	corack = {
		"corapt3",
		"corminibuzz",
		"corhllllt",
		"cordoomt3",
		"corafust3",
		"cormmkrt3",
	},
	coracv = {
		"corapt3",
		"corminibuzz",
		"corhllllt",
		"cordoomt3",
		"corafust3",
		"cormmkrt3",
	},

	coravp = {
		"corgatreap",
		"corftiger",
	},

	coraap = {
		"corcrw",
	},

	corasy = {
		"cordronecarry",
		"corslrpc",
		"corsentinel",
	},

	corgant = {
		"corkarganetht4",
		"corakt4",
		"corthermite",
		"cormandot4",
	},

	corgantuw = {
		"corkarganetht4",
		"corakt4",
		"cormandot4",
	},

	legaca = {
		"legapt3",
		"legministarfall",
		"legafust3",
		"legadveconvt3",
	},
	legack = {
		"legapt3",
		"legministarfall",
		"legafust3",
		"legadveconvt3",
	},
	legacv = {
		"legapt3",
		"legministarfall",
		"legafust3",
		"legadveconvt3",
	},

	leggant = {
		"legsrailt4",
		"leggobt3",
		"legpede",
		"legeheatraymech_old",
	},
}

-- These reproduce BAR's:
-- unitbasedefs/experimental_extra_units.lua
local experimentalBuildOptions = {
	armcs = {
		"armgplat",
		"armfrock",
	},
	armcsa = {
		"armgplat",
		"armfrock",
	},

	armvp = {
		"armzapper",
	},

	armap = {
		"armfify",
	},

	armaca = {
		"armshockwave",
		"armwint2",
		"armnanotct2",
		"armlwall",
		"armgatet3",
	},
	armack = {
		"armshockwave",
		"armwint2",
		"armnanotct2",
		"armlwall",
		"armgatet3",
	},
	armacv = {
		"armshockwave",
		"armwint2",
		"armnanotct2",
		"armlwall",
		"armgatet3",
	},

	armacsub = {
		"armfgate",
		"armnanotc2plat",
	},

	armasy = {
		"armexcalibur",
		"armseadragon",
	},

	armshltx = {
		"armmeatball",
		"armassimilator",
	},

	armshltxuw = {
		"armmeatball",
		"armassimilator",
	},

	corcs = {
		"corgplat",
		"corfrock",
	},
	corcsa = {
		"corgplat",
		"corfrock",
	},

	coraca = {
		"corwint2",
		"cornanotct2",
		"cormwall",
		"corgatet3",
	},
	corack = {
		"corwint2",
		"cornanotct2",
		"cormwall",
		"corgatet3",
	},
	coracv = {
		"corwint2",
		"cornanotct2",
		"cormwall",
		"corgatet3",
	},

	coracsub = {
		"corfgate",
		"cornanotc2plat",
	},

	coralab = {
		"cordeadeye",
	},

	coravp = {
		"corvac",
		"corphantom",
		"corsiegebreaker",
		"corforge",
		"cortorch",
	},

	corasy = {
		"coresuppt3",
		"coronager",
		"cordesolator",
		"corprince",
	},

	corgant = {
		"corves",
	},

	corgantuw = {
		"corves",
	},

	legca = {
		"legmext15",
	},
	legck = {
		"legmext15",
	},
	legcv = {
		"legmext15",
	},

	legaca = {
		"legwint2",
		"legnanotct2",
		"legrwall",
		"leggatet3",
	},
	legack = {
		"legwint2",
		"legnanotct2",
		"legrwall",
		"leggatet3",
	},
	legacv = {
		"legwint2",
		"legnanotct2",
		"legrwall",
		"leggatet3",
	},

	leganavyconsub = {
		"corfgate",
		"legnanotct2plat",
	},

	leggant = {
		"legbunk",
		"legapollyon",
	},
}

--------------------------------------------------------------------------------
-- Resolved UnitDef caches
--------------------------------------------------------------------------------

-- unitDefID -> { builtUnitDefID, ... }
local scavBuildOptionsByDefID = {}
local experimentalBuildOptionsByDefID = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Echo(...)
	Spring.Echo("[Team Options]", ...)
end

local function IsEnabled(value)
	return value == true
		or value == 1
		or value == "1"
		or value == "true"
		or value == "enabled"
end

local function NumericValue(value, fallback)
	local numberValue = tonumber(value)

	if numberValue ~= nil then
		return numberValue
	end

	return fallback
end

local function NumericDiffersFromDefault(value)
	return math.abs(NumericValue(value, 1) - 1) > 0.000001
end

--------------------------------------------------------------------------------
-- Mapping
--------------------------------------------------------------------------------

local function BuildTeamMapping()
	local gaiaTeamID = spGetGaiaTeamID()
	local gaiaAllyTeamID = select(
		6,
		spGetTeamInfo(gaiaTeamID, false)
	)

	local allyTeams = spGetAllyTeamList()

	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]

		if allyTeamID ~= gaiaAllyTeamID then
			playableAllyTeams[#playableAllyTeams + 1] =
				allyTeamID
		end
	end

	table.sort(playableAllyTeams)

	for slot = 1, math.min(#playableAllyTeams, 8) do
		local allyTeamID = playableAllyTeams[slot]

		teamSlotToAllyTeam[slot] = allyTeamID
		allyTeamToTeamSlot[allyTeamID] = slot

		local teams = spGetTeamList(allyTeamID)

		for i = 1, #teams do
			local teamID = teams[i]

			if teamID ~= gaiaTeamID then
				teamIDToTeamSlot[teamID] = slot
			end
		end

		Echo(
			"Team",
			slot,
			"mapped to allyTeamID",
			allyTeamID
		)
	end
end

--------------------------------------------------------------------------------
-- Team option parsing
--------------------------------------------------------------------------------

local function ParseValue(value)
	if value == "true" then
		return true
	end

	if value == "false" then
		return false
	end

	local numberValue = tonumber(value)

	if numberValue ~= nil then
		return numberValue
	end

	return value
end

local function ParseOptionString(input)
	local result = {}

	if not input or input == "" then
		return result
	end

	for line in string.gmatch(input, "[^\r\n]+") do
		local key, value = string.match(
			line,
			"^%s*([^=]+)%s*=%s*(.-)%s*$"
		)

		if key and value and key ~= "" then
			result[string.lower(key)] =
				ParseValue(value)
		else
			Echo(
				"Ignoring invalid option:",
				line
			)
		end
	end

	return result
end

local function LoadTeamOptions()
	local modOptions = spGetModOptions()

	for slot = 1, 8 do
		local key =
			"team" .. slot .. "_options"

		local value = modOptions[key]

		if value and value ~= "" then
			teamOptions[slot] =
				ParseOptionString(value)

			Echo(
				"Loaded Team",
				slot,
				"options:",
				value
			)
		else
			teamOptions[slot] = {}
		end
	end
end

--------------------------------------------------------------------------------
-- Public option access
--------------------------------------------------------------------------------

local function GetTeamSlotFromTeamID(teamID)
	return teamIDToTeamSlot[teamID]
end

local function GetTeamSlotFromAllyTeamID(
	allyTeamID
)
	return allyTeamToTeamSlot[allyTeamID]
end

local function GetOptionBySlot(
	slot,
	key,
	fallback
)
	local options = teamOptions[slot]

	if options then
		local value =
			options[string.lower(key)]

		if value ~= nil then
			return value
		end
	end

	return fallback
end

local function GetOptionByTeamID(
	teamID,
	key,
	fallback
)
	local slot = teamIDToTeamSlot[teamID]

	if not slot then
		return fallback
	end

	return GetOptionBySlot(
		slot,
		key,
		fallback
	)
end

local function GetOptionByAllyTeamID(
	allyTeamID,
	key,
	fallback
)
	local slot =
		allyTeamToTeamSlot[allyTeamID]

	if not slot then
		return fallback
	end

	return GetOptionBySlot(
		slot,
		key,
		fallback
	)
end

--------------------------------------------------------------------------------
-- Feature initialization
--------------------------------------------------------------------------------

local function InitializeFeatureState()
	local modOptions = spGetModOptions()

	globalScavUnits =
		IsEnabled(
			modOptions.scavunitsforplayers
		)

	globalExperimentalUnits =
		IsEnabled(
			modOptions.experimentalextraunits
		)

	teamScavFeatureActive = false
	teamExperimentalFeatureActive = false

	for slot = 1, 8 do
		local options =
			teamOptions[slot] or {}

		if not globalScavUnits then
			teamScavEnabled[slot] =
				IsEnabled(
					options.scavunitsforplayers
				)

			if teamScavEnabled[slot] then
				teamScavFeatureActive = true
			end
		else
			teamScavEnabled[slot] = false
		end

		if not globalExperimentalUnits then
			teamExperimentalEnabled[slot] =
				IsEnabled(
					options.experimentalextraunits
				)

			if teamExperimentalEnabled[slot] then
				teamExperimentalFeatureActive = true
			end
		else
			teamExperimentalEnabled[slot] = false
		end
	end

	for i = 1, #numericOptionKeys do
		local key = numericOptionKeys[i]
		globalNumericOverride[key] =
			NumericDiffersFromDefault(modOptions[key])
	end

	for slot = 1, 8 do
		teamNumericValues[slot] = {}

		local options = teamOptions[slot] or {}

		for i = 1, #numericOptionKeys do
			local key = numericOptionKeys[i]
			local value = NumericValue(options[key], 1)

			if globalNumericOverride[key] then
				-- BAR already changed the UnitDefs globally. Do not add a
				-- second team-specific multiplier for this same feature.
				value = 1
			elseif NumericDiffersFromDefault(value) then
				teamNumericFeatureActive = true
			end

			teamNumericValues[slot][key] = value
		end
	end

	if teamNumericFeatureActive then
		Echo("Team-specific numeric multipliers active")
	end

	if globalScavUnits then
		Echo(
			"Global scavunitsforplayers is enabled; "
				.. "team-specific scav handling disabled"
		)
	elseif teamScavFeatureActive then
		Echo(
			"Team-specific scavunitsforplayers active"
		)
	end

	if globalExperimentalUnits then
		Echo(
			"Global experimentalextraunits is enabled; "
				.. "team-specific experimental handling disabled"
		)
	elseif teamExperimentalFeatureActive then
		Echo(
			"Team-specific experimentalextraunits active"
		)
	end
end

--------------------------------------------------------------------------------
-- Resolve build-option names once
--------------------------------------------------------------------------------

local function ResolveBuildOptionMap(
	source,
	target,
	featureName
)
	for builderName, builtNames in pairs(source) do
		local builderDef =
			UnitDefNames[builderName]

		if builderDef then
			local resolved = {}

			for i = 1, #builtNames do
				local builtName =
					builtNames[i]

				local builtDef =
					UnitDefNames[builtName]

				if builtDef then
					resolved[#resolved + 1] =
						builtDef.id
				else
					Echo(
						featureName,
						"unit definition not loaded:",
						builtName
					)
				end
			end

			if #resolved > 0 then
				target[builderDef.id] =
					resolved
			end
		end
	end
end

local function ResolveFeatureBuildOptions()
	if teamScavFeatureActive then
		ResolveBuildOptionMap(
			scavBuildOptions,
			scavBuildOptionsByDefID,
			"scavunitsforplayers"
		)
	end

	if teamExperimentalFeatureActive then
		ResolveBuildOptionMap(
			experimentalBuildOptions,
			experimentalBuildOptionsByDefID,
			"experimentalextraunits"
		)
	end
end

--------------------------------------------------------------------------------
-- Runtime build-option application
--------------------------------------------------------------------------------

local function SetBuildOptionsForUnit(
	unitID,
	buildOptions,
	enabled
)
	if not buildOptions then
		return
	end

	local api = GG.DynamicBuildOptions

	if not api then
		Echo(
			"DynamicBuildOptions API unavailable"
		)
		return
	end

	for i = 1, #buildOptions do
		local builtUnitDefID =
			buildOptions[i]

		if enabled then
			api.AddToUnit(
				unitID,
				builtUnitDefID
			)
		else
			api.RemoveFromUnit(
				unitID,
				builtUnitDefID
			)
		end
	end
end

local function ApplyTeamFeaturesToUnit(
	unitID,
	unitDefID,
	teamID
)
	local slot =
		teamIDToTeamSlot[teamID]

	if not slot then
		return
	end

	--
	-- Scavenger units for players
	--
	if teamScavFeatureActive then
		local options =
			scavBuildOptionsByDefID[unitDefID]

		if options then
			SetBuildOptionsForUnit(
				unitID,
				options,
				teamScavEnabled[slot] == true
			)
		end
	end

	--
	-- Experimental extra units
	--
	if teamExperimentalFeatureActive then
		local options =
			experimentalBuildOptionsByDefID[
				unitDefID
			]

		if options then
			SetBuildOptionsForUnit(
				unitID,
				options,
				teamExperimentalEnabled[slot]
					== true
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Runtime numeric multiplier application
--------------------------------------------------------------------------------

local function GetTeamNumericMultiplier(slot, key)
	local slotValues = teamNumericValues[slot]

	if not slotValues then
		return 1
	end

	return slotValues[key] or 1
end

local function SetBuildPowerMultiplier(unitID, multiplier)
	-- unit_attributes.lua owns final build/repair/reclaim speed calculation.
	-- Using its public rules-param hook means slows, stuns and other BAR
	-- attribute modifiers continue to compose correctly with this multiplier.
	spSetUnitRulesParam(unitID, "buildpower_mult", multiplier)

	if GG.UpdateUnitAttributes then
		GG.UpdateUnitAttributes(unitID)
	end
end

local function ApplyMovementMultipliers(unitID, slot)
	local moveMult =
		GetTeamNumericMultiplier(slot, "multiplier_maxvelocity")
	local turnMult =
		GetTeamNumericMultiplier(slot, "multiplier_turnrate")

	if moveMult == 1 and turnMult == 1 then
		return
	end

	-- BAR's generic attribute system composes these with slows/stuns/upgrades.
	GG.att_genericUsed = true
	GG.att_moveMult[unitID] = moveMult
	GG.att_turnMult[unitID] = turnMult

	-- Global multiplier_maxvelocity changes acceleration/deceleration less
	-- aggressively than max speed: ((x - 1) / 2 + 1).
	local accelTarget = ((moveMult - 1) / 2) + 1
	GG.att_accelMult[unitID] =
		moveMult ~= 0 and (accelTarget / moveMult) or 1

	-- Keep required generic slots populated.
	GG.att_reloadMult[unitID] = GG.att_reloadMult[unitID] or 1
	GG.att_econMult[unitID] = GG.att_econMult[unitID] or 1
	GG.att_buildMult[unitID] = GG.att_buildMult[unitID] or 1

	if GG.UpdateUnitAttributes then
		GG.UpdateUnitAttributes(unitID)
	end
end

local function ApplyWeaponMultipliers(unitID, unitDef, slot)
	local rangeMult =
		GetTeamNumericMultiplier(slot, "multiplier_weaponrange")
	local damageMult =
		GetTeamNumericMultiplier(slot, "multiplier_weapondamage")

	if rangeMult == 1 and damageMult == 1 then
		return
	end

	local maxRange = 0
	local weapons = unitDef.weapons

	if not weapons then
		return
	end

	for weaponNum = 1, #weapons do
		local weaponDefID = weapons[weaponNum].weaponDef
		local weaponDef = WeaponDefs[weaponDefID]

		if weaponDef then
			if rangeMult ~= 1 then
				local range = (weaponDef.range or 0) * rangeMult
				spSetUnitWeaponState(unitID, weaponNum, "range", range)

				-- Reproduce the important runtime parts of BAR's global
				-- range multiplier. Recoil exposes both TTL and projectile
				-- speed as per-unit weapon state.
				if weaponDef.flightTime then
					spSetUnitWeaponState(
						unitID,
						weaponNum,
						"ttl",
						weaponDef.flightTime * (rangeMult * 1.5)
					)
				end

				if
					weaponDef.type == "Cannon"
					and weaponDef.gravityAffected
					and weaponDef.projectilespeed
				then
					spSetUnitWeaponState(
						unitID,
						weaponNum,
						"projectileSpeed",
						weaponDef.projectilespeed * math.sqrt(rangeMult)
					)
				end

				if range > maxRange then
					maxRange = range
				end
			end

			if damageMult ~= 1 and weaponDef.damages then
				local damages = {}
				for armorType, value in pairs(weaponDef.damages) do
					if type(value) == "number" then
						damages[armorType] = value * damageMult
					end
				end
				spSetUnitWeaponDamages(unitID, weaponNum, damages)
			end
		end
	end

	if rangeMult ~= 1 and maxRange > 0 then
		spSetUnitMaxRange(unitID, maxRange)
	end

	-- BAR's global damage multiplier also affects unit death/self-destruct
	-- explosions. Recoil exposes the same per-unit damage override.
	if damageMult ~= 1 then
		local deathWeapon = unitDef.deathExplosion
		if deathWeapon and WeaponDefs[deathWeapon] and WeaponDefs[deathWeapon].damages then
			local damages = {}
			for armorType, value in pairs(WeaponDefs[deathWeapon].damages) do
				if type(value) == "number" then
					damages[armorType] = value * damageMult
				end
			end
			spSetUnitWeaponDamages(unitID, "explode", damages)
		end

		local selfDWeapon = unitDef.selfDExplosion
		if selfDWeapon and WeaponDefs[selfDWeapon] and WeaponDefs[selfDWeapon].damages then
			local damages = {}
			for armorType, value in pairs(WeaponDefs[selfDWeapon].damages) do
				if type(value) == "number" then
					damages[armorType] = value * damageMult
				end
			end
			spSetUnitWeaponDamages(unitID, "selfDestruct", damages)
		end
	end
end

local function ApplyNumericFeaturesToUnit(unitID, unitDefID, teamID)
	if not teamNumericFeatureActive then
		return
	end

	local slot = teamIDToTeamSlot[teamID]

	if not slot then
		return
	end

	local unitDef = UnitDefs[unitDefID]

	if not unitDef then
		return
	end

	ApplyMovementMultipliers(unitID, slot)
	ApplyWeaponMultipliers(unitID, unitDef, slot)

	local buildPowerMult =
		GetTeamNumericMultiplier(slot, "multiplier_buildpower")

	if (unitDef.buildSpeed or 0) > 0 then
		SetBuildPowerMultiplier(unitID, buildPowerMult)
	end

	local buildDistanceMult =
		GetTeamNumericMultiplier(slot, "multiplier_builddistance")

	if unitDef.buildDistance and unitDef.buildDistance > 0 then
		spSetUnitBuildParams(
			unitID,
			"buildDistance",
			unitDef.buildDistance * buildDistanceMult
		)
	end

	local resourceMult =
		GetTeamNumericMultiplier(slot, "multiplier_resourceincome")

	local metalExtractionMult =
		resourceMult
			* GetTeamNumericMultiplier(
				slot,
				"multiplier_metalextraction"
			)

	local energyProductionMult =
		resourceMult
			* GetTeamNumericMultiplier(
				slot,
				"multiplier_energyproduction"
			)

	-- Metal extractors. UnitDefs already contain any active global
	-- resource/extraction multipliers, so the value here is only the
	-- remaining team-specific factor.
	if (unitDef.extractsMetal or 0) > 0 then
		spSetUnitMetalExtraction(
			unitID,
			unitDef.extractsMetal * metalExtractionMult
		)

		if (unitDef.metalStorage or 0) > 0 then
			spSetUnitStorage(
				unitID,
				"m",
				unitDef.metalStorage * metalExtractionMult
			)
		end
	end

	-- Static unconditional production.
	if (unitDef.metalMake or 0) ~= 0 then
		spSetUnitResourcing(
			unitID,
			"umm",
			unitDef.metalMake * resourceMult
		)
	end

	if (unitDef.energyMake or 0) ~= 0 then
		spSetUnitResourcing(
			unitID,
			"ume",
			unitDef.energyMake * energyProductionMult
		)

		if (unitDef.energyStorage or 0) > 0 then
			spSetUnitStorage(
				unitID,
				"e",
				unitDef.energyStorage * energyProductionMult
			)
		end
	end

	-- BAR treats negative energy upkeep as energy production when the
	-- unit is enabled, so reproduce that definition multiplier too.
	if (unitDef.energyUpkeep or 0) < 0 then
		spSetUnitResourcing(
			unitID,
			"uue",
			unitDef.energyUpkeep * energyProductionMult
		)

		if (unitDef.energyStorage or 0) > 0 then
			spSetUnitStorage(
				unitID,
				"e",
				unitDef.energyStorage * energyProductionMult
			)
		end
	end

	local conversionMult =
		resourceMult
			* GetTeamNumericMultiplier(
				slot,
				"multiplier_energyconversion"
			)

	if
		unitDef.customParams
		and unitDef.customParams.energyconv_capacity
		and unitDef.customParams.energyconv_efficiency
	then
		if (unitDef.metalStorage or 0) > 0 then
			spSetUnitStorage(
				unitID,
				"m",
				unitDef.metalStorage * conversionMult
			)
		end

		if (unitDef.energyStorage or 0) > 0 then
			spSetUnitStorage(
				unitID,
				"e",
				unitDef.energyStorage * conversionMult
			)
		end
	end

	-- Expose the shield multiplier for the shield-specific runtime gadget.
	spSetUnitRulesParam(
		unitID,
		"team_multiplier_shieldpower",
		GetTeamNumericMultiplier(slot, "multiplier_shieldpower")
	)

	local losMult =
		GetTeamNumericMultiplier(slot, "multiplier_losrange")

	if (unitDef.losRadius or 0) > 0 then
		spSetUnitSensorRadius(
			unitID,
			"los",
			math.floor(unitDef.losRadius * losMult + 0.5)
		)
	end

	if (unitDef.airLosRadius or 0) > 0 then
		spSetUnitSensorRadius(
			unitID,
			"airLos",
			math.floor(unitDef.airLosRadius * losMult + 0.5)
		)
	end

	local radarMult =
		GetTeamNumericMultiplier(slot, "multiplier_radarrange")

	if (unitDef.radarDistance or 0) > 0 then
		spSetUnitSensorRadius(
			unitID,
			"radar",
			math.floor(unitDef.radarDistance * radarMult + 0.5)
		)
	end

	if (unitDef.sonarDistance or 0) > 0 then
		spSetUnitSensorRadius(
			unitID,
			"sonar",
			math.floor(unitDef.sonarDistance * radarMult + 0.5)
		)
	end
end

--------------------------------------------------------------------------------
-- Gadget lifecycle
--------------------------------------------------------------------------------

function gadget:Initialize()
	BuildTeamMapping()
	LoadTeamOptions()
	InitializeFeatureState()
	ResolveFeatureBuildOptions()

	GG.TeamOptions = {
		GetOptionBySlot =
			GetOptionBySlot,

		GetOptionByTeamID =
			GetOptionByTeamID,

		GetOptionByAllyTeamID =
			GetOptionByAllyTeamID,

		GetTeamSlotFromTeamID =
			GetTeamSlotFromTeamID,

		GetTeamSlotFromAllyTeamID =
			GetTeamSlotFromAllyTeamID,

		GetEffectiveNumericBySlot =
			GetTeamNumericMultiplier,

		GetEffectiveNumericByTeamID =
			function(teamID, key)
				local slot = teamIDToTeamSlot[teamID]
				if not slot then
					return 1
				end
				return GetTeamNumericMultiplier(slot, key)
			end,

		teamSlotToAllyTeam =
			teamSlotToAllyTeam,

		allyTeamToTeamSlot =
			allyTeamToTeamSlot,

		teamIDToTeamSlot =
			teamIDToTeamSlot,
	}

	Echo("Initialized")
end

--------------------------------------------------------------------------------
-- Event driven unit handling
--------------------------------------------------------------------------------

function gadget:UnitCreated(
	unitID,
	unitDefID,
	unitTeam
)
	if
		not teamScavFeatureActive
		and not teamExperimentalFeatureActive
		and not teamNumericFeatureActive
	then
		return
	end

	ApplyTeamFeaturesToUnit(
		unitID,
		unitDefID,
		unitTeam
	)

	ApplyNumericFeaturesToUnit(
		unitID,
		unitDefID,
		unitTeam
	)
end

function gadget:UnitGiven(
	unitID,
	unitDefID,
	newTeam,
	oldTeam
)
	if
		not teamScavFeatureActive
		and not teamExperimentalFeatureActive
		and not teamNumericFeatureActive
	then
		return
	end

	ApplyTeamFeaturesToUnit(
		unitID,
		unitDefID,
		newTeam
	)

	ApplyNumericFeaturesToUnit(
		unitID,
		unitDefID,
		newTeam
	)
end

function gadget:UnitTaken(
	unitID,
	unitDefID,
	oldTeam,
	newTeam
)
	if
		not teamScavFeatureActive
		and not teamExperimentalFeatureActive
		and not teamNumericFeatureActive
	then
		return
	end

	ApplyTeamFeaturesToUnit(
		unitID,
		unitDefID,
		newTeam
	)

	ApplyNumericFeaturesToUnit(
		unitID,
		unitDefID,
		newTeam
	)
end

function gadget:Shutdown()
	GG.TeamOptions = nil
end
