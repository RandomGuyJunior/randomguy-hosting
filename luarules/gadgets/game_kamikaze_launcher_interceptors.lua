local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Kamikaze Launcher/Interceptors",
		desc = "Provides generic consume/self-destruct behavior for kamikaze launcher/interceptor units",
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

local spDestroyUnit = Spring.DestroyUnit
local spGetUnitIsDead = Spring.GetUnitIsDead
local spValidUnitID = Spring.ValidUnitID

local pending = {}
local currentFrame = 0

local function validUnit(unitID)
	return unitID and spValidUnitID(unitID) and not spGetUnitIsDead(unitID)
end

local function queue(unitID, explode)
	if not validUnit(unitID) then
		return false
	end
	pending[unitID] = {
		frame = currentFrame + 1,
		explode = explode == true,
	}
	return true
end

function gadget:GameFrame(frame)
	currentFrame = frame

	for unitID, data in pairs(pending) do
		if frame >= data.frame then
			pending[unitID] = nil
			if validUnit(unitID) then
				if data.explode then
					spDestroyUnit(unitID, true, false)
				else
					spDestroyUnit(unitID, false, true)
				end
			end
		end
	end
end

function gadget:UnitDestroyed(unitID)
	pending[unitID] = nil
end

function gadget:Initialize()
	GG.KamikazeLauncherInterceptors = {
		Consume = function(unitID)
			return queue(unitID, false)
		end,
		SelfDestruct = function(unitID)
			return queue(unitID, true)
		end,
	}
end

function gadget:Shutdown()
	if GG.KamikazeLauncherInterceptors then
		GG.KamikazeLauncherInterceptors = nil
	end
end
