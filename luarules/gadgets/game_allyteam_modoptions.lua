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

local teamConfig = VFS.Include("gamedata/team_options.lua")

local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetTeamList = Spring.GetTeamList

local playableAllyTeams = {}
local teamSlotToAllyTeam = {}
local allyTeamToTeamSlot = {}
local teamIDToTeamSlot = {}

local teamOptions = teamConfig.Options

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

local function GetTeamSlotFromTeamID(teamID)
	return teamIDToTeamSlot[teamID]
end

local function GetTeamSlotFromAllyTeamID(allyTeamID)
	return allyTeamToTeamSlot[allyTeamID]
end

local function GetOptionBySlot(slot, key, fallback)
	return teamConfig.GetOption(slot, key, fallback)
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

	GG.TeamOptions = {
		GetOptionBySlot = GetOptionBySlot,
		GetOptionByTeamID = GetOptionByTeamID,
		GetOptionByAllyTeamID = GetOptionByAllyTeamID,

		GetTeamSlotFromTeamID = GetTeamSlotFromTeamID,
		GetTeamSlotFromAllyTeamID = GetTeamSlotFromAllyTeamID,

		TeamFeatureActive = teamConfig.TeamFeatureActive,
		TeamHasFeature = teamConfig.TeamHasFeature,

		teamSlotToAllyTeam = teamSlotToAllyTeam,
		allyTeamToTeamSlot = allyTeamToTeamSlot,
		teamIDToTeamSlot = teamIDToTeamSlot,
	}

	Echo("Initialized")
end

function gadget:Shutdown()
	GG.TeamOptions = nil
end
