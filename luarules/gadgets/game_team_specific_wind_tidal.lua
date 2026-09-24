local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Team Specific Wind/Tidal Multipliers",
		desc = "Applies teamX resource and energy-production multipliers to wind and tidal generators",
		author = "RandomGuyJunior",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 1,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local spAddUnitResource = Spring.AddUnitResource
local spGetUnitIsStunned = Spring.GetUnitIsStunned
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID
local spGetAllUnits = Spring.GetAllUnits

local tracked = {}

local function GetTeamEnergyFactor(teamID)
	if GG.TeamOptions and GG.TeamOptions.GetEffectiveNumericByTeamID then
		return
			GG.TeamOptions.GetEffectiveNumericByTeamID(teamID, "multiplier_resourceincome")
			* GG.TeamOptions.GetEffectiveNumericByTeamID(teamID, "multiplier_energyproduction")
	end
	return 1
end

local function SetupUnit(unitID, unitDefID, teamID)
	local ud = UnitDefs[unitDefID]
	if not ud then
		tracked[unitID] = nil
		return
	end

	local isWind = (ud.windGenerator or 0) > 0
	local isTidal = (ud.tidalGenerator or 0) > 0

	if not isWind and not isTidal then
		tracked[unitID] = nil
		return
	end

	local teamFactor = GetTeamEnergyFactor(teamID)
	if teamFactor == 1 then
		tracked[unitID] = nil
		return
	end

	tracked[unitID] = {
		isWind = isWind,
		isTidal = isTidal,
		teamFactor = teamFactor,
		baseWindMult = tonumber(ud.customParams and ud.customParams.energymultiplier) or 1,
		tidalScale = ud.tidalGenerator or 0,
	}
end

function gadget:Initialize()
	local units = spGetAllUnits()
	for i = 1, #units do
		local unitID = units[i]
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if unitDefID and teamID then
			SetupUnit(unitID, unitDefID, teamID)
		end
	end
end

function gadget:UnitFinished(unitID, unitDefID, unitTeam)
	SetupUnit(unitID, unitDefID, unitTeam)
end

function gadget:UnitGiven(unitID, unitDefID, newTeam)
	SetupUnit(unitID, unitDefID, newTeam)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
	SetupUnit(unitID, unitDefID, newTeam)
end

function gadget:UnitDestroyed(unitID)
	tracked[unitID] = nil
end

function gadget:GameFrame(frame)
	if (frame + 15) % 30 ~= 0 then
		return
	end

	if not next(tracked) then
		return
	end

	local _, _, _, windStrength = Spring.GetWind()
	local tidalStrength = Spring.GetTidal and Spring.GetTidal() or Game.tidal or 0

	for unitID, data in pairs(tracked) do
		if not spGetUnitIsStunned(unitID) then
			local extra = 0

			if data.isWind then
				-- BAR's wind gadget already accounts for baseWindMult.
				-- Add only the extra team-specific factor on top.
				extra = extra
					+ windStrength
						* data.baseWindMult
						* (data.teamFactor - 1)
			end

			if data.isTidal then
				extra = extra
					+ tidalStrength
						* data.tidalScale
						* (data.teamFactor - 1)
			end

			if extra ~= 0 then
				spAddUnitResource(unitID, "e", extra)
			end
		end
	end
end
