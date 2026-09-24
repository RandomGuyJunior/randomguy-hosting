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
	then
		return
	end

	ApplyTeamFeaturesToUnit(
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
	then
		return
	end

	ApplyTeamFeaturesToUnit(
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
	then
		return
	end

	ApplyTeamFeaturesToUnit(
		unitID,
		unitDefID,
		newTeam
	)
end

function gadget:Shutdown()
	GG.TeamOptions = nil
end
