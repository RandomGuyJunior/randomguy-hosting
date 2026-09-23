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

local spGetModOptions = Spring.GetModOptions
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetTeamList = Spring.GetTeamList

local playableAllyTeams = {}
local teamSlotToAllyTeam = {}
local allyTeamToTeamSlot = {}
local teamIDToTeamSlot = {}

local teamOptions = {}

local function Echo(...)
	Spring.Echo("[Team Options]", ...)
end

local function BuildTeamMapping()
	local gaiaTeamID = spGetGaiaTeamID()
	local gaiaAllyTeamID = select(6, spGetTeamInfo(gaiaTeamID, false))

	local allyTeams = spGetAllyTeamList()

	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]

		if allyTeamID ~= gaiaAllyTeamID then
			playableAllyTeams[#playableAllyTeams + 1] = allyTeamID
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
		local key, value = string.match(line, "^%s*([^=]+)%s*=%s*(.-)%s*$")

		if key and value and key ~= "" then
			result[key] = ParseValue(value)
		else
			Echo("Ignoring invalid option:", line)
		end
	end

	return result
end

local function LoadTeamOptions()
	local modOptions = spGetModOptions()

	for slot = 1, 8 do
		local key = "team" .. slot .. "_options"
		local value = modOptions[key]

		if value and value ~= "" then
			teamOptions[slot] = ParseOptionString(value)

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

local function GetTeamSlotFromTeamID(teamID)
	return teamIDToTeamSlot[teamID]
end

local function GetTeamSlotFromAllyTeamID(allyTeamID)
	return allyTeamToTeamSlot[allyTeamID]
end

local function GetOptionBySlot(slot, key, fallback)
	local options = teamOptions[slot]

	if options then
		local value = options[key]

		if value ~= nil then
			return value
		end
	end

	return fallback
end

local function GetOptionByTeamID(teamID, key, fallback)
	local slot = teamIDToTeamSlot[teamID]

	if not slot then
		return fallback
	end

	return GetOptionBySlot(slot, key, fallback)
end

local function GetOptionByAllyTeamID(allyTeamID, key, fallback)
	local slot = allyTeamToTeamSlot[allyTeamID]

	if not slot then
		return fallback
	end

	return GetOptionBySlot(slot, key, fallback)
end

function gadget:Initialize()
	BuildTeamMapping()
	LoadTeamOptions()

	GG.TeamOptions = {
		GetOptionBySlot = GetOptionBySlot,
		GetOptionByTeamID = GetOptionByTeamID,
		GetOptionByAllyTeamID = GetOptionByAllyTeamID,

		GetTeamSlotFromTeamID = GetTeamSlotFromTeamID,
		GetTeamSlotFromAllyTeamID = GetTeamSlotFromAllyTeamID,

		teamSlotToAllyTeam = teamSlotToAllyTeam,
		allyTeamToTeamSlot = allyTeamToTeamSlot,
		teamIDToTeamSlot = teamIDToTeamSlot,
	}

	Echo("Initialized")
end

function gadget:Shutdown()
	GG.TeamOptions = nil
end