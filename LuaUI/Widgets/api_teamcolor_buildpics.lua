local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Team Color BuildPics",
		desc = "Uses cached 3D-generated unit portraits in BAR's native build menu",
		author = "RandomGuyJunior",
		date = "2026-10-04",
		license = "GNU GPL, v2 or later",
		layer = 0.5,
		enabled = true,
		handler = true,
	}
end

local originalDrawUnit
local wrappedDrawUnit
local lastRevision = -1

local function portraitAPI()
	return WG.TeamColorUnitPics
end

local function request(unitDefID, teamID)
	local api = portraitAPI()
	if not api or not api.GetTexture then
		return nil
	end
	return api.GetTexture(unitDefID, teamID or Spring.GetLocalTeamID())
end

local function refreshBuildMenu()
	if WG.buildmenu
			and WG.buildmenu.getShowPrice
			and WG.buildmenu.setShowPrice
	then
		WG.buildmenu.setShowPrice(WG.buildmenu.getShowPrice())
	end
end

local function stats()
	local api = portraitAPI()
	return {
		revision = api and api.GetRevision and api.GetRevision() or -1,
		teamColorSource = api and api.GetTeamColorSource and api.GetTeamColorSource() or "unavailable",
	}
end

function widget:Initialize()
	if not WG.FlowUI or not WG.FlowUI.Draw or type(WG.FlowUI.Draw.Unit) ~= "function" then
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
				-- First frame can use BAR's native icon while the model portrait
				-- is generated. Once generated, all later draws use the cached
				-- model portrait; no native buildpic is recoloured or analysed.
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
		Invalidate = function(unitDefID)
			local api = portraitAPI()
			if api and api.Invalidate then api.Invalidate(unitDefID) end
		end,
		GetBackgroundType = function(unitDefID)
			local api = portraitAPI()
			return api and api.GetBackgroundType and api.GetBackgroundType(unitDefID) or "land"
		end,
		GetStats = stats,
	}

	local api = portraitAPI()
	lastRevision = api and api.GetRevision and api.GetRevision() or -1
	Spring.Echo("[Team Color BuildPics] using generated 3D portraits; native buildpics are fallback only")
end

function widget:DrawGenesis()
	local api = portraitAPI()
	if not api or not api.GetRevision then return end
	local revision = api.GetRevision()
	if revision ~= lastRevision then
		lastRevision = revision
		refreshBuildMenu()
	end
end

function widget:TextCommand(command)
	if command == "tcpicsstats" then
		local s = stats()
		Spring.Echo(
			"[Team Color BuildPics] revision=" .. tostring(s.revision)
				.. " teamMask=" .. tostring(s.teamColorSource)
		)
		return true
	end

	local unitDefID = tonumber(string.match(command, "^tcpicsinvalidate%s+(%d+)$"))
	if unitDefID then
		local api = portraitAPI()
		if api and api.Invalidate then api.Invalidate(unitDefID) end
		Spring.Echo("[Team Color BuildPics] invalidated generated portrait " .. unitDefID)
		return true
	end
end

function widget:Shutdown()
	if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Unit == wrappedDrawUnit then
		WG.FlowUI.Draw.Unit = originalDrawUnit
	end
	WG.TeamColorBuildPics = nil
end
