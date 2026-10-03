local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Team Color BuildPics Cache",
		desc = "Generates and caches team-coloured variants of BAR's native buildpics",
		author = "RandomGuyJunior",
		date = "2026-10-03",
		license = "GNU GPL, v2 or later",
		layer = 0.5,
		enabled = true,
		handler = true,
	}
end

local CACHE_SIZE = 256
local GENERATE_PER_FRAME = 2

local shader
local originalDrawUnit
local wrappedDrawUnit
local cache = {}
local queue = {}
local queued = {}

local HUE_MIN_ARM, HUE_MAX_ARM = 0.50, 0.66
local HUE_MIN_COR, HUE_MAX_COR = 0.95, 0.035
local HUE_MIN_LEG, HUE_MAX_LEG = 0.27, 0.44
local HUE_MIN_SCAV, HUE_MAX_SCAV = 0.68, 0.90
local SAT_DEFAULT = 0.30

local SAT_OVERRIDES = {
	legafus = { arm = 1.5 },
	legafust3 = { arm = 1.5 },
	coradvsol = { arm = 1.5 },
	legadvsol = { arm = 1.5 },
	armbeamer = { scav = 1.5 },
	armllt = { cor = 1.5 },
}

local SPATIAL_ARM = {
	armadvsol = { vMin = 0.68, vMax = 0.84 },
}

local LINE_EXCLUDE_COR = {
	corllt = { a = 23.6226, b = -6.9825, c = -11.9803 },
	corhllt = { a = 17.2151, b = -2.6811, c = -9.1859 },
}

local CIRCLE_EXCLUDE_COR = {
	corllt = { x = 0.62, y = 0.37, r = 0.16 },
}

local RESCUE_COR = {
	corllt = { x = 0.71, y = 0.665, r = 0.06 },
}

local VERT = [[
	varying vec2 texCoord;
	void main() {
		texCoord = gl_MultiTexCoord0.st;
		gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
	}
]]

local FRAG = [[
	uniform sampler2D tex0;
	uniform float targetHue;
	uniform float targetSat;
	uniform float refHueMinArm;
	uniform float refHueMaxArm;
	uniform float refHueMinCor;
	uniform float refHueMaxCor;
	uniform float refHueMinLeg;
	uniform float refHueMaxLeg;
	uniform float refHueMinScav;
	uniform float refHueMaxScav;
	uniform float satThresholdArm;
	uniform float satThresholdCor;
	uniform float satThresholdLeg;
	uniform float satThresholdScav;
	uniform float restrictArmVMin;
	uniform float restrictArmVMax;
	uniform float lineExcludeCorA;
	uniform float lineExcludeCorB;
	uniform float lineExcludeCorC;
	uniform float circleExcludeCorX;
	uniform float circleExcludeCorY;
	uniform float circleExcludeCorR;
	uniform float rescueCorX;
	uniform float rescueCorY;
	uniform float rescueCorR;
	varying vec2 texCoord;

	vec3 rgb2hsv(vec3 c) {
		vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
		vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
		vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
		float d = q.x - min(q.w, q.y);
		float e = 1.0e-10;
		return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
	}

	vec3 hsv2rgb(vec3 c) {
		vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
		vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
		return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
	}

	bool inHueBand(float hue, float lo, float hi) {
		if (lo <= hi) return hue >= lo && hue <= hi;
		return hue >= lo || hue <= hi;
	}

	void main() {
		vec4 texColor = texture2D(tex0, texCoord);
		vec3 hsv = rgb2hsv(texColor.rgb);

		bool matchArm = inHueBand(hsv.x, refHueMinArm, refHueMaxArm)
			&& hsv.y >= satThresholdArm
			&& texCoord.t >= restrictArmVMin
			&& texCoord.t <= restrictArmVMax;

		bool corLineExclude =
			(lineExcludeCorA * texCoord.s + lineExcludeCorB * texCoord.t + lineExcludeCorC) > 0.0;
		bool corCircleExclude =
			distance(texCoord, vec2(circleExcludeCorX, circleExcludeCorY)) < circleExcludeCorR;
		bool corRescue =
			distance(texCoord, vec2(rescueCorX, rescueCorY)) < rescueCorR;
		bool corExcluded = (corLineExclude || corCircleExclude) && !corRescue;

		bool matchCor = inHueBand(hsv.x, refHueMinCor, refHueMaxCor)
			&& hsv.y >= satThresholdCor
			&& !corExcluded;
		bool matchLeg = inHueBand(hsv.x, refHueMinLeg, refHueMaxLeg)
			&& hsv.y >= satThresholdLeg;
		bool matchScav = inHueBand(hsv.x, refHueMinScav, refHueMaxScav)
			&& hsv.y >= satThresholdScav;

		if (matchArm || matchCor || matchLeg || matchScav) {
			hsv.x = targetHue;
			hsv.y = targetSat;
		}
		gl_FragColor = vec4(hsv2rgb(hsv), texColor.a);
	}
]]

