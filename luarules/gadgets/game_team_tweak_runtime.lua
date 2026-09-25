local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Team Tweak Runtime",
		desc = "Routes team-specific cloned UnitDefs and build options",
		author = "RandomGuyJunior",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = -900,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetTeamList = Spring.GetTeamList
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID

local teamIDToSlot = {}
local sourceToCloneBySlot = {}
local cloneToSourceBySlot = {}

local function Echo(...)
	Spring.Echo("[Team Tweaks]", ...)
end

local function BuildTeamMapping()
	local gaiaTeamID = spGetGaiaTeamID()
	local gaiaAllyTeamID = select(6, spGetTeamInfo(gaiaTeamID, false))
	local allyTeams = spGetAllyTeamList()
	local playable = {}

	for i = 1, #allyTeams do
		if allyTeams[i] ~= gaiaAllyTeamID then
			playable[#playable + 1] = allyTeams[i]
		end
	end

	table.sort(playable)

	for slot = 1, math.min(#playable, 8) do
		local teams = spGetTeamList(playable[slot])
		for i = 1, #teams do
			local teamID = teams[i]
			if teamID ~= gaiaTeamID then
				teamIDToSlot[teamID] = slot
			end
		end
	end
end

local function BuildCloneMaps()
	for slot = 1, 8 do
		sourceToCloneBySlot[slot] = {}
		cloneToSourceBySlot[slot] = {}
	end

	for unitDefID, unitDef in pairs(UnitDefs) do
		local cp = unitDef.customParams
		local slot = cp and tonumber(cp.rg_team_tweak_slot)
		local source = cp and cp.rg_team_tweak_source

		if slot and source and sourceToCloneBySlot[slot] then
			local sourceDef = UnitDefNames[source]
			if sourceDef then
				sourceToCloneBySlot[slot][sourceDef.id] = unitDefID
				cloneToSourceBySlot[slot][unitDefID] = sourceDef.id
			else
				-- Newly-created tweak units have no source UnitDef. They are still
				-- reachable through rewritten buildoptions/evolution/spawner refs.
				Echo("Team", slot, "new UnitDef", unitDef.name or unitDefID)
			end
		end
	end
end

local function ResolveUnitDefID(teamID, unitDefID)
	local slot = teamIDToSlot[teamID]
	if not slot then
		return unitDefID
	end

	return sourceToCloneBySlot[slot][unitDefID] or unitDefID
end

local function ResolveUnitName(teamID, unitName)
	local def = UnitDefNames[unitName]
	if not def then
		return unitName
	end

	local resolved = ResolveUnitDefID(teamID, def.id)
	local resolvedDef = UnitDefs[resolved]
	return resolvedDef and resolvedDef.name or unitName
end

local function ApplyBuildRemaps(unitID, unitDefID, teamID)
	local slot = teamIDToSlot[teamID]
	if not slot then
		return
	end

	local api = GG.DynamicBuildOptions
	if not api then
		return
	end

	local unitDef = UnitDefs[unitDefID]
	if not unitDef or not unitDef.isBuilder then
		return
	end

	local replacements = sourceToCloneBySlot[slot]
	for sourceDefID, cloneDefID in pairs(replacements) do
		if api.HasUnitBuildOption(unitID, sourceDefID) then
			api.RemoveFromUnit(unitID, sourceDefID)
			api.AddToUnit(unitID, cloneDefID)
		end
	end
end

function gadget:Initialize()
	BuildTeamMapping()
	BuildCloneMaps()

	GG.TeamTweaks = {
		ResolveUnitDefID = ResolveUnitDefID,
		ResolveUnitName = ResolveUnitName,
		GetTeamSlot = function(teamID)
			return teamIDToSlot[teamID]
		end,
		sourceToCloneBySlot = sourceToCloneBySlot,
		cloneToSourceBySlot = cloneToSourceBySlot,
	}

	for _, teamID in ipairs(spGetTeamList()) do
		for _, unitID in ipairs(Spring.GetTeamUnits(teamID)) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID then
				ApplyBuildRemaps(unitID, unitDefID, teamID)
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, unitTeam)
	ApplyBuildRemaps(unitID, unitDefID, unitTeam)
end

function gadget:UnitGiven(unitID, unitDefID, newTeam)
	ApplyBuildRemaps(unitID, unitDefID, newTeam)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
	ApplyBuildRemaps(unitID, unitDefID, newTeam)
end

function gadget:Shutdown()
	GG.TeamTweaks = nil
end
