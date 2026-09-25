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
local spSetUnitMaxHealth = Spring.SetUnitMaxHealth
local spSetUnitHealth = Spring.SetUnitHealth
local spSetUnitRulesParam = Spring.SetUnitRulesParam
local spSetUnitBuildParams = Spring.SetUnitBuildParams
local spSetUnitMetalExtraction = Spring.SetUnitMetalExtraction
local spSetUnitResourcing = Spring.SetUnitResourcing
local spSetUnitStorage = Spring.SetUnitStorage
local spSetUnitSensorRadius = Spring.SetUnitSensorRadius
local spSetUnitMoveTypeData = Spring.SetUnitMoveTypeData


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

local function ParseRuntimePatch(text)
	local out = {}
	if not text or text == "" then
		return out
	end
	for line in text:gmatch("[^\r\n]+") do
		local field, oldValue, newValue = line:match("^([^\t]+)\t([^\t]*)\t(.*)$")
		if field then
			local numberValue = tonumber(newValue)
			if numberValue ~= nil then
				newValue = numberValue
			end
			out[#out + 1] = { field = field, value = newValue }
		end
	end
	return out
end

local function SplitNames(text)
	local out = {}
	if not text or text == "" then
		return out
	end
	for name in tostring(text):gmatch("%S+") do
		out[#out + 1] = string.lower(name)
	end
	return out
end

local function ResolveNameToDefID(name)
	local def = UnitDefNames[name]
	return def and def.id
end

local function ApplyRuntimePatch(unitID, unitDefID, teamID)
	local slot = teamIDToSlot[teamID]
	if not slot then
		return
	end

	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return
	end

	local cp = unitDef.customParams or {}
	local patch = cp["rg_team_runtime_patch_" .. slot]
	if not patch then
		return
	end

	for _, entry in ipairs(ParseRuntimePatch(patch)) do
		local field = entry.field
		local value = entry.value

		if field == "health" and type(value) == "number" then
			local current, oldMax = Spring.GetUnitHealth(unitID)
			local ratio = (current and oldMax and oldMax > 0) and (current / oldMax) or 1
			spSetUnitMaxHealth(unitID, value)
			spSetUnitHealth(unitID, math.max(1, value * ratio))

		elseif field == "workertime" and type(value) == "number" then
			local base = unitDef.buildSpeed or 0
			if base > 0 then
				spSetUnitRulesParam(unitID, "buildpower_mult", value / base)
				if GG.UpdateUnitAttributes then
					GG.UpdateUnitAttributes(unitID)
				end
			end

		elseif field == "builddistance" and type(value) == "number" then
			spSetUnitBuildParams(unitID, "buildDistance", value)

		elseif (field == "speed" or field == "maxvelocity") and type(value) == "number" then
			local base = unitDef.speed or 0
			if base > 0 then
				GG.att_genericUsed = true
				GG.att_moveMult[unitID] = value / base
				GG.att_turnMult[unitID] = GG.att_turnMult[unitID] or 1
				GG.att_accelMult[unitID] = GG.att_accelMult[unitID] or 1
				GG.att_reloadMult[unitID] = GG.att_reloadMult[unitID] or 1
				GG.att_econMult[unitID] = GG.att_econMult[unitID] or 1
				GG.att_buildMult[unitID] = GG.att_buildMult[unitID] or 1
				if GG.UpdateUnitAttributes then
					GG.UpdateUnitAttributes(unitID)
				end
			end

		elseif field == "turnrate" and type(value) == "number" then
			local base = unitDef.turnRate or 0
			if base > 0 then
				GG.att_genericUsed = true
				GG.att_moveMult[unitID] = GG.att_moveMult[unitID] or 1
				GG.att_turnMult[unitID] = value / base
				GG.att_accelMult[unitID] = GG.att_accelMult[unitID] or 1
				GG.att_reloadMult[unitID] = GG.att_reloadMult[unitID] or 1
				GG.att_econMult[unitID] = GG.att_econMult[unitID] or 1
				GG.att_buildMult[unitID] = GG.att_buildMult[unitID] or 1
				if GG.UpdateUnitAttributes then
					GG.UpdateUnitAttributes(unitID)
				end
			end

		elseif field == "sightdistance" and type(value) == "number" then
			spSetUnitSensorRadius(unitID, "los", math.floor(value + 0.5))
		elseif field == "airsightdistance" and type(value) == "number" then
			spSetUnitSensorRadius(unitID, "airLos", math.floor(value + 0.5))
		elseif field == "radardistance" and type(value) == "number" then
			spSetUnitSensorRadius(unitID, "radar", math.floor(value + 0.5))
		elseif field == "sonardistance" and type(value) == "number" then
			spSetUnitSensorRadius(unitID, "sonar", math.floor(value + 0.5))

		elseif field == "extractsmetal" and type(value) == "number" then
			spSetUnitMetalExtraction(unitID, value)

		elseif field == "energymake" and type(value) == "number" then
			spSetUnitResourcing(unitID, "ume", value)

		elseif field == "metalmake" and type(value) == "number" then
			spSetUnitResourcing(unitID, "umm", value)

		elseif field == "energyupkeep" and type(value) == "number" then
			spSetUnitResourcing(unitID, "uue", value)

		elseif field == "energystorage" and type(value) == "number" then
			spSetUnitStorage(unitID, "e", value)

		elseif field == "metalstorage" and type(value) == "number" then
			spSetUnitStorage(unitID, "m", value)
		end
	end
end

local function ApplyBuildOptionPatch(unitID, unitDefID, teamID)
	local slot = teamIDToSlot[teamID]
	if not slot or not GG.DynamicBuildOptions then
		return
	end

	local unitDef = UnitDefs[unitDefID]
	if not unitDef or not unitDef.isBuilder then
		return
	end

	local cp = unitDef.customParams or {}
	local removeNames = SplitNames(cp["rg_team_build_remove_" .. slot])
	for i = 1, #removeNames do
		local defID = ResolveNameToDefID(removeNames[i])
		if defID then
			GG.DynamicBuildOptions.RemoveFromUnit(unitID, defID)
		end
	end

	local addNames = SplitNames(cp["rg_team_build_add_" .. slot])
	for i = 1, #addNames do
		local defID = ResolveNameToDefID(addNames[i])
		if defID then
			defID = ResolveUnitDefID(teamID, defID)
			GG.DynamicBuildOptions.AddToUnit(unitID, defID)
		end
	end
end

local function ApplyBuildRemaps(unitID, unitDefID, teamID)
	ApplyRuntimePatch(unitID, unitDefID, teamID)
	ApplyBuildOptionPatch(unitID, unitDefID, teamID)

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
