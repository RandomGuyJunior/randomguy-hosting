function widget:GetInfo()
	return {
		name = "Epic Bastion Distortion",
		desc = "BAR GL4 spatial refraction for the Epic Bastion rings and heat ray",
		author = "RandomGuy",
		date = "2026",
		license = "GNU GPL v2",
		layer = 1,
		enabled = true,
	}
end

local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitPieceMap = Spring.GetUnitPieceMap
local spGetUnitPiecePosDir = Spring.GetUnitPiecePosDir

local targetDefs = {}
local tracked = {}
local elapsed = 0
local cachedVBO = {}

local function IsTargetDef(unitDefID)
	return targetDefs[unitDefID] == true
end

local function GetVBO(api, shape)
	if cachedVBO[shape] then
		return cachedVBO[shape]
	end
	if api.GetDistortionVBO then
		cachedVBO[shape] = api.GetDistortionVBO(shape)
		if cachedVBO[shape] then
			return cachedVBO[shape]
		end
	end

	-- Compatibility fallback for an upstream renderer without the accessor.
	if debug and debug.getupvalue and api.RemoveDistortion then
		for i = 1, 32 do
			local name, value = debug.getupvalue(api.RemoveDistortion, i)
			if not name then break end
			if name == "distortionVBOMap" and type(value) == "table" then
				cachedVBO[shape] = value[shape]
				return cachedVBO[shape]
			end
		end
	end
	return nil
end

local function EmptyParams()
	local p = {}
	for i = 1, 29 do p[i] = 0 end
	return p
end

local function PointHeatParams(x, y, z, firing)
	local p = EmptyParams()
	p[1], p[2], p[3] = x, y + (firing and 12 or 22), z
	p[4] = firing and 92 or 62
	p[10] = firing and 1.65 or 0.48
	p[11] = firing and 0.32 or 0.46
	p[13] = firing and 20 or 5.5
	p[14] = firing and 0.038 or 0.085
	p[15] = firing and 0.42 or 0.75
	p[16] = 0
	p[18] = 0
	p[19] = firing and 1 or 8
	p[20] = 0
	p[21] = firing and 0.45 or 0.18
	p[23] = -1
	p[24] = 0
	return p
end

local function BeamHeatParams(x, y, z, dx, dy, dz)
	local p = EmptyParams()
	local length = 1380
	p[1], p[2], p[3] = x, y, z
	p[4] = 24
	p[5], p[6], p[7] = x + dx * length, y + dy * length, z + dz * length
	p[10] = 2.35
	p[11] = 0.22
	p[13] = 3.2
	p[14] = 0.028
	p[15] = 0.55
	p[16] = 0
	p[18] = 0
	p[19] = 0
	p[20] = 0
	p[21] = 0.25
	p[23] = -1
	p[24] = 0
	return p
end

local function RemoveOne(api, shape, id)
	if id then
		api.RemoveDistortion(shape, id, nil)
	end
end

local function RemoveVisuals(state)
	local api = WG.distortionsgl4
	if not api or not state then return end
	if state.pointAdded then
		RemoveOne(api, "point", state.pointId)
		state.pointAdded = false
	end
	if state.beamAdded then
		RemoveOne(api, "beam", state.beamId)
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
	if not api then return false end
	local piece = GetPiece(unitID, "ringanchor") or GetPiece(unitID, "ring")
	if not piece then return false end
	local x, y, z = spGetUnitPiecePosDir(unitID, piece)
	if not x then return false end
	local vbo = GetVBO(api, "point")
	if not vbo then return false end
	api.AddDistortion(state.pointId, nil, nil, vbo, PointHeatParams(x, y, z, firing), false)
	state.pointAdded = true
	return true
end

local function AddBeam(unitID, state)
	local api = WG.distortionsgl4
	if not api then return false end
	local piece = GetPiece(unitID, "beam_muzzle")
	if not piece then return false end
	local x, y, z, dx, dy, dz = spGetUnitPiecePosDir(unitID, piece)
	if not x or not dx then return false end
	local vbo = GetVBO(api, "beam")
	if not vbo then return false end
	api.AddDistortion(state.beamId, nil, nil, vbo, BeamHeatParams(x, y, z, dx, dy, dz), false)
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
		RemoveOne(api, "beam", state.beamId)
		state.beamAdded = false
	end
	AddBeam(unitID, state)
end

local function Track(unitID, unitDefID)
	if not IsTargetDef(unitDefID) or tracked[unitID] then return end
	tracked[unitID] = {
		mode = -1,
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
		local hover = spGetUnitRulesParam(unitID, "epic_bastion_hover") or 0
		local firing = spGetUnitRulesParam(unitID, "epic_bastion_firing") or 0
		local desired = 0
		if hover > 0 then
			desired = (firing > 0) and 2 or 1
		end

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
