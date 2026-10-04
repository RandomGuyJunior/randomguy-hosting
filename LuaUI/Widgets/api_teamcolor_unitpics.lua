local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Team Color UnitPics API",
		desc = "Generates lit model build portraits with land/sea/amphibious backgrounds and true model team-colour masks",
		author = "RandomGuyJunior; portrait lighting values adapted from BAR icon-generator config",
		date = "2026-10-04",
		license = "GNU GPL, v2 or later",
		layer = -999997,
		enabled = true,
		handler = true,
	}
end

local ICON_SIZE = 256
local MAX_GENERATE_PER_FRAME = 2
local MAX_CACHE_ENTRIES = 768
local AMPHIBIOUS_DEPTH = 5000

local caches = {}
local cacheOrder = {}
local cacheHead = 1
local cacheTail = 0
local cacheCount = 0
local queue = {}
local queueHead = 1
local queueTail = 0
local queued = {}
local modelShader
local backgroundShader
local teamColUniform
local backgroundModeUniform
local shadowScaleUniform
local revision = 0

local BG_LAND = 0
local BG_SEA = 1
local BG_AMPHIBIOUS = 2

local MODEL_VERT = [[
	#version 150 compatibility
	varying vec3 vNormal;
	void main() {
		gl_TexCoord[0] = gl_MultiTexCoord0;
		vNormal = gl_NormalMatrix * gl_Normal;
		gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
	}
]]

local MODEL_FRAG = [[
	#version 150 compatibility
	uniform sampler2D tex0;
	uniform vec3 teamCol;
	varying vec3 vNormal;

	void main() {
		vec4 texel = texture2D(tex0, gl_TexCoord[0].st);

		// S3O texture-1 alpha is the model's real team-colour mask.
		// This is the authoritative paint indicator: no hue matching, no
		// buildpic pixel guessing, and no background can ever become team colour.
		float teamMask = clamp(texel.a, 0.0, 1.0);
		vec3 albedo = mix(texel.rgb, teamCol, teamMask);

		vec3 n = normalize(vNormal);
		vec3 keyDir = normalize(vec3(-0.30, 0.50, 0.55));
		vec3 fillDir = normalize(vec3(0.50, 0.20, -0.35));
		float key = max(dot(n, keyDir), 0.0);
		float fill = max(dot(n, fillDir), 0.0);
		float rim = pow(1.0 - abs(n.z), 2.0);

		// BAR buildpic config uses ~0.6 ambient with a strong diffuse source.
		// Keep that readable icon-lighting style while adding a mild fill/rim.
		float lighting = 0.60 + 0.34 * key + 0.10 * fill + 0.06 * rim;
		gl_FragColor = vec4(albedo * lighting, 1.0);
	}
]]

local BACKGROUND_VERT = [[
	#version 150 compatibility
	varying vec2 uv;
	void main() {
		uv = gl_MultiTexCoord0.st;
		gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
	}
]]

local BACKGROUND_FRAG = [[
	#version 150 compatibility
	uniform float backgroundMode;
	uniform vec2 shadowScale;
	varying vec2 uv;

	float hash(vec2 p) {
		return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
	}

	vec3 landColour(vec2 p) {
		float grain = (hash(floor(p * 48.0)) - 0.5) * 0.035;
		float bands = sin((p.x + p.y * 0.35) * 18.0) * 0.012;
		return vec3(0.29 + grain + bands, 0.275 + grain, 0.235 + grain * 0.6);
	}

	vec3 waterColour(vec2 p) {
		float waves = sin(p.x * 42.0 + p.y * 11.0) * 0.018
			+ sin(p.x * 19.0 - p.y * 27.0) * 0.012;
		return vec3(0.105 + waves * 0.35, 0.235 + waves * 0.55, 0.315 + waves);
	}

	void main() {
		float horizon = 0.53;
		float skyT = smoothstep(horizon, 1.0, uv.y);
		vec3 sky = mix(vec3(0.31, 0.37, 0.40), vec3(0.52, 0.58, 0.61), skyT);

		vec3 surface;
		if (backgroundMode < 0.5) {
			surface = landColour(uv);
		} else if (backgroundMode < 1.5) {
			surface = waterColour(uv);
		} else {
			// True amphibious portrait: one half land, one half water with a
			// narrow soft shoreline, rather than tinting a single background.
			float shore = smoothstep(0.46, 0.54, uv.x);
			surface = mix(landColour(uv), waterColour(uv), shore);
		}

		float ground = 1.0 - smoothstep(horizon - 0.025, horizon + 0.025, uv.y);
		vec3 colour = mix(sky, surface, ground);

		// Soft contact shadow / water shadow beneath the generated model.
		vec2 d = vec2((uv.x - 0.50) / max(shadowScale.x, 0.01),
					  (uv.y - 0.405) / max(shadowScale.y, 0.01));
		float shadow = (1.0 - smoothstep(0.45, 1.0, dot(d, d))) * ground;
		colour *= 1.0 - shadow * 0.34;

		// Small vignette keeps silhouettes readable without baking unit art.
		vec2 edge = abs(uv - 0.5) * 2.0;
		float vignette = smoothstep(0.72, 1.35, max(edge.x, edge.y));
		colour *= 1.0 - vignette * 0.13;

		gl_FragColor = vec4(colour, 1.0);
	}
]]

