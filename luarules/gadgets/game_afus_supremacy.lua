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
for slot = 1, 8 do
	teamEnabled[slot] = teamOptions.IsOptionEnabled(slot, "afus_supremacy")
end
local anyTeamEnabled = false
for slot = 1, 8 do
	if teamEnabled[slot] then
		anyTeamEnabled = true
		break
	end
end
if not globalEnabled and not anyTeamEnabled then
	return false
end

local CMD_AFUS_LAUNCH = 39958
local LAUNCH_RANGE = 10000
local LAUNCH_RANGE_SQ = LAUNCH_RANGE * LAUNCH_RANGE
local INTERCEPT_COVERAGE = 3500
local INTERCEPT_COVERAGE_SQ = INTERCEPT_COVERAGE * INTERCEPT_COVERAGE

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitIsDead = Spring.GetUnitIsDead
local spGetProjectilePosition = Spring.GetProjectilePosition
local spGetProjectileTeamID = Spring.GetProjectileTeamID
local spGetGroundHeight = Spring.GetGroundHeight
local spSpawnProjectile = Spring.SpawnProjectile
local spSetProjectileTarget = Spring.SetProjectileTarget
local spDestroyUnit = Spring.DestroyUnit
local spValidUnitID = Spring.ValidUnitID
local spAreTeamsAllied = Spring.AreTeamsAllied
local spInsertUnitCmdDesc = Spring.InsertUnitCmdDesc
local spFindUnitCmdDesc = Spring.FindUnitCmdDesc

local projectileTargetType = string.byte("p")

local afusUnitDefs = {}
local payloadWeaponByUnitDef = {}
local payloadWeaponDefs = {}

local pendingConsume = {}
local payloads = {}
local assignedTarget = {}
local interceptorTarget = {}
local currentFrame = 0
local spawnKind
local spawnTargetProjectile

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

local launchCommand = {
	id = CMD_AFUS_LAUNCH,
	type = CMDTYPE.ICON_MAP,
	name = "Launch AFUS",
	action = "afuslaunch",
	cursor = "cursorattack",
	tooltip = "Launch this AFUS itself at a ground target within 10,000 range. The AFUS is consumed after launch.",
}

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
	local weaponDefID = unitDefID and payloadWeaponByUnitDef[unitDefID]
	if not weaponDefID then
		return false
	end

	local params = buildProjectileParams(unitID, x, y, z)
	if not params then
		return false
	end

	spawnKind = "attack"
	spawnTargetProjectile = nil
	local projectileID = spSpawnProjectile(weaponDefID, params)
	spawnKind = nil

	if not projectileID then
		return false
	end

	spSetProjectileTarget(projectileID, x, y, z)
	payloads[projectileID] = {
		kind = "attack",
		teamID = params.team,
		targetX = x,
		targetY = y,
		targetZ = z,
	}

	queueConsume(unitID)
	return true
end

local function spawnInterceptor(unitID, targetProjectileID)
	local tx, ty, tz = spGetProjectilePosition(targetProjectileID)
	if not tx then
		return false
	end

	local unitDefID = spGetUnitDefID(unitID)
	local weaponDefID = unitDefID and payloadWeaponByUnitDef[unitDefID]
	if not weaponDefID then
		return false
	end

	local params = buildProjectileParams(unitID, tx, ty, tz)
	if not params then
		return false
	end

	spawnKind = "interceptor"
	spawnTargetProjectile = targetProjectileID
	local projectileID = spSpawnProjectile(weaponDefID, params)
	spawnKind = nil
	spawnTargetProjectile = nil

	if not projectileID then
		return false
	end

	spSetProjectileTarget(projectileID, targetProjectileID, projectileTargetType)

	payloads[projectileID] = {
		kind = "interceptor",
		teamID = params.team,
		targetProjectileID = targetProjectileID,
	}
	assignedTarget[targetProjectileID] = projectileID
	interceptorTarget[projectileID] = targetProjectileID

	queueConsume(unitID)
	return true
end

local function findInterceptorFor(payloadID, payload)
	local px, _, pz = spGetProjectilePosition(payloadID)
	if not px then
		return nil
	end

	local bestUnitID
	local bestDistSq

	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if isLiveAFUS(unitID) and not pendingConsume[unitID] then
			local teamID = spGetUnitTeam(unitID)
			if teamID and payload.teamID and not spAreTeamsAllied(teamID, payload.teamID) then
				local ux, _, uz = spGetUnitPosition(unitID)
				if ux then
					local dx = ux - px
					local dz = uz - pz
					local distSq = dx * dx + dz * dz
					if distSq <= INTERCEPT_COVERAGE_SQ and (not bestDistSq or distSq < bestDistSq) then
						bestDistSq = distSq
						bestUnitID = unitID
					end
				end
			end
		end
	end

	return bestUnitID
