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

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitIsDead = Spring.GetUnitIsDead
local spGetGroundHeight = Spring.GetGroundHeight
local spSpawnProjectile = Spring.SpawnProjectile
local spSetProjectileTarget = Spring.SetProjectileTarget
local spDestroyUnit = Spring.DestroyUnit
local spValidUnitID = Spring.ValidUnitID
local spInsertUnitCmdDesc = Spring.InsertUnitCmdDesc
local spFindUnitCmdDesc = Spring.FindUnitCmdDesc

local afusUnitDefs = {}
local payloadWeaponByUnitDef = {}
local payloadWeaponDefs = {}

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

	local projectileID = spSpawnProjectile(weaponDefID, params)
	if not projectileID then
		return false
	end

	spSetProjectileTarget(projectileID, x, y, z)
	return true
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
	if ownerID and isLiveAFUS(ownerID) then
		queueConsume(ownerID)
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

end

function gadget:Initialize()
	gadgetHandler:RegisterCMDID(CMD_AFUS_LAUNCH)
	gadgetHandler:RegisterAllowCommand(CMD_AFUS_LAUNCH)

	for unitDefID, unitDef in pairs(UnitDefs) do
		local cp = unitDef.customParams
		if cp and cp.afus_supremacy then
			afusUnitDefs[unitDefID] = true
			for _, weapon in ipairs(unitDef.weapons or {}) do
				local weaponDef = WeaponDefs[weapon.weaponDef]
				if weaponDef and weaponDef.customParams and weaponDef.customParams.afus_supremacy then
					payloadWeaponByUnitDef[unitDefID] = weapon.weaponDef
					payloadWeaponDefs[weapon.weaponDef] = true
					Script.SetWatchProjectile(weapon.weaponDef, true)
					break
				end
			end
		end
	end

	for _, unitID in ipairs(Spring.GetAllUnits()) do
		addLaunchCommand(unitID, spGetUnitDefID(unitID))
	end
end