local function colorKey(teamID)
	local r, g, b = Spring.GetTeamColor(teamID)
	if not r then return nil end
	local ri = math.floor(math.max(0, math.min(1, r)) * 255 + 0.5)
	local gi = math.floor(math.max(0, math.min(1, g)) * 255 + 0.5)
	local bi = math.floor(math.max(0, math.min(1, b)) * 255 + 0.5)
	return ri .. ":" .. gi .. ":" .. bi, r, g, b
end

local function hsvTarget(r, g, b)
	local mx = math.max(r, g, b)
	local mn = math.min(r, g, b)
	local d = mx - mn
	if d <= 0.02 then return nil, nil end
	local h
	if mx == r then
		h = ((g - b) / d) % 6
	elseif mx == g then
		h = (b - r) / d + 2
	else
		h = (r - g) / d + 4
	end
	return h / 6, (mx <= 0.00001 and 0 or d / mx)
end

local function cacheKey(unitDefID, teamID)
	local ck, r, g, b = colorKey(teamID)
	if not ck then return nil end
	return tostring(unitDefID) .. "@" .. ck, r, g, b
end

local function setUnitOverrides(unitDefID)
	local satArm, satCor, satLeg, satScav = SAT_DEFAULT, SAT_DEFAULT, SAT_DEFAULT, SAT_DEFAULT
	local vMin, vMax = 0.0, 1.0
	local lineA, lineB, lineC = 0.0, 0.0, -1.0
	local circleX, circleY, circleR = 0.0, 0.0, 0.0
	local rescueX, rescueY, rescueR = 0.0, 0.0, 0.0

	local def = UnitDefs[unitDefID]
	local name = def and def.name
	if name then
		local o = SAT_OVERRIDES[name]
		if o then
			satArm = o.arm or satArm
			satCor = o.cor or satCor
			satLeg = o.leg or satLeg
			satScav = o.scav or satScav
		end
		local s = SPATIAL_ARM[name]
		if s then vMin, vMax = s.vMin, s.vMax end
		local l = LINE_EXCLUDE_COR[name]
		if l then lineA, lineB, lineC = l.a, l.b, l.c end
		local c = CIRCLE_EXCLUDE_COR[name]
		if c then circleX, circleY, circleR = c.x, c.y, c.r end
		local r = RESCUE_COR[name]
		if r then rescueX, rescueY, rescueR = r.x, r.y, r.r end
	end

	shader:SetUniform("satThresholdArm", satArm)
	shader:SetUniform("satThresholdCor", satCor)
	shader:SetUniform("satThresholdLeg", satLeg)
	shader:SetUniform("satThresholdScav", satScav)
	shader:SetUniform("restrictArmVMin", vMin)
	shader:SetUniform("restrictArmVMax", vMax)
	shader:SetUniform("lineExcludeCorA", lineA)
	shader:SetUniform("lineExcludeCorB", lineB)
	shader:SetUniform("lineExcludeCorC", lineC)
	shader:SetUniform("circleExcludeCorX", circleX)
	shader:SetUniform("circleExcludeCorY", circleY)
	shader:SetUniform("circleExcludeCorR", circleR)
	shader:SetUniform("rescueCorX", rescueX)
	shader:SetUniform("rescueCorY", rescueY)
	shader:SetUniform("rescueCorR", rescueR)
end

local function drawGenerationQuad()
	-- RenderToTexture-backed textures come back vertically inverted when sent
	-- through BAR's normal buildpic draw path. Deliberately render the source
	-- upside-down here so the cached result is upright when later sampled by
	-- FlowUI.Draw.Unit.
	gl.TexCoord(0, 0); gl.Vertex(0, 0, 0)
	gl.TexCoord(1, 0); gl.Vertex(CACHE_SIZE, 0, 0)
	gl.TexCoord(1, 1); gl.Vertex(CACHE_SIZE, CACHE_SIZE, 0)
	gl.TexCoord(0, 1); gl.Vertex(0, CACHE_SIZE, 0)
end