local function colorKey(teamID)
	teamID = teamID or Spring.GetLocalTeamID()
	local r, g, b = Spring.GetTeamColor(teamID)
	if not r then return nil end
	local ri = math.floor(math.clamp(r, 0, 1) * 255 + 0.5)
	local gi = math.floor(math.clamp(g, 0, 1) * 255 + 0.5)
	local bi = math.floor(math.clamp(b, 0, 1) * 255 + 0.5)
	return ri .. ":" .. gi .. ":" .. bi, r, g, b
end

local function cacheKey(unitDefID, teamID)
	local ck, r, g, b = colorKey(teamID)
	if not ck then return nil end
	return tostring(unitDefID) .. "@" .. ck, r, g, b
end

local function classifyBackground(unitDef)
	if not unitDef then return BG_LAND end

	-- Aircraft deliberately use the land presentation.
	if unitDef.canFly then
		return BG_LAND
	end

	-- Water-only structures belong on the sea background even when they expose
	-- no useful movedef (or some auxiliary movement metadata).
	if unitDef.floatOnWater or ((unitDef.minWaterDepth or 0) > 0) then
		return BG_SEA
	end

	local md = unitDef.moveDef
	if md then
		local smClass = md.smClass
		local speedClasses = Game.speedModClasses or {}
		local shipClass = speedClasses.Ship or speedClasses.ship
		local boatClass = speedClasses.Boat or speedClasses.boat
		local hoverClass = speedClasses.Hover or speedClasses.hover

		-- Ships and submarines are water-only.
		if (shipClass ~= nil and smClass == shipClass)
			or (boatClass ~= nil and smClass == boatClass)
			or (md.isSubmarine == true)
		then
			return BG_SEA
		end

		-- Hovers can operate on both land and water, so they use the same split
		-- presentation as true amphibious Tank/KBot movedefs.
		if hoverClass ~= nil and smClass == hoverClass then
			return BG_AMPHIBIOUS
		end

		-- BAR exposes movedef max-water-depth as .depth in UnitDef.moveDef.
		-- Deep-capable non-ship units are true amphibious units.
		if md.depth and md.depth >= AMPHIBIOUS_DEPTH then
			return BG_AMPHIBIOUS
		end
	end

	return BG_LAND
end

local function getProjectedBounds(unitDefID)
	local dims = Spring.GetUnitDefDimensions(unitDefID)
	if not dims then return nil end

	local minx, maxx = dims.minx or 0, dims.maxx or 0
	local miny, maxy = dims.miny or 0, dims.maxy or 0
	local minz, maxz = dims.minz or 0, dims.maxz or 0
	local midx = (minx + maxx) * 0.5
	local midy = (miny + maxy) * 0.5
	local midz = (minz + maxz) * 0.5

	local yaw = math.rad(45)
	local pitch = math.rad(26)
	local cy, sy = math.cos(yaw), math.sin(yaw)
	local cp, sp = math.cos(pitch), math.sin(pitch)

	local minPX, maxPX = math.huge, -math.huge
	local minPY, maxPY = math.huge, -math.huge
	for _, x in ipairs({ minx, maxx }) do
		for _, y in ipairs({ miny, maxy }) do
			for _, z in ipairs({ minz, maxz }) do
				local lx, ly, lz = x - midx, y - midy, z - midz
				-- Matches gl.Rotate(26, X) then gl.Rotate(45, Y):
				-- the Y rotation acts first on the vertex.
				local rx = lx * cy + lz * sy
				local rz = -lx * sy + lz * cy
				local ry = ly * cp - rz * sp
				minPX = math.min(minPX, rx)
				maxPX = math.max(maxPX, rx)
				minPY = math.min(minPY, ry)
				maxPY = math.max(maxPY, ry)
			end
		end
	end

	local halfW = math.max(1, (maxPX - minPX) * 0.5)
	local halfH = math.max(1, (maxPY - minPY) * 0.5)
	-- 7% border around the actual projected model box. This avoids the old
	-- bounding-sphere problem that made long/tall units appear tiny.
	local half = math.max(halfW, halfH) / 0.93

	return midx, midy, midz, half, halfW, halfH
