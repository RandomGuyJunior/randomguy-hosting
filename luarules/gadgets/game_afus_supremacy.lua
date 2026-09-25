local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AFUS Supremacy",
		desc = "Turns AFUS into disposable long-range launchers and AFUS-only interceptors",
		author = "RandomGuyJunior",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 2,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local modOptions = Spring.GetModOptions()
local teamOptions = VFS.Include("gamedata/team_options.lua")
local globalEnabled = modOptions.afus_supremacy == true or modOptions.afus_supremacy == "1"

local teamEnabled = {}
local anyTeamEnabled = false
for slot = 1, 8 do
	teamEnabled[slot] = teamOptions.IsOptionEnabled(slot, "afus_supremacy")
	if teamEnabled[slot] then
		anyTeamEnabled = true
	end
end

if not globalEnabled and not anyTeamEnabled then
	return false
end

local LAUNCH_RANGE = 10000
local LAUNCH_RANGE_SQ = LAUNCH_RANGE * LAUNCH_RANGE
local INTERCEPT_RANGE = 3500
local INTERCEPT_RANGE_SQ = INTERCEPT_RANGE * INTERCEPT_RANGE
local PROJECTILE_TARGET = string.byte("p")

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitIsDead = Spring.GetUnitIsDead
local spGetGroundHeight = Spring.GetGroundHeight
local spGetProjectilePosition = Spring.GetProjectilePosition
local spGetProjectileTeamID = Spring.GetProjectileTeamID
local spSpawnProjectile = Spring.SpawnProjectile
local spSetProjectileTarget = Spring.SetProjectileTarget
local spDestroyUnit = Spring.DestroyUnit
local spValidUnitID = Spring.ValidUnitID
local spAreTeamsAllied = Spring.AreTeamsAllied

local afusUnitDefs = {}
local launcherBySource = {}
local interceptorBySource = {}
local roleByWeaponDef = {}

local trackedLaunchers = {}
local assignedInterceptor = {}
local interceptorTarget = {}
local pendingConsume = {}
local currentFrame = 0

local function teamHasMode(teamID)
	if globalEnabled then
		return true
	end
	if not GG.TeamOptions or not GG.TeamOptions.GetTeamSlotFromTeamID then
		return false
	end
	local slot = GG.TeamOptions.GetTeamSlotFromTeamID(teamID)
	return slot and teamEnabled[slot] == true or false
end

