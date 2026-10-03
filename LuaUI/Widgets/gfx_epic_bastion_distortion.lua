function widget:GetInfo()
	return {
		name = "Epic Bastion Distortion",
		desc = "True screen-space heat refraction for the Legion Epic Bastion",
		author = "RandomGuy",
		date = "2026",
		license = "GNU GPL v2",
		layer = 0,
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
local cachedPointVBO

local function IsTargetDef(unitDefID)
	return targetDefs[unitDefID] == true
end

-- BAR's public GetDistortionVBO() currently returns nil. Prefer it if BAR
-- exposes the VBO in future; otherwise retrieve the already-public world VBO
-- map from RemoveDistortion's Lua closure. This keeps RandomGuy a tiny overlay
-- instead of copying the whole Distortion GL4 widget.
local function GetPointVBO(api)
	if cachedPointVBO then
		return cachedPointVBO
	end
	if api.GetDistortionVBO then
		cachedPointVBO = api.GetDistortionVBO("point")
		if cachedPointVBO then
			return cachedPointVBO
		end
	end
	if debug and debug.getupvalue and api.RemoveDistortion then
		for i = 1, 32 do
			local name, value = debug.getupvalue(api.RemoveDistortion, i)
			if not name then
				break
			end
			if name == "distortionVBOMap" and type(value) == "table" then
				cachedPointVBO = value.point
				return cachedPointVBO
			end
		end
	end
	return nil
end

local function NewHeatParams(x, y, z, mode)
	local p = {}
	for i = 1, 29 do
		p[i] = 0
	end

	local firing = mode == 2
	p[1], p[2], p[3] = x, y, z
	p[4] = firing and 82 or 58          -- radius
	p[10] = firing and 1.35 or 0.72    -- effectStrength
	p[11] = 0.40                        -- startRadius
	p[13] = firing and 18 or 8          -- noiseStrength
	p[14] = firing and 0.045 or 0.065   -- noiseScaleSpace
	p[15] = 0.50                        -- distanceFalloff
	p[16] = 0                           -- distort map + models
	p[18] = 0                           -- persistent until explicitly removed
	p[19] = firing and 2 or 6           -- rampUp
	p[20] = 0                           -- decay
	p[21] = 0.30                        -- riseRate
	p[23] = -1                          -- windAffected
	p[24] = 0                           -- heatDistortion
	return p
end

local function RemoveVisuals(state)
	local api = WG.distortionsgl4
	if not api or not state or not state.added then
		return
	end
	api.RemoveDistortion("point", state.id, nil)
	state.added = false
end

local function GetRingCenter(unitID)
	local pieceMap = spGetUnitPieceMap(unitID)
	if not pieceMap or not pieceMap.ring then
		return nil
	end
	return spGetUnitPiecePosDir(unitID, pieceMap.ring)
end

local function ApplyVisuals(unitID, state, mode)
	local api = WG.distortionsgl4
	if not api then
		return false
	end

	RemoveVisuals(state)

	if mode == 0 then
		state.mode = 0
		return true
	end

	local x, y, z = GetRingCenter(unitID)
	if not x then
		return false
	end

	local vbo = GetPointVBO(api)
	if not vbo then
		return false
	end

	api.AddDistortion(state.id, nil, nil, vbo, NewHeatParams(x, y, z, mode), false)
	state.added = true
	state.mode = mode
	return true
end

local function Track(unitID, unitDefID)
	if not IsTargetDef(unitDefID) or tracked[unitID] then
		return
	end
	tracked[unitID] = {
		mode = -1,
		added = false,
		id = "epicbastion_" .. unitID .. "_heat",
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
	if elapsed < 0.10 then
		return
	end
	elapsed = 0

	for unitID, state in pairs(tracked) do
		local hover = spGetUnitRulesParam(unitID, "epic_bastion_hover") or 0
		local firing = spGetUnitRulesParam(unitID, "epic_bastion_firing") or 0
		local desired = 0
		if hover > 0 then
			desired = (firing > 0) and 2 or 1
		end
		if desired ~= state.mode or (desired > 0 and not state.added) then
			ApplyVisuals(unitID, state, desired)
		end
	end
end

function widget:Shutdown()
	for _, state in pairs(tracked) do
		RemoveVisuals(state)
	end
end
