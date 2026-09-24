local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Team Specific Starting Resources",
		desc = "Applies start resource modoptions from teamX_options",
		author = "RandomGuyJunior",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 100, -- after BAR's game_team_resources.lua
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local spGetModOptions = Spring.GetModOptions
local spGetTeamList = Spring.GetTeamList
local spGetTeamInfo = Spring.GetTeamInfo
local spGetPlayerList = Spring.GetPlayerList
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spSetTeamResource = Spring.SetTeamResource
local spGetGaiaTeamID = Spring.GetGaiaTeamID

local mathMax = math.max
local gaiaTeamID = spGetGaiaTeamID()
local minStorageMetal = 1000
local minStorageEnergy = 1000

local function IsEnabled(value)
	return value == true or value == 1 or value == "1" or value == "true" or value == "enabled"
end

local function GetTeamPlayerCounts()
	local counts = {}
	local players = spGetPlayerList()

	for i = 1, #players do
		local _, _, isSpec, teamID = spGetPlayerInfo(players[i], false)
		if not isSpec then
			counts[teamID] = (counts[teamID] or 0) + 1
		end
	end

	return counts
end

local function GetOption(teamID, key, fallback)
	if GG.TeamOptions and GG.TeamOptions.GetOptionByTeamID then
		return GG.TeamOptions.GetOptionByTeamID(teamID, key, fallback)
	end
	return fallback
end

local function Apply(addResources, skipGaia)
	local modOptions = spGetModOptions()
	local teamPlayerCounts = GG.coopMode and GetTeamPlayerCounts() or {}
	local teams = spGetTeamList()

	for i = 1, #teams do
		local teamID = teams[i]

		if not (skipGaia and teamID == gaiaTeamID) then
			local coopMultiplier = GG.coopMode and (teamPlayerCounts[teamID] or 1) or 1

			local startMetal = tonumber(GetOption(teamID, "startmetal", modOptions.startmetal)) or modOptions.startmetal
			local startEnergy = tonumber(GetOption(teamID, "startenergy", modOptions.startenergy)) or modOptions.startenergy
			local startMetalStorage =
				tonumber(GetOption(teamID, "startmetalstorage", modOptions.startmetalstorage))
				or modOptions.startmetalstorage
			local startEnergyStorage =
				tonumber(GetOption(teamID, "startenergystorage", modOptions.startenergystorage))
				or modOptions.startenergystorage

			local bonusEnabled =
				IsEnabled(GetOption(
					teamID,
					"bonusstartresourcemultiplier",
					modOptions.bonusstartresourcemultiplier
				))

			local teamBonus = 1
			if bonusEnabled then
				teamBonus = select(7, spGetTeamInfo(teamID, false)) or 1
			end

			local totalMultiplier = coopMultiplier * teamBonus
			local startingMetal = startMetal * totalMultiplier
			local startingEnergy = startEnergy * totalMultiplier
			local startingMetalStorage = startMetalStorage * totalMultiplier
			local startingEnergyStorage = startEnergyStorage * totalMultiplier

			local commanderMinMetal = 0
			local commanderMinEnergy = 0
			local startUnitDefID = spGetTeamRulesParam(teamID, "startUnit")
			local commanderDef = startUnitDefID and UnitDefs[startUnitDefID]

			if commanderDef then
				commanderMinMetal = commanderDef.metalStorage or 0
				commanderMinEnergy = commanderDef.energyStorage or 0
			end

			spSetTeamResource(
				teamID,
				"ms",
				mathMax(minStorageMetal, startingMetalStorage, startingMetal, commanderMinMetal)
			)
			spSetTeamResource(
				teamID,
				"es",
				mathMax(minStorageEnergy, startingEnergyStorage, startingEnergy, commanderMinEnergy)
			)

			if addResources then
				spSetTeamResource(teamID, "m", startingMetal)
				spSetTeamResource(teamID, "e", startingEnergy)
			end
		end
	end
end

function gadget:Initialize()
	if Spring.GetGameFrame() > 0 then
		return
	end
	Apply(true, false)
end

function gadget:GameStart()
	-- BAR resets team storage here after commander storage has been added.
	Apply(false, true)
end