local function generate(job)
	if not shader then return nil end

	local hue, sat = hsvTarget(job.r, job.g, job.b)
	if not hue then
		return false
	end

	local tex = gl.CreateTexture(CACHE_SIZE, CACHE_SIZE, {
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = true,
	})
	if not tex then return nil end

	local source = "#" .. job.unitDefID
	local ok = pcall(function()
		gl.RenderToTexture(tex, function()
			gl.Clear(GL.COLOR_BUFFER_BIT, 0, 0, 0, 0)
			gl.MatrixMode(GL.PROJECTION)
			gl.PushMatrix()
			gl.LoadIdentity()
			gl.Ortho(0, CACHE_SIZE, 0, CACHE_SIZE, -1, 1)
			gl.MatrixMode(GL.MODELVIEW)
			gl.PushMatrix()
			gl.LoadIdentity()

			gl.Blending(false)
			gl.Color(1, 1, 1, 1)
			gl.Texture(source)
			shader:Activate()
			shader:SetUniform("targetHue", hue)
			shader:SetUniform("targetSat", sat)
			setUnitOverrides(job.unitDefID)
			gl.BeginEnd(GL.QUADS, drawGenerationQuad)
			shader:Deactivate()
			gl.Texture(false)
			gl.Blending(true)

			gl.MatrixMode(GL.MODELVIEW)
			gl.PopMatrix()
			gl.MatrixMode(GL.PROJECTION)
			gl.PopMatrix()
			gl.MatrixMode(GL.MODELVIEW)
		end)
	end)

	if not ok then
		gl.DeleteTexture(tex)
		return nil
	end
	return tex
end

local function request(unitDefID, teamID)
	if not unitDefID or not UnitDefs[unitDefID] then return nil end
	teamID = teamID or Spring.GetLocalTeamID()

	local key, r, g, b = cacheKey(unitDefID, teamID)
	if not key then return nil end

	if cache[key] then
		return cache[key]
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
	local count = math.min(GENERATE_PER_FRAME, #queue)
	for _ = 1, count do
		local job = table.remove(queue, 1)
		if job then
			queued[job.key] = nil
			if not cache[job.key] then
				local tex = generate(job)
				if tex then
					cache[job.key] = tex
				end
			end
		end
	end
end

function widget:Initialize()
	if not gl.LuaShader or not WG.FlowUI or not WG.FlowUI.Draw or type(WG.FlowUI.Draw.Unit) ~= "function" then
		widgetHandler:RemoveWidget()
		return
	end

	shader = gl.LuaShader({
		vertex = VERT,
		fragment = FRAG,
		uniformInt = { tex0 = 0 },
		uniformFloat = {
			targetHue = 0,
			targetSat = 0,
			refHueMinArm = HUE_MIN_ARM,
			refHueMaxArm = HUE_MAX_ARM,
			refHueMinCor = HUE_MIN_COR,
			refHueMaxCor = HUE_MAX_COR,
			refHueMinLeg = HUE_MIN_LEG,
			refHueMaxLeg = HUE_MAX_LEG,
			refHueMinScav = HUE_MIN_SCAV,
			refHueMaxScav = HUE_MAX_SCAV,
			satThresholdArm = SAT_DEFAULT,
			satThresholdCor = SAT_DEFAULT,
			satThresholdLeg = SAT_DEFAULT,
			satThresholdScav = SAT_DEFAULT,
			restrictArmVMin = 0.0,
			restrictArmVMax = 1.0,
			lineExcludeCorA = 0.0,
			lineExcludeCorB = 0.0,
			lineExcludeCorC = -1.0,
			circleExcludeCorX = 0.0,
			circleExcludeCorY = 0.0,
			circleExcludeCorR = 0.0,
			rescueCorX = 0.0,
			rescueCorY = 0.0,
			rescueCorR = 0.0,
		},
	}, "CachedNativeBuildPicTeamColor")

	if not shader:Initialize() then
		shader = nil
		widgetHandler:RemoveWidget()
		return
	end

	originalDrawUnit = WG.FlowUI.Draw.Unit
	wrappedDrawUnit = function(
		px, py, sx, sy, cs, tl, tr, br, bl, zoom,
		borderSize, borderOpacity, texture, radarTexture, groupTexture,
		price, queueCount
	)
		local drawTexture = texture
		if type(texture) == "string" then
			local unitDefID = tonumber(string.match(texture, "^#(%d+)$"))
			if unitDefID then
				drawTexture = request(unitDefID, Spring.GetLocalTeamID()) or texture
			end
		end

		return originalDrawUnit(
			px, py, sx, sy, cs, tl, tr, br, bl, zoom,
			borderSize, borderOpacity, drawTexture, radarTexture, groupTexture,
			price, queueCount
		)
	end

	WG.FlowUI.Draw.Unit = wrappedDrawUnit
	WG.TeamColorBuildPics = {
		GetTexture = request,
	}
	Spring.Echo("[Team Color BuildPics] cached native buildpic generator installed")
end

function widget:DrawGenesis()
	processQueue()
end

function widget:Shutdown()
	if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Unit == wrappedDrawUnit then
		WG.FlowUI.Draw.Unit = originalDrawUnit
	end
	WG.TeamColorBuildPics = nil

	for key, tex in pairs(cache) do
		gl.DeleteTexture(tex)
		cache[key] = nil
	end
	for key in pairs(queued) do queued[key] = nil end
	for i = #queue, 1, -1 do queue[i] = nil end

	if shader then
		shader:Finalize()
		shader = nil
	end
end
