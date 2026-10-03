local widget = widget ---@type Widget
function widget:GetInfo()
	return {
		name = "Team Color BuildPics Bridge",
		desc = "Applies the proven buildpic recolor pass to BAR's native build menu",
		author = "RandomGuyJunior",
		date = "2026-10-03",
		license = "GNU GPL, v2 or later",
		layer = 0.5,
		enabled = true,
	}
end

local shader
local originalDrawUnit
local wrappedDrawUnit

local vert = [[
varying vec2 texCoord;
void main() {
	texCoord = gl_MultiTexCoord0.st;
	gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
}
]]

local frag = [[
uniform sampler2D tex0;
uniform float targetHue;
uniform float targetSat;
varying vec2 texCoord;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
	vec4 p = mix(vec4(c.bg,K.wz),vec4(c.gb,K.xy),step(c.b,c.g));
	vec4 q = mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
	float d = q.x - min(q.w,q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z+(q.w-q.y)/(6.0*d+e)),d/(q.x+e),q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K=vec4(1.0,2.0/3.0,1.0/3.0,3.0);
	vec3 p=abs(fract(c.xxx+K.xyz)*6.0-K.www);
	return c.z*mix(K.xxx,clamp(p-K.xxx,0.0,1.0),c.y);
}
bool band(float h,float lo,float hi) {
	return lo<=hi ? (h>=lo && h<=hi) : (h>=lo || h<=hi);
}
void main() {
	vec4 t=texture2D(tex0,texCoord);
	vec3 h=rgb2hsv(t.rgb);
	bool match =
		(band(h.x,0.50,0.66) ||
		 band(h.x,0.95,0.035) ||
		 band(h.x,0.27,0.44) ||
		 band(h.x,0.68,0.90)) && h.y>=0.30;
	if (match) {
		h.x=targetHue;
		h.y=targetSat;
		gl_FragColor=vec4(hsv2rgb(h),t.a);
	} else {
		gl_FragColor=vec4(0.0);
	}
}
]]

local function hsvTarget(r,g,b)
	local mx=math.max(r,g,b)
	local mn=math.min(r,g,b)
	local d=mx-mn
	if d<=0.02 then return nil,nil end
	local h
	if mx==r then h=((g-b)/d)%6
	elseif mx==g then h=(b-r)/d+2
	else h=(r-g)/d+4 end
	return h/6,(mx<=0.00001 and 0 or d/mx)
end

local function overlay(px,py,sx,sy,cs,tl,tr,br,bl,zoom,texture)
	local r,g,b=Spring.GetTeamColor(Spring.GetLocalTeamID())
	local hue,sat=hsvTarget(r,g,b)
	if not hue then return end
	gl.Blending(GL.SRC_ALPHA,GL.ONE_MINUS_SRC_ALPHA)
	gl.Color(1,1,1,1)
	gl.Texture(texture)
	shader:Activate()
	shader:SetUniform("targetHue",hue)
	shader:SetUniform("targetSat",sat)
	gl.BeginEnd(
		GL.QUADS,WG.FlowUI.Draw.TexRectRound,
		px,py,sx,sy,cs,tl,tr,br,bl,(zoom or 0)+0.02
	)
	shader:Deactivate()
	gl.Texture(false)
end

function widget:Initialize()
	if not gl.LuaShader or not WG.FlowUI or not WG.FlowUI.Draw then
		widgetHandler:RemoveWidget()
		return
	end
	shader=gl.LuaShader({
		vertex=vert,
		fragment=frag,
		uniformInt={tex0=0},
		uniformFloat={targetHue=0,targetSat=0},
	},"NativeBuildPicTeamColor")
	if not shader:Initialize() then
		shader=nil
		widgetHandler:RemoveWidget()
		return
	end

	originalDrawUnit=WG.FlowUI.Draw.Unit
	wrappedDrawUnit=function(
		px,py,sx,sy,cs,tl,tr,br,bl,zoom,
		borderSize,borderOpacity,texture,radarTexture,groupTexture,
		price,queueCount
	)
		originalDrawUnit(
			px,py,sx,sy,cs,tl,tr,br,bl,zoom,
			borderSize,borderOpacity,texture,radarTexture,groupTexture,
			price,queueCount
		)
		if borderOpacity~=0 and type(texture)=="string" and string.match(texture,"^#%d+$") then
			overlay(px,py,sx,sy,cs,tl,tr,br,bl,zoom,texture)
		end
	end
	WG.FlowUI.Draw.Unit=wrappedDrawUnit
	Spring.Echo("[Team Color BuildPics] native DDS recolor bridge installed")
end

function widget:Shutdown()
	if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Unit==wrappedDrawUnit then
		WG.FlowUI.Draw.Unit=originalDrawUnit
	end
	if shader then shader:Finalize() end
end