end

local function tryAssignInterceptor(payloadID, payload)
	if payload.kind ~= "attack" or assignedTarget[payloadID] then
		return
	end

	if not spGetProjectilePosition(payloadID) then
		return
	end

	local unitID = findInterceptorFor(payloadID, payload)
	if unitID then
		spawnInterceptor(unitID, payloadID)
	end
end

local function addLaunchCommand(unitID, unitDefID)
	if not afusUnitDefs[unitDefID] or not teamHasMode(spGetUnitTeam(unitID)) then
		return
	end
	if not spFindUnitCmdDesc(unitID, CMD_AFUS_LAUNCH) then
		spInsertUnitCmdDesc(unitID, launchCommand)
	end
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams)
	if cmdID ~= CMD_AFUS_LAUNCH then
		return true
	end
	if not afusUnitDefs[unitDefID] or not teamHasMode(teamID) or #cmdParams < 3 or pendingConsume[unitID] then
		return false
	end

	local ux, _, uz = spGetUnitPosition(unitID)
	if not ux then
		return false
	end

	local x, z = tonumber(cmdParams[1]), tonumber(cmdParams[3])
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
	if not payloadWeaponDefs[weaponDefID] then
		return
	end

	local teamID = Spring.GetProjectileTeamID(projectileID) or (ownerID and spGetUnitTeam(ownerID))
	if spawnKind == "interceptor" then
		payloads[projectileID] = {
			kind = "interceptor",
			teamID = teamID,
			targetProjectileID = spawnTargetProjectile,
		}
	elseif spawnKind == "attack" then
		-- spawnGroundPayload fills exact target coordinates immediately after SpawnProjectile returns.
	else
		-- Defensive fallback for a projectile somehow created through the hidden template weapon.
		local targetType, target = Spring.GetProjectileTarget(projectileID)
		if type(target) == "table" then
			payloads[projectileID] = {
				kind = "attack",
				teamID = teamID,
				targetX = target[1],
				targetY = target[2],
				targetZ = target[3],
			}
		end
	end
end

function gadget:ProjectileDestroyed(projectileID)
	payloads[projectileID] = nil

	local targetID = interceptorTarget[projectileID]
	if targetID then
		if assignedTarget[targetID] == projectileID then
			assignedTarget[targetID] = nil
		end
		interceptorTarget[projectileID] = nil
	end

	local interceptorID = assignedTarget[projectileID]
	if interceptorID then
		interceptorTarget[interceptorID] = nil
		assignedTarget[projectileID] = nil
	end
end

function gadget:UnitCreated(unitID, unitDefID)
	addLaunchCommand(unitID, unitDefID)
end

function gadget:UnitGiven(unitID, unitDefID)
	local idx = spFindUnitCmdDesc(unitID, CMD_AFUS_LAUNCH)
	if afusUnitDefs[unitDefID] and teamHasMode(spGetUnitTeam(unitID)) then
		if not idx then
			spInsertUnitCmdDesc(unitID, launchCommand)
		end
	elseif idx then
		Spring.RemoveUnitCmdDesc(unitID, idx)
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

	if frame % 15 == 0 then
		for projectileID, payload in pairs(payloads) do
			if payload.kind == "attack" then
				if spGetProjectilePosition(projectileID) then
					tryAssignInterceptor(projectileID, payload)
				else
					payloads[projectileID] = nil
					assignedTarget[projectileID] = nil
				end
			end
		end
	end
end

function gadget:Initialize()
	gadgetHandler:RegisterCMDID(CMD_AFUS_LAUNCH)
	gadgetHandler:RegisterAllowCommand(CMD_AFUS_LAUNCH)

	local payloadBySourceName = {}
	for weaponDefID, weaponDef in pairs(WeaponDefs) do
		local cp = weaponDef.customParams
		if cp and cp.afus_supremacy and cp.afus_source_unit then
			payloadBySourceName[string.lower(cp.afus_source_unit)] = weaponDefID
			payloadWeaponDefs[weaponDefID] = true
			Script.SetWatchProjectile(weaponDefID, true)
		end
	end

	for unitDefID, unitDef in pairs(UnitDefs) do
		local cp = unitDef.customParams
		if cp and cp.afus_supremacy then
			afusUnitDefs[unitDefID] = true
			local sourceName = string.lower(cp.rg_team_tweak_source or unitDef.name)
			payloadWeaponByUnitDef[unitDefID] = payloadBySourceName[sourceName]
		end
	end

	for _, unitID in ipairs(Spring.GetAllUnits()) do
		addLaunchCommand(unitID, spGetUnitDefID(unitID))
	end
end
