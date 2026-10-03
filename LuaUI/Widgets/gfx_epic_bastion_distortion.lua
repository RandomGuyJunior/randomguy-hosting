function widget:GetInfo()
	return {
		name = "Epic Bastion Distortion",
		desc = "Hover/firing heat distortion for the Legion Epic Bastion",
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

local targetDefs = {}
local tracked = {}
local elapsed = 0

local function IsTargetDef(unitDefID)
	return targetDefs[unitDefID] == true
end

local function NewParams(radius, strength)
	local p = {}
	for i = 1, 29 do
		p[i] = 0
	end
	p[4] = radius
	p[10] = strength
	p[11] = radius
	p[13] = 0.85
	p[14] = -1.75
	p[15] = 0.75
	p[16] = 0
	p[18] = 0
	p[19] = 8
	p[20] = 12
	p[21] = 0.10
	p[23] = -0.15
	p[24] = 0 -- heatDistortion
	return p
end

local function RemoveVisuals(unitID, state)
	local api = WG.distortionsgl4
	if not api or not state or not state.added then
		return
	end
	api.RemoveDistortion("point", state.id1, unitID)
	api.RemoveDistortion("point", state.id2, unitID)
	state.added = false
end

local function ApplyVisuals(unitID, state, mode)
	local api = WG.distortionsgl4
	if not api then
		return false
	end

	RemoveVisuals(unitID, state)

	if mode == 0 then
		state.mode = 0
		return true
	end

	local pieceMap = spGetUnitPieceMap(unitID)
	if not pieceMap or not pieceMap.ring or not pieceMap.ring2 then
		return false
	end

	local vbo = api.GetDistortionVBO("point")
	if not vbo then
		return false
	end

	local radius = (mode == 2) and 46 or 28
	local strength = (mode == 2) and 0.95 or 0.28

	api.AddDistortion(state.id1, unitID, pieceMap.ring, vbo, NewParams(radius, strength), false)
	api.AddDistortion(state.id2, unitID, pieceMap.ring2, vbo, NewParams(radius, strength), false)
	state.added = true
	state.mode = mode
	return true
end

local function Track(unitID, unitDefID)
	if not IsTargetDef(unitDefID) then
		return
	end
	if tracked[unitID] then
		return
	end
	tracked[unitID] = {
		mode = -1,
		added = false,
		id1 = "epicbastion_" .. unitID .. "_ring1",
		id2 = "epicbastion_" .. unitID .. "_ring2",
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
		RemoveVisuals(unitID, state)
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
	for unitID, state in pairs(tracked) do
		RemoveVisuals(unitID, state)
	end
end
