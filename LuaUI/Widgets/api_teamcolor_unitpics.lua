local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Team Color UnitPics API",
		desc = "BAR-native team-colour unit portraits rendered from UnitDef models",
		author = "RandomGuyJunior; rendering approach adapted from BAR icon/model tooling",
		date = "2026-09-30",
		license = "GNU GPL, v2 or later",
		layer = -999997,
		enabled = true,
		handler = true,
	}
end

local ICON_SIZE = 256
local MAX_GENERATE_PER_FRAME = 2
local caches = {}
local queue = {}
local queued = {}
local modelShader
local teamColUniform
local revision = 0

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
		vec4 t = texture2D(tex0, gl_TexCoord[0].st);
		vec3 albedo = mix(t.rgb, teamCol, t.a);
		float ndl = clamp(dot(normalize(vNormal), normalize(vec3(0.35, 1.0, 0.25))), 0.0, 1.0);
		gl_FragColor = vec4(albedo * (0.58 + 0.42 * ndl), 1.0);
	}
]]

local function colorKey(teamID)
	if teamID == nil then
		teamID = Spring.GetLocalTeamID()
	end
	local r, g, b = Spring.GetTeamColor(teamID)
	if not r then
		return nil
	end
	local ri = math.floor(math.max(0, math.min(1, r)) * 255 + 0.5)
	local gi = math.floor(math.max(0, math.min(1, g)) * 255 + 0.5)
	local bi = math.floor(math.max(0, math.min(1, b)) * 255 + 0.5)
	return ri .. ":" .. gi .. ":" .. bi, r, g, b
end

local function cacheKey(unitDefID, teamID)
	local ck, r, g, b = colorKey(teamID)
	if not ck then return nil end
	return tostring(unitDefID) .. "@" .. ck, r, g, b
end

local function getDimensions(unitDefID)
	local dims = Spring.GetUnitDefDimensions(unitDefID)
	if not dims then return nil end

	local midx = ((dims.maxx or 0) + (dims.minx or 0)) * 0.5
	local midy = (math.max(0, dims.maxy or 0) + math.max(0, dims.miny or 0)) * 0.5
	local midz = ((dims.maxz or 0) + (dims.minz or 0)) * 0.5
	local ax = math.max(math.abs((dims.maxx or 0) - midx), math.abs((dims.minx or 0) - midx))
	local ay = math.max(math.abs((dims.maxy or 0) - midy), math.abs((dims.miny or 0) - midy))
	local az = math.max(math.abs((dims.maxz or 0) - midz), math.abs((dims.minz or 0) - midz))
	local radius = math.sqrt(ax * ax + ay * ay + az * az)

	if radius < 1 then radius = 1 end
	return midx, midy, midz, radius
end

local function renderPortrait(job)
	if not modelShader or not UnitDefs[job.unitDefID] then
		return nil
	end

	local midx, midy, midz, radius = getDimensions(job.unitDefID)
	if not midx then return nil end

	-- Slight breathing room matches BAR's buildpic framing without requiring
	-- faction-specific or per-unit colour heuristics.
	local half = radius * 1.28
	local tex = gl.CreateTexture(ICON_SIZE, ICON_SIZE, {
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = true,
	})
	if not tex then
		return nil
	end

	local ok = pcall(function()
		gl.RenderToTexture(tex, function()
			gl.Clear(GL.COLOR_BUFFER_BIT, 0, 0, 0, 0)
			gl.Clear(GL.DEPTH_BUFFER_BIT, 1)
			gl.DepthTest(true)
			gl.DepthMask(true)
			gl.Culling(GL.BACK)
			gl.Blending(false)

			gl.MatrixMode(GL.PROJECTION)
			gl.PushMatrix()
			gl.LoadIdentity()
			gl.Ortho(-half, half, -half, half, -half * 8, half * 8)

			gl.MatrixMode(GL.MODELVIEW)
			gl.PushMatrix()
			gl.LoadIdentity()
			-- BAR's icon generator uses a shallow top-down angle plus 45-degree
			-- yaw. This keeps buildings and mobile units recognizable.
			gl.Rotate(26, 1, 0, 0)
			gl.Rotate(45, 0, 1, 0)
			gl.Translate(-midx, -midy, -midz)

			gl.UnitShapeTextures(job.unitDefID, true)
			gl.UseShader(modelShader)
			gl.Uniform(teamColUniform, job.r, job.g, job.b)
			-- rawState=true preserves our orthographic matrices. The custom
			-- shader supplies textures, lighting and the actual team colour.
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
	return tex
end

local function requestTexture(unitDefID, teamID)
	if not unitDefID or not UnitDefs[unitDefID] then return nil end
	teamID = teamID or Spring.GetLocalTeamID()

	local key, r, g, b = cacheKey(unitDefID, teamID)
	if not key then return nil end
	if caches[key] then
		return caches[key]
	end

	if not queued[key] then
		queued[key] = true
		queue[#queue + 1] = {
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
	local n = math.min(MAX_GENERATE_PER_FRAME, #queue)
	for _ = 1, n do
		local job = table.remove(queue, 1)
		if job then
			queued[job.key] = nil
			if not caches[job.key] then
				local tex = renderPortrait(job)
				if tex then
					caches[job.key] = tex
					revision = revision + 1
				end
			end
		end
	end
end

function widget:Initialize()
	modelShader = gl.CreateShader({
		vertex = MODEL_VERT,
		fragment = MODEL_FRAG,
		uniformInt = { tex0 = 0 },
		uniformFloat = { teamCol = { 1, 1, 1 } },
	})
	if not modelShader or modelShader == 0 then
		Spring.Echo("[Team Color UnitPics] shader failed:", tostring(gl.GetShaderLog()))
		widgetHandler:RemoveWidget()
		return
	end
	teamColUniform = gl.GetUniformLocation(modelShader, "teamCol")

	WG.TeamColorUnitPics = {
		GetTexture = requestTexture,
		Invalidate = function()
			for key, tex in pairs(caches) do
				gl.DeleteTexture(tex)
				caches[key] = nil
			end
			for key in pairs(queued) do queued[key] = nil end
			for i = #queue, 1, -1 do queue[i] = nil end
			revision = revision + 1
		end,
		GetRevision = function()
			return revision
		end,
	}
end

function widget:DrawGenesis()
	processQueue()
end

function widget:PlayerChanged()
	-- Color-keyed cache means old colours are harmless, but clearing keeps
	-- memory bounded when players change colour repeatedly.
	if WG.TeamColorUnitPics then
		WG.TeamColorUnitPics.Invalidate()
	end
end

function widget:Shutdown()
	if WG.TeamColorUnitPics then
		WG.TeamColorUnitPics.Invalidate()
		WG.TeamColorUnitPics = nil
	end
	if modelShader then
		gl.DeleteShader(modelShader)
		modelShader = nil
	end
end