end

local function drawFullscreenQuad()
	gl.TexCoord(0, 0); gl.Vertex(-1, -1, 0)
	gl.TexCoord(1, 0); gl.Vertex( 1, -1, 0)
	gl.TexCoord(1, 1); gl.Vertex( 1,  1, 0)
	gl.TexCoord(0, 1); gl.Vertex(-1,  1, 0)
end

local function drawBackground(mode, halfW, halfH, half)
	gl.MatrixMode(GL.PROJECTION)
	gl.PushMatrix()
	gl.LoadIdentity()
	gl.Ortho(-1, 1, 1, -1, -1, 1)
	gl.MatrixMode(GL.MODELVIEW)
	gl.PushMatrix()
	gl.LoadIdentity()

	gl.DepthTest(false)
	gl.DepthMask(false)
	gl.Blending(false)
	gl.UseShader(backgroundShader)
	gl.Uniform(backgroundModeUniform, mode)
	local occupancyX = math.clamp(halfW / half, 0.18, 0.95)
	gl.Uniform(shadowScaleUniform, math.clamp(occupancyX * 0.46, 0.16, 0.43), 0.105)
	gl.BeginEnd(GL.QUADS, drawFullscreenQuad)
	gl.UseShader(0)

	gl.MatrixMode(GL.MODELVIEW)
	gl.PopMatrix()
	gl.MatrixMode(GL.PROJECTION)
	gl.PopMatrix()
	gl.MatrixMode(GL.MODELVIEW)
end

local function renderPortrait(job)
	local unitDef = UnitDefs[job.unitDefID]
	if not modelShader or not backgroundShader or not unitDef then
		return nil
	end

	local midx, midy, midz, half, halfW, halfH = getProjectedBounds(job.unitDefID)
	if not midx then return nil end

	local tex = gl.CreateTexture(ICON_SIZE, ICON_SIZE, {
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = true,
	})
	if not tex then return nil end

	local mode = classifyBackground(unitDef)
	local ok = pcall(function()
		gl.RenderToTexture(tex, function()
			gl.Clear(GL.COLOR_BUFFER_BIT, 0, 0, 0, 1)
			gl.Clear(GL.DEPTH_BUFFER_BIT, 1)

			drawBackground(mode, halfW, halfH, half)

			gl.DepthTest(true)
			gl.DepthMask(true)
			gl.Culling(GL.BACK)
			gl.Blending(false)

			gl.MatrixMode(GL.PROJECTION)
			gl.PushMatrix()
			gl.LoadIdentity()
			gl.Ortho(-half, half, half, -half, -half * 8, half * 8)

			gl.MatrixMode(GL.MODELVIEW)
			gl.PushMatrix()
			gl.LoadIdentity()
			gl.Rotate(26, 1, 0, 0)
			gl.Rotate(45, 0, 1, 0)
			gl.Translate(-midx, -midy, -midz)

			gl.UnitShapeTextures(job.unitDefID, true)
			gl.UseShader(modelShader)
			gl.Uniform(teamColUniform, job.r, job.g, job.b)
			gl.UnitShape(job.unitDefID, job.teamID, true, false, true)
			gl.UseShader(0)
			gl.UnitShapeTextures(job.unitDefID, false)

			gl.MatrixMode(GL.PROJECTION)
			gl.PopMatrix()
			gl.MatrixMode(GL.MODELVIEW)
			gl.PopMatrix()

			gl.Culling(false)
			gl.DepthMask(false)
			gl.DepthTest(false)
			gl.Blending(true)
		end)
	end)

	if not ok then
		gl.DeleteTexture(tex)
		return nil
	end
	return tex, mode
end

local function deleteCachedKey(key)
	local entry = caches[key]
	if entry then
		gl.DeleteTexture(entry.texture)
		caches[key] = nil
		cacheCount = math.max(0, cacheCount - 1)
	end
end

