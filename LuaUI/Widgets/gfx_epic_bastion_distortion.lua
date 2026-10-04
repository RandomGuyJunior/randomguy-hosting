function widget:GetInfo()
	return {
		name = "Epic Bastion Distortion",
		desc = "BAR GL4 spatial refraction for the Epic Bastion rings and heat ray",
		author = "RandomGuy",
		date = "2026",
		license = "GNU GPL v2",
		layer = 1,
		enabled = false,
	}
end

local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitPieceMap = Spring.GetUnitPieceMap

local targetDefs = {}
local tracked = {}
local elapsed = 0
local cachedVBO = {}

local distortionConfig = VFS.Include("LuaUI/configs/distortionconfigs/epic_bastion.lua")

local function IsTargetDef(unitDefID)
	return targetDefs[unitDefID] == true
end

local function EmptyParams()
	local p = {}
	for i = 1, 29 do p[i] = 0 end
	return p
end

local function PointHeatParams(firing)
	local cfg = firing and distortionConfig.firing.point or distortionConfig.passive.point
	local p = EmptyParams()
	p[1], p[2], p[3] = 0, 0, 0
	p[4] = cfg.radius
	p[10] = cfg.effectStrength
	p[11] = cfg.startRadius
	p[13] = cfg.noiseStrength
	p[14] = cfg.noiseScaleSpace
	p[15] = cfg.distanceFalloff
	p[16] = 0
	p[18] = 0
	p[19] = cfg.rampUp
	p[20] = 0
	p[21] = cfg.riseRate
	p[23] = -1
	p[24] = 0
	return p
end

local function BeamHeatParams()
	local cfg = distortionConfig.firing.beam
	local p = EmptyParams()
	local length = cfg.length
	p[1], p[2], p[3] = 0, 0, 0
	p[4] = cfg.radius
	p[5], p[6], p[7] = 0, 0, length
	p[10] = cfg.effectStrength
	p[11] = cfg.startRadius
	p[13] = cfg.noiseStrength
	p[14] = cfg.noiseScaleSpace
	p[15] = cfg.distanceFalloff
	p[16] = 0
	p[18] = 0
	p[19] = 0
	p[20] = 0
	p[21] = cfg.riseRate
	p[23] = -1
	p[24] = 0
	return p
end

local function RemoveOne(api, shape, id, unitID)
	if id then
		api.RemoveDistortion(shape, id, unitID)
	end
end

local function RemoveVisuals(state)
	local api = WG.distortionsgl4
	if not api or not state then return end
	if state.pointAdded then
		RemoveOne(api, "point", state.pointId, state.unitID)
		state.pointAdded = false
	end
	if state.beamAdded then
		RemoveOne(api, "beam", state.beamId, state.unitID)
		state.beamAdded = false
	end
end

local function GetPiece(unitID, name)
	local pieceMap = spGetUnitPieceMap(unitID)
	if not pieceMap then return nil end
	return pieceMap[name]
end

local function AddPoint(unitID, state, firing)
	local api = WG.distortionsgl4
	if not api or not api.GetUnitDistortionVBO then return false end
	local piece = GetPiece(unitID, "ringanchor") or GetPiece(unitID, "ring")
	if not piece then return false end
	local vbo = api.GetUnitDistortionVBO("point")
	if not vbo then return false end
	api.AddDistortion(state.pointId, unitID, piece, vbo, PointHeatParams(firing), false)
	state.pointAdded = true
	return true
end

local function AddBeam(unitID, state)
	local api = WG.distortionsgl4
	if not api or not api.GetUnitDistortionVBO then return false end
	local piece = GetPiece(unitID, "beam_muzzle")
	if not piece then return false end
	local vbo = api.GetUnitDistortionVBO("beam")
	if not vbo then return false end
	api.AddDistortion(state.beamId, unitID, piece, vbo, BeamHeatParams(), false)
	state.beamAdded = true
	return true
end

local function ApplyMode(unitID, state, mode)
	local api = WG.distortionsgl4
	if not api then return false end
	RemoveVisuals(state)

	if mode == 0 then
		state.mode = 0
		return true
	end

	if not AddPoint(unitID, state, mode == 2) then
		return false
	end
	if mode == 2 then
		AddBeam(unitID, state)
	end
	state.mode = mode
	return true
end

local function RefreshFiringBeam(unitID, state)
	local api = WG.distortionsgl4
	if not api then return end
	if state.beamAdded then
		RemoveOne(api, "beam", state.beamId, state.unitID)
		state.beamAdded = false
	end
	AddBeam(unitID, state)
end

local function Track(unitID, unitDefID)
	if not IsTargetDef(unitDefID) or tracked[unitID] then return end
	tracked[unitID] = {
		mode = -1,
		unitID = unitID,
		pointAdded = false,
		beamAdded = false,
		pointId = "epicbastion_" .. unitID .. "_ringheat",
		beamId = "epicbastion_" .. unitID .. "_beamheat",
	}
end

function widget:Initialize()
	if UnitDefNames.legbastiont3 then
		targetDefs[UnitDefNames.legbastiont3.id] = true
	end
	if UnitDefNames.legbastiont3_scav then
		targetDefs[UnitDefNames.legbastiont3_scav.id] = true
	end
	if not next(targetDefs) then
		widgetHandler:RemoveWidget()
		return
	end
	for _, unitID in ipairs(spGetAllUnits()) do
		Track(unitID, spGetUnitDefID(unitID))
	end
end

function widget:UnitCreated(unitID, unitDefID)
	Track(unitID, unitDefID)
end

function widget:UnitDestroyed(unitID)
	local state = tracked[unitID]
	if state then
		RemoveVisuals(state)
		tracked[unitID] = nil
	end
end

function widget:Update(dt)
	elapsed = elapsed + dt
	if elapsed < 0.05 then return end
	elapsed = 0

	for unitID, state in pairs(tracked) do
		local firing = spGetUnitRulesParam(unitID, "epic_bastion_firing") or 0
		-- Minor passive ring distortion is always present; firing replaces it
		-- with the stronger point distortion and adds the beam distortion.
		local desired = (firing > 0) and 2 or 1

		if desired ~= state.mode or (desired > 0 and not state.pointAdded) then
			ApplyMode(unitID, state, desired)
		elseif desired == 2 then
			-- Rebuild only the beam instance so its endpoint follows the
			-- invisible yaw/pitch pivot while the sustained sweep is moving.
			RefreshFiringBeam(unitID, state)
		end
	end
end

function widget:Shutdown()
	for _, state in pairs(tracked) do
		RemoveVisuals(state)
	end
end