local function getSourceForUnitDef(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return nil
	end
	local cp = unitDef.customParams or {}
	return cp.afus_supremacy_source or cp.rg_team_tweak_source or string.lower(unitDef.name or "")
end

local function isLiveAFUS(unitID)
	if not unitID or not spValidUnitID(unitID) or spGetUnitIsDead(unitID) then
		return false
	end
	local unitDefID = spGetUnitDefID(unitID)
	local teamID = spGetUnitTeam(unitID)
	return unitDefID and afusUnitDefs[unitDefID] == true and teamHasMode(teamID)
end

local function queueConsume(unitID)
	pendingConsume[unitID] = currentFrame + 1
end

local function buildProjectileParams(unitID, x, y, z)
	local ux, uy, uz = spGetUnitPosition(unitID)
	if not ux then
		return nil
	end

	return {
		pos = { ux, uy + 30, uz },
		speed = { 0, 20, 0 },
		["end"] = { x, y, z },
		owner = unitID,
		team = spGetUnitTeam(unitID),
		ttl = Game.gameSpeed * 40,
	}
end

local function spawnGroundPayload(unitID, x, y, z)
	local unitDefID = spGetUnitDefID(unitID)
	local source = unitDefID and getSourceForUnitDef(unitDefID)
	local weaponDefID = source and launcherBySource[string.lower(source)]
	if not weaponDefID then
		return false
	end

	local params = buildProjectileParams(unitID, x, y, z)
	if not params then
		return false
	end

	local projectileID = spSpawnProjectile(weaponDefID, params)
	if not projectileID then
		return false
	end

	spSetProjectileTarget(projectileID, x, y, z)
	return true
end

local function spawnInterceptor(unitID, targetProjectileID)
	local tx, ty, tz = spGetProjectilePosition(targetProjectileID)
	if not tx then
		return false
	end

	local unitDefID = spGetUnitDefID(unitID)
	local source = unitDefID and getSourceForUnitDef(unitDefID)
	local weaponDefID = source and interceptorBySource[string.lower(source)]
	if not weaponDefID then
		return false
	end

	local params = buildProjectileParams(unitID, tx, ty, tz)
	if not params then
		return false
	end

	local projectileID = spSpawnProjectile(weaponDefID, params)
	if not projectileID then
		return false
	end

	spSetProjectileTarget(projectileID, targetProjectileID, PROJECTILE_TARGET)
	assignedInterceptor[targetProjectileID] = projectileID
	interceptorTarget[projectileID] = targetProjectileID
	return true
end

local function findInterceptor(targetProjectileID, targetTeamID)
	local px, _, pz = spGetProjectilePosition(targetProjectileID)
	if not px then
		return nil
	end

	local bestUnitID
	local bestDistSq

	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if isLiveAFUS(unitID) and not pendingConsume[unitID] then
			local teamID = spGetUnitTeam(unitID)
			if teamID and targetTeamID and not spAreTeamsAllied(teamID, targetTeamID) then
				local ux, _, uz = spGetUnitPosition(unitID)
				if ux then
					local dx = ux - px
					local dz = uz - pz
					local distSq = dx * dx + dz * dz
					if distSq <= INTERCEPT_RANGE_SQ and (not bestDistSq or distSq < bestDistSq) then
						bestDistSq = distSq
						bestUnitID = unitID
					end
				end
			end
		end
	end

	return bestUnitID
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams)
	if cmdID ~= CMD.MANUALFIRE then
		return true
	end
	if not afusUnitDefs[unitDefID] then
		return true
	end
	if not teamHasMode(teamID) or #cmdParams < 3 or pendingConsume[unitID] then
		return false
	end

	local ux, _, uz = spGetUnitPosition(unitID)
	if not ux then
		return false
	end

	local x = tonumber(cmdParams[1])
	local z = tonumber(cmdParams[3])
	if not x or not z then
		return false
	end
	local y = tonumber(cmdParams[2]) or spGetGroundHeight(x, z)

	local dx = x - ux
	local dz = z - uz
	if dx * dx + dz * dz > LAUNCH_RANGE_SQ then
		return false
	end

	spawnGroundPayload(unitID, x, y, z)
	return false
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	local role = roleByWeaponDef[weaponDefID]
	if not role then
		return
	end

	if ownerID and isLiveAFUS(ownerID) then
		queueConsume(ownerID)
	end

	if role == "launcher" then
		trackedLaunchers[projectileID] = spGetProjectileTeamID(projectileID) or (ownerID and spGetUnitTeam(ownerID))
	end
end

function gadget:ProjectileDestroyed(projectileID)
	trackedLaunchers[projectileID] = nil

	local targetID = interceptorTarget[projectileID]
	if targetID then
		if assignedInterceptor[targetID] == projectileID then
			assignedInterceptor[targetID] = nil
		end
		interceptorTarget[projectileID] = nil
	end

	local interceptorID = assignedInterceptor[projectileID]
	if interceptorID then
		interceptorTarget[interceptorID] = nil
		assignedInterceptor[projectileID] = nil
	end
end

function gadget:UnitDestroyed(unitID)
	pendingConsume[unitID] = nil
end

function gadget:GameFrame(frame)
	currentFrame = frame

	for unitID, consumeFrame in pairs(pendingConsume) do
		if frame >= consumeFrame then
			pendingConsume[unitID] = nil
			if isLiveAFUS(unitID) then
				spDestroyUnit(unitID, false, true)
			end
		end
	end

	for projectileID, targetTeamID in pairs(trackedLaunchers) do
		if not spGetProjectilePosition(projectileID) then
			trackedLaunchers[projectileID] = nil
			assignedInterceptor[projectileID] = nil
		elseif not assignedInterceptor[projectileID] then
			local unitID = findInterceptor(projectileID, targetTeamID)
			if unitID then
				spawnInterceptor(unitID, projectileID)
			end
		end
	end
end

function gadget:Initialize()
	gadgetHandler:RegisterAllowCommand(CMD.MANUALFIRE)

	for weaponDefID, weaponDef in pairs(WeaponDefs) do
		local cp = weaponDef.customParams
		if cp and cp.afus_supremacy and cp.afus_source_unit and cp.afus_supremacy_role then
			local source = string.lower(cp.afus_source_unit)
			roleByWeaponDef[weaponDefID] = cp.afus_supremacy_role
			if cp.afus_supremacy_role == "launcher" then
				launcherBySource[source] = weaponDefID
			elseif cp.afus_supremacy_role == "interceptor" then
				interceptorBySource[source] = weaponDefID
			end
			Script.SetWatchProjectile(weaponDefID, true)
		end
	end

	for unitDefID, unitDef in pairs(UnitDefs) do
		local cp = unitDef.customParams
		if cp and cp.afus_supremacy then
			afusUnitDefs[unitDefID] = true
		end
	end
end