local function storeCache(job, texture, mode)
	if not caches[job.key] then
		cacheCount = cacheCount + 1
	end
	caches[job.key] = {
		texture = texture,
		backgroundMode = mode,
		unitDefID = job.unitDefID,
	}
	cacheTail = cacheTail + 1
	cacheOrder[cacheTail] = job.key

	while cacheCount > MAX_CACHE_ENTRIES do
		while cacheHead <= cacheTail do
			local oldKey = cacheOrder[cacheHead]
			cacheOrder[cacheHead] = nil
			cacheHead = cacheHead + 1
			if oldKey and caches[oldKey] then
				deleteCachedKey(oldKey)
				break
			end
		end
		if cacheHead > cacheTail then
			cacheOrder = {}
			cacheHead, cacheTail = 1, 0
		end
	end
end

local function requestTexture(unitDefID, teamID)
	if not unitDefID or not UnitDefs[unitDefID] then return nil end
	teamID = teamID or Spring.GetLocalTeamID()

	local key, r, g, b = cacheKey(unitDefID, teamID)
	if not key then return nil end
	if caches[key] then
		return caches[key].texture
	end

	if not queued[key] then
		queued[key] = true
		queueTail = queueTail + 1
		queue[queueTail] = {
			key = key,
			unitDefID = unitDefID,
			teamID = teamID,
			r = r,
			g = g,
			b = b,
		}
	end
	return nil
end

local function processQueue()
	local produced = false
	for _ = 1, MAX_GENERATE_PER_FRAME do
		if queueHead > queueTail then
			queue = {}
			queueHead, queueTail = 1, 0
			break
		end

		local job = queue[queueHead]
		queue[queueHead] = nil
		queueHead = queueHead + 1
		if job then
			queued[job.key] = nil
			if not caches[job.key] then
				local tex, mode = renderPortrait(job)
				if tex then
					storeCache(job, tex, mode)
					revision = revision + 1
					produced = true
				end
			end
		end
	end
	return produced
end

local function invalidate(unitDefID)
	for key, entry in pairs(caches) do
		if not unitDefID or entry.unitDefID == unitDefID then
			deleteCachedKey(key)
		end
	end
	if not unitDefID then
		queued = {}
		queue = {}
		queueHead, queueTail = 1, 0
	end
	revision = revision + 1
end

local function backgroundName(unitDefID)
	local mode = classifyBackground(UnitDefs[unitDefID])
	if mode == BG_SEA then return "sea" end
	if mode == BG_AMPHIBIOUS then return "amphibious" end
	return "land"
end

function widget:Initialize()
	modelShader = gl.CreateShader({
		vertex = MODEL_VERT,
		fragment = MODEL_FRAG,
		uniformInt = { tex0 = 0 },
		uniformFloat = { teamCol = { 1, 1, 1 } },
	})
	if not modelShader or modelShader == 0 then
		Spring.Echo("[Team Color UnitPics] model shader failed:", tostring(gl.GetShaderLog()))
		widgetHandler:RemoveWidget()
		return
	end
	teamColUniform = gl.GetUniformLocation(modelShader, "teamCol")

	backgroundShader = gl.CreateShader({
		vertex = BACKGROUND_VERT,
		fragment = BACKGROUND_FRAG,
		uniformFloat = {
			backgroundMode = 0,
			shadowScale = { 0.35, 0.105 },
		},
	})
	if not backgroundShader or backgroundShader == 0 then
		Spring.Echo("[Team Color UnitPics] background shader failed:", tostring(gl.GetShaderLog()))
		gl.DeleteShader(modelShader)
		modelShader = nil
		widgetHandler:RemoveWidget()
		return
	end
	backgroundModeUniform = gl.GetUniformLocation(backgroundShader, "backgroundMode")
	shadowScaleUniform = gl.GetUniformLocation(backgroundShader, "shadowScale")

	WG.TeamColorUnitPics = {
		GetTexture = requestTexture,
		Invalidate = invalidate,
		GetRevision = function() return revision end,
		GetBackgroundType = backgroundName,
		GetTeamColorSource = function() return "model_texture1_alpha" end,
	}
	Spring.Echo("[Team Color UnitPics] model-generated portrait cache installed (land/sea/amphibious)")
end

function widget:DrawGenesis()
	processQueue()
end

function widget:PlayerChanged()
	-- Cached portraits are keyed by exact team RGB. No guessing or mutation is
	-- necessary; a new colour produces one new portrait on first request.
end

function widget:Shutdown()
	if WG.TeamColorUnitPics then
		WG.TeamColorUnitPics = nil
	end
	for key in pairs(caches) do
		deleteCachedKey(key)
	end
	if modelShader then
		gl.DeleteShader(modelShader)
		modelShader = nil
	end
	if backgroundShader then
		gl.DeleteShader(backgroundShader)
		backgroundShader = nil
	end
end
