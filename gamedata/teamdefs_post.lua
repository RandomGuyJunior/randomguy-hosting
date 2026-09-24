local system = VFS.Include("gamedata/system.lua")

local section = "teamdefs_post.lua"
local modOptions = Spring.GetModOptions()

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Echo(...)
	Spring.Echo("[Team UnitDefs]", ...)
end

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

local function IsEnabled(value)
	return value == true
		or value == 1
		or value == "1"
		or value == "true"
		or value == "enabled"
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
		end
	end

	return result
end

--------------------------------------------------------------------------------
-- Parse team-specific options once
--------------------------------------------------------------------------------

local teamOptions = {}

for slot = 1, 8 do
	local value =
		modOptions["team" .. slot .. "_options"]

	teamOptions[slot] =
		ParseOptionString(value)
end

local function AnyTeamEnabled(key)
	for slot = 1, 8 do
		local value =
			teamOptions[slot][key]

		if IsEnabled(value) then
			return true
		end
	end

	return false
end

--------------------------------------------------------------------------------
-- Determine which team-specific features need definition support
--
-- Each option is independent.
--
-- If BAR's global option is already enabled, we do absolutely nothing for
-- that specific team feature.
--------------------------------------------------------------------------------

local teamScavNeeded =
	not IsEnabled(modOptions.scavunitsforplayers)
	and AnyTeamEnabled("scavunitsforplayers")

local teamExperimentalNeeded =
	not IsEnabled(modOptions.experimentalextraunits)
	and AnyTeamEnabled("experimentalextraunits")

local teamForceAllNeeded =
	not IsEnabled(modOptions.forceallunits)
	and AnyTeamEnabled("forceallunits")

--------------------------------------------------------------------------------
-- Nothing relevant requested
--------------------------------------------------------------------------------

if
	not teamScavNeeded
	and not teamExperimentalNeeded
	and not teamForceAllNeeded
then
	return
end

--------------------------------------------------------------------------------
-- Required unit families
--
-- BAR's existing unitdefs.lua behavior:
--
-- scavunitsforplayers:
--     scavengers + legion
--
-- experimentalextraunits:
--     scavengers + legion
--
-- forceallunits:
--     scavengers + legion + raptors
--------------------------------------------------------------------------------

local requireScavengers =
	teamScavNeeded
	or teamExperimentalNeeded
	or teamForceAllNeeded

local requireLegion =
	teamScavNeeded
	or teamExperimentalNeeded
	or teamForceAllNeeded

local requireRaptors =
	teamForceAllNeeded

Echo(
	"Requirements:",
	"scavengers=" .. tostring(requireScavengers),
	"legion=" .. tostring(requireLegion),
	"raptors=" .. tostring(requireRaptors)
)

--------------------------------------------------------------------------------
-- Load one raw UnitDef file using BAR's normal UnitDef environment
--------------------------------------------------------------------------------

local function LoadUnitFile(filename)
	local unitDefsEnv = {}

	unitDefsEnv._G = unitDefsEnv
	unitDefsEnv.Shared = Shared
	unitDefsEnv.BAR = BAR

	unitDefsEnv.GetFilename = function()
		return filename
	end

	setmetatable(
		unitDefsEnv,
		{
			__index = system,
		}
	)

	local success, defs =
		pcall(
			VFS.Include,
			filename,
			unitDefsEnv,
			VFS_MODES
		)

	if not success then
		Spring.Log(
			section,
			LOG.ERROR,
			"Error parsing "
				.. filename
				.. ": "
				.. tostring(defs)
		)

		return
	end

	if type(defs) ~= "table" then
		Spring.Log(
			section,
			LOG.ERROR,
			"Bad return table from: "
				.. filename
		)

		return
	end

	for unitDefName, unitDef in pairs(defs) do
		if
			type(unitDefName) == "string"
			and type(unitDef) == "table"
		then
			--
			-- Do not overwrite something BAR already loaded.
			--
			if UnitDefs[unitDefName] == nil then
				UnitDefs[unitDefName] = unitDef
			end
		else
			Spring.Log(
				section,
				LOG.ERROR,
				"Bad return table entry from: "
					.. filename
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Load only required families
--------------------------------------------------------------------------------

local luaFiles =
	VFS.DirList(
		"units/",
		"*.lua",
		nil,
		true
	)

local loadedFiles = 0

for _, filename in ipairs(luaFiles) do
	local shouldLoad = false

	if
		requireLegion
		and filename:find("legion")
	then
		shouldLoad = true
	end

	if
		requireScavengers
		and filename:find("scavengers")
	then
		shouldLoad = true
	end

	if
		requireRaptors
		and filename:find("raptors")
	then
		shouldLoad = true
	end

	if shouldLoad then
		LoadUnitFile(filename)
		loadedFiles = loadedFiles + 1
	end
end

Echo(
	"Finished team-specific raw UnitDef loading; scanned/load-called",
	loadedFiles,
	"files"
)
