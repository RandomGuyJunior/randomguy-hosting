local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AFUS Supremacy",
		desc = "Consumes AFUS units after successful Supremacy weapon fire",
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

local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitIsDead = Spring.GetUnitIsDead
local spDestroyUnit = Spring.DestroyUnit
local spValidUnitID = Spring.ValidUnitID

local afusUnitDefs = {}
local supremacyWeaponDefs = {}
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

local function isLiveSupremacyAFUS(unitID)
	if not unitID or not spValidUnitID(unitID) or spGetUnitIsDead(unitID) then
		return false
	end
	local unitDefID = spGetUnitDefID(unitID)
	local teamID = spGetUnitTeam(unitID)
	return unitDefID
		and afusUnitDefs[unitDefID] == true
		and teamHasMode(teamID)
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	if not supremacyWeaponDefs[weaponDefID] then
		return
	end
	if ownerID and isLiveSupremacyAFUS(ownerID) then
		pendingConsume[ownerID] = currentFrame + 1
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
			if isLiveSupremacyAFUS(unitID) then
				-- Do not use selfDestruct here: the projectile itself carries the AFUS
				-- payload. We only remove the consumed launcher/interceptor unit.
				spDestroyUnit(unitID, false, true)
			end
		end
	end
end

function gadget:Initialize()
	for weaponDefID, weaponDef in pairs(WeaponDefs) do
		local cp = weaponDef.customParams
		if cp and cp.afus_supremacy then
			supremacyWeaponDefs[weaponDefID] = true
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
