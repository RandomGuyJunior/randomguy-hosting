local widget = widget ---@type Widget

-- LOCAL MOD (2026-09-27): this is a MODIFIED COPY of BAR's own bundled
-- "Info" widget (the selected-unit/build-info panel -- name, DPS, range,
-- portrait, etc), saved under its OWN distinct filename
-- (gui_info_teamcolor.lua) and its OWN distinct GetInfo().name, same
-- reasoning as this project's earlier gui_gridmenu_teamcolor.lua fork: BAR's
-- widget loader discovers every widget file across every mount and errors
-- with "duplicate name" if two report the same GetInfo().name, so this
-- widget explicitly disables the real "Info" widget from its own
-- widget:Initialize() instead of trying to reuse its identity.
--
-- Why this file needed forking too: the Grid Menu fork (gui_gridmenu_
-- teamcolor.lua) only recolors the build-menu icon grid. This "Info" widget
-- separately draws the big selected-unit portrait (and the small multi-
-- select icon row) shown in the bottom-left panel, using the EXACT SAME
-- flat unitpics/*.dds texture + WG.FlowUI.Draw.Unit drawing helper as the
-- grid menu icons -- confirmed by reading this file's drawUnitInfo() and
-- drawSelectionCell() functions directly. So it needs the identical
-- selective hue-shift shader treatment, just inserted at its own two
-- UiUnit(...) call sites instead of gridmenu's one. See the "LOCAL MOD"
-- section further down (right before widget:Initialize()) for the actual
-- shader code -- it's the same shader/band logic as gui_gridmenu_teamcolor.lua,
-- duplicated here rather than shared, since each BAR widget is a separate
-- file with its own private global environment (no cross-widget require()
-- convention already exists in this project to share it another way).
-- Everything else in this file is untouched from upstream -- diff against
-- beyond-all-reason/Beyond-All-Reason's own luaui/Widgets/gui_info.lua to
-- see exactly what changed.

function widget:GetInfo()
	return {
		name = "Info (Team Color)",
		desc = "Selected-unit info panel with team-color icon recolor (local mod, replaces stock Info widget)",
		author = "Floris (original); team-color recolor local mod by Armis71",
		date = "April 2020 (recolor mod added 2026-09-27)",
		license = "GNU GPL, v2 or later",
		layer = 1,
		enabled = true,
		handler = true, -- required for widgetHandler:IsWidgetKnown/:DisableWidgetRaw below;
		-- stock gui_info.lua never declared this since it never called those
		-- (it doesn't manage other widgets) -- every BAR widget that DOES call
		-- them also sets this, confirmed by grepping the whole upstream repo.
		-- Without it, widgetHandler is a restricted proxy that doesn't expose
		-- those methods at all (nil), which is exactly the runtime error this fixes.
	}
end

local alwaysShow = false

local width = 0
local height = 0

local zoomMult = 1.5
local defaultCellZoom = 0 * zoomMult
local rightclickCellZoom = 0.065 * zoomMult
local clickCellZoom = 0.065 * zoomMult
local hoverCellZoom = 0.03 * zoomMult
local showBuilderBuildlist = true
local displayMapPosition = false
local activeCmdID

local emptyInfo = false
local showEngineTooltip = false -- straight up display old engine delivered text

local iconTypes = require("gamedata/icontypes")
local weaponInfo = require("common/weapons")

local vsx, vsy = Spring.GetViewGeometry()

local hoverType, hoverData = "", ""
local customHoverType, customHoverData = nil, nil -- For external widgets (like PIP) to supply hover info
local sound_button = "LuaUI/Sounds/buildbar_add.wav"
local sound_button2 = "LuaUI/Sounds/buildbar_rem.wav"

local ui_scale = tonumber(Spring.GetConfigFloat("ui_scale", 1) or 1)

---@type ScreenRect
local backgroundRect = { 0, 0, 0, 0 }
local currentTooltip = ""
local lastUpdateClock = 0
local infoShows = false
local isPregame

local tooltipTitleColor = "\255\205\255\205"
local tooltipTextColor = "\255\255\255\255"
local tooltipLabelTextColor = "\255\200\200\200"
local tooltipDarkTextColor = "\255\133\133\133"
local tooltipValueColor = "\255\255\255\255"
local tooltipValueWhiteColor = "\255\255\255\255"
local tooltipValueYellowColor = "\255\253\192\76"

-- Cache frequently used color strings
local cachedColorStrings = {
	white = "\255\233\233\233",
	grey = "\255\215\215\215",
}

local selectionHowto = tooltipTextColor
	.. "Left click"
	.. tooltipLabelTextColor
	.. ": Select\n "
	.. tooltipTextColor
	.. "   + CTRL"
	.. tooltipLabelTextColor
	.. ": Select units of this type on map\n "
	.. tooltipTextColor
	.. "   + ALT"
	.. tooltipLabelTextColor
	.. ": Select 1 single unit of this unit type\n "
	.. tooltipTextColor
	.. "Right click"
	.. tooltipLabelTextColor
	.. ": Remove\n "
	.. tooltipTextColor
	.. "    + CTRL"
	.. tooltipLabelTextColor
	.. ": Remove only 1 unit from that unit type\n "
	.. tooltipTextColor
	.. "Middle click"
	.. tooltipLabelTextColor
	.. ": Move to center location\n "
	.. tooltipTextColor
	.. "    + CTRL"
	.. tooltipLabelTextColor
	.. ": Move to center off whole selection"

local anonymousName = "?????"

local dlistGuishader, bgpadding, ViewResizeUpdate, texOffset, displayMode
local loadedFontSize, font, font2, font2, cfgDisplayUnitID, cfgDisplayUnitDefID, rankTextures
local cellRect, cellPadding, cornerSize, cellsize, cellHovered
local gridHeight, selUnitsSorted, selUnitsCounts, selectionCells, customInfoArea, contentPadding
local displayUnitID, displayUnitDefID, doUpdateClock
local contentWidth, bfcolormap, selUnitTypes

local RectRound, UiElement, UiUnit, elementCorner

local spGetCurrentTooltip = Spring.GetCurrentTooltip
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetSelectedUnitsCounts = Spring.GetSelectedUnitsCounts
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount
local SelectedUnitsCount = Spring.GetSelectedUnitsCount()
local selectedUnits = Spring.GetSelectedUnits()
local spGetUnitDefID = Spring.GetUnitDefID
local spGetFeatureDefID = Spring.GetFeatureDefID
local spTraceScreenRay = Spring.TraceScreenRay
local spGetMouseState = Spring.GetMouseState
local spGetModKeyState = Spring.GetModKeyState
local spSelectUnitArray = Spring.SelectUnitArray
local spGetTeamUnitsSorted = Spring.GetTeamUnitsSorted
local spSelectUnitMap = Spring.SelectUnitMap
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitResources = Spring.GetUnitResources
local spGetUnitExperience = Spring.GetUnitExperience
local spGetUnitWeaponState = Spring.GetUnitWeaponState
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spColorString = BAR.Utilities.Color.ToString

local math_floor = math.floor
local math_ceil = math.ceil
local math_min = math.min
local math_max = math.max
local math_isInRect = math.isInRect
local string_lines = string.lines

local os_clock = os.clock

local myTeamID = Spring.GetLocalTeamID()
local mySpec = Spring.GetSpectatingState()

local GL_QUADS = GL.QUADS
local glTexture = gl.Texture
local glTexRect = gl.TexRect
local glColor = gl.Color
local glBlending = gl.Blending
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA
local GL_ONE = GL.ONE

local hideBuildlist

-- Reverse armor type table
local armorIndex = {}
for ii = 1, #Game.armorTypes do
	armorIndex[Game.armorTypes[ii]] = ii
end

local function round(value, numDecimalPlaces)
	if type(numDecimalPlaces) ~= "number" then
		numDecimalPlaces = 0
	end
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		local rounded = math.round(value, numDecimalPlaces)
		if rounded == rounded and rounded > -math.huge and rounded < math.huge then
			return string.format("%0." .. numDecimalPlaces .. "f", rounded)
		end
	end
	return 0
end

local unitDefInfo = {}
local unitRestricted = {}
local isWaterUnit = {}
local isGeothermalUnit = {}

-- Cache frequently used translated strings
local cachedTranslations = {}
local function getCachedTranslation(key)
	if not cachedTranslations[key] then
		cachedTranslations[key] = BAR.I18N(key)
	end
	return cachedTranslations[key]
end

-- String buffer for concatenation to reduce allocations
local stringBuffer = {}
local function clearStringBuffer()
	for i = #stringBuffer, 1, -1 do
		stringBuffer[i] = nil
	end
end

-- Reusable tables to reduce allocations in hot paths
local rightMouseButtonMap = {}
local emptyTable = {}
local shiftTable = { "shift" }
local unloadParams = { 0, 0, 0, 0 } -- x, y, z, unitID
local viewSelectionCmd = { "viewselection" }
local selectionUnitpicWarm = { warmed = {}, queued = {}, queuedSet = {}, candidateSet = {}, count = 0 }
local selectionUnitpicWarmPerFrame = 1

local showWeaponGroups = { ["0"] = true, ["1"] = true } -- <0:=fake weapons, 0:=always active, 1:=primary set, >1:=alternate sets

local function refreshUnitInfo()
	local builderTraits = {
		canBuild = function(def)
			return def.isFactory or next(def.buildOptions) ~= nil
		end,
		canAssist = function(def)
			return not def.isFactory and def.canAssist
		end,
		canCapture = function(def)
			return not def.isFactory and def.canCapture and def.buildDistance > 0
		end,
		canReclaim = function(def)
			return not def.isFactory and def.canReclaim and def.buildDistance > 0
		end,
		canRepair = function(def)
			return not def.isFactory and def.canRepair and def.buildDistance > 0
		end,
		canRestore = function(def)
			return not def.isFactory and def.canRestore and def.buildDistance > 0
		end,
	}
	local function hasBuilderTrait(def)
		for trait, check in pairs(builderTraits) do
			if check(def) then
				return true
			end
		end
		return false
	end

	for unitDefID, unitDef in pairs(UnitDefs) do
		unitDefInfo[unitDefID] = {}

		if unitDef.iconType and iconTypes[unitDef.iconType] and iconTypes[unitDef.iconType].bitmap then
			unitDefInfo[unitDefID].icontype = iconTypes[unitDef.iconType].bitmap
		end

		if
			unitDef.name == "armdl"
			or unitDef.name == "cordl"
			or unitDef.name == "armlance"
			or unitDef.name == "cortitan"
			or (unitDef.minWaterDepth > 0 or unitDef.modCategories.ship)
		then
			if
				not (unitDef.modCategories.hover or (unitDef.modCategories.mobile and unitDef.modCategories.canbeuw))
			then
				isWaterUnit[unitDefID] = true
			end
		end

		if unitDef.needGeo then
			isGeothermalUnit[unitDefID] = true
		end

		if unitDef.maxThisUnit == 0 then
			unitRestricted[unitDefID] = true
		end

		if unitDef.isAirUnit then
			unitDefInfo[unitDefID].airUnit = true
		end

		unitDefInfo[unitDefID].translatedHumanName = unitDef.translatedHumanName
		if unitDef.maxWeaponRange > 16 then
			unitDefInfo[unitDefID].maxWeaponRange = unitDef.maxWeaponRange
		end
		if unitDef.speed > 0 then
			if (tonumber(unitDef.customParams.speedfactorinwater or 1) or 1) == 1 then
				unitDefInfo[unitDefID].speed = round(unitDef.speed, 0)
			else
				local speed = unitDef.speed
				local speedInWater =
					math.round(speed * math.clamp(tonumber(unitDef.customParams.speedfactorinwater), 0, 1e4))
				unitDefInfo[unitDefID].speedMin = math.min(speed, speedInWater)
				unitDefInfo[unitDefID].speedMax = math.max(speed, speedInWater)
			end
		end
		if unitDef.rSpeed > 0 then
			unitDefInfo[unitDefID].reverseSpeed = round(unitDef.rSpeed, 0)
		end
		if unitDef.stealth then
			unitDefInfo[unitDefID].stealth = true
		end
		if unitDef.cloakCost and unitDef.canCloak then
			unitDefInfo[unitDefID].cloakCost = unitDef.cloakCost
			if unitDef.cloakCostMoving > unitDef.cloakCost then
				unitDefInfo[unitDefID].cloakCostMoving = unitDef.cloakCostMoving
			end
		end
		if unitDef.isTransport then
			unitDefInfo[unitDefID].transport =
				{ unitDef.transportMass, unitDef.transportSize, unitDef.transportCapacity }
		end
		if unitDef.customParams.paralyzemultiplier then
			unitDefInfo[unitDefID].paralyzeMult = tonumber(unitDef.customParams.paralyzemultiplier)
		end
		unitDefInfo[unitDefID].armorType = Game.armorTypes[unitDef.armorType or 0] or "???"

		if unitDef.sightDistance > 0 then
			unitDefInfo[unitDefID].sightDistance = unitDef.sightDistance
		end
		if unitDef.airSightDistance > 0 then
			unitDefInfo[unitDefID].airSightDistance = unitDef.airSightDistance
		end
		if unitDef.radarDistance > 0 then
			unitDefInfo[unitDefID].radarDistance = unitDef.radarDistance
		end
		if unitDef.sonarDistance > 0 then
			unitDefInfo[unitDefID].sonarDistance = unitDef.sonarDistance
		end
		if unitDef.radarDistanceJam > 0 then
			unitDefInfo[unitDefID].radarDistanceJam = unitDef.radarDistanceJam
		end
		if unitDef.sonarDistanceJam > 0 then
			unitDefInfo[unitDefID].sonarDistanceJam = unitDef.sonarDistanceJam
		end
		if unitDef.seismicDistance > 0 then
			unitDefInfo[unitDefID].seismicDistance = unitDef.seismicDistance
		end

		if unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency then
			unitDefInfo[unitDefID].metalmaker = {
				tonumber(unitDef.customParams.energyconv_capacity),
				tonumber(unitDef.customParams.energyconv_efficiency),
			}
		end

		unitDefInfo[unitDefID].description = unitDef.translatedTooltip
		unitDefInfo[unitDefID].energyCost = unitDef.energyCost
		unitDefInfo[unitDefID].metalCost = unitDef.metalCost
		unitDefInfo[unitDefID].energyStorage = unitDef.energyStorage
		unitDefInfo[unitDefID].metalStorage = unitDef.metalStorage

		unitDefInfo[unitDefID].health = unitDef.health
		unitDefInfo[unitDefID].buildTime = unitDef.buildTime
		unitDefInfo[unitDefID].buildPic = unitDef.buildPic and true or false
		if unitDef.canStockpile then
			unitDefInfo[unitDefID].canStockpile = true
		end
		if unitDef.buildSpeed > 0 and hasBuilderTrait(unitDef) then
			unitDefInfo[unitDefID].buildSpeed = unitDef.buildSpeed
		end
		if unitDef.buildOptions[1] then
			unitDefInfo[unitDefID].buildOptions = unitDef.buildOptions
		end
		if unitDef.extractsMetal > 0 then
			unitDefInfo[unitDefID].mex = true
		end
		local weapons = unitDef.weapons

		-----------------------------------------------------
		-- Utility functions for calculating weapon values --
		-----------------------------------------------------

		local function addPrimaryDPS(minDPS, maxDPS)
			unitDefInfo[unitDefID].mindps = (unitDefInfo[unitDefID].mindps or 0) + minDPS
			unitDefInfo[unitDefID].maxdps = (unitDefInfo[unitDefID].maxdps or 0) + maxDPS
		end

		local function addSecondaryDPS(minDPS, maxDPS)
			unitDefInfo[unitDefID].maxdps = (unitDefInfo[unitDefID].maxdps or 0) + maxDPS
		end

		local function calculateLaserDPS(def, damage)
			return weaponInfo.GetDamagePerSecond(def, damage)
		end

		local function calculateWeaponDPS(def, damage)
			local reloadDPS = damage * (def.salvoSize * def.projectiles) / def.reload
			local stockpileDPS = damage
				* (def.salvoSize * def.projectiles)
				/ (def.stockpile and def.stockpileTime / 30 or def.reload)
			return math_min(reloadDPS, stockpileDPS), math_max(reloadDPS, stockpileDPS)
		end

		local function calculateClusterDPS(def, damage)
			local munition = unitDef.name .. "_" .. def.customParams.cluster_def
			local cmNumber = def.customParams.cluster_number
			local cmDamage = WeaponDefNames[munition].damages[0]

			local mainDps = (def.salvoSize * def.projectiles) / def.reload * damage
			local cmunDps = (def.salvoSize * def.projectiles) / def.reload * (cmNumber * cmDamage)
			return mainDps, mainDps + cmunDps
		end

		local function calculateAreaDPS(def, damage)
			local burst = def.salvoSize * def.projectiles
			local impactDps = damage * burst / def.reload
			local areaDps = def.customParams.area_onhit_damage -- by definition
			local damageMax =
				math_max(impactDps + areaDps, areaDps * burst * def.customParams.area_onhit_time / def.reload)
			return impactDps, damageMax
		end

		local function setEnergyAndMetalCosts(def)
			if
				def.energyCost > 0
				and (not unitDefInfo[unitDefID].energyPerShot or def.energyCost > unitDefInfo[unitDefID].energyPerShot)
			then
				unitDefInfo[unitDefID].energyPerShot = def.energyCost
			end
			if
				def.metalCost > 0
				and (not unitDefInfo[unitDefID].metalPerShot or def.metalCost > unitDefInfo[unitDefID].metalPerShot)
			then
				unitDefInfo[unitDefID].metalPerShot = def.metalCost
			end
		end

		-----------------------------------------------------

		local unitExempt = false

		local function refreshUnitWeaponInfo(i, weaponDef, isPrimaryWeapon)
			unitDefInfo[unitDefID].weapons[i] = weaponDef

			if isPrimaryWeapon and weapons[i].onlyTargets.vtol then
				unitDefInfo[unitDefID].isAaUnit = true -- displays airLOS range
			end

			local addDPS = isPrimaryWeapon and addPrimaryDPS or addSecondaryDPS

			if weaponDef.interceptor ~= 0 and weaponDef.coverageRange then
				unitDefInfo[unitDefID].maxCoverage =
					math.max(unitDefInfo[unitDefID].maxCoverage or 1, weaponDef.coverageRange)
			elseif weaponDef.shieldRadius and weaponDef.shieldRadius > 0 then
				if #weapons == 1 then
					unitDefInfo[unitDefID].weapons = {}
					unitDefInfo[unitDefID].shieldOnly = true
				end
				unitDefInfo[unitDefID].shieldRange = weaponDef.shieldRadius
				unitDefInfo[unitDefID].shieldCapacity = weaponDef.shieldPower
				unitDefInfo[unitDefID].shieldRechargeRate = weaponDef.shieldPowerRegen
				unitDefInfo[unitDefID].shieldRechargeCost = weaponDef.shieldPowerRegenEnergy
			else
				if unitDef.customParams.weapons_smart_select and (weaponDef.customParams.smart_priority or weaponDef.customParams.smart_backup or weaponDef.customParams.smart_trajectory_checker) then
					unitExempt = true -- NB: I hate this thing
					if weaponDef.customParams.smart_priority then
						addDPS(calculateWeaponDPS(weaponDef, weaponDef.damages[0]))
					end
				elseif
					unitDef.customParams.evocomlvl -- use primary weapon for evolving commanders
					or unitDef.name == "armcom" -- ignore underwater secondary
					or unitDef.name == "corcom"
					or unitDef.name == "legcom"
					or unitDef.name == "corkarg" -- ignore secondary weapons, kick
					or unitDef.name == "armguard" -- ignore high-trajectory modes
					or unitDef.name == "corpun"
					or unitDef.name == "legcluster"
					or unitDef.name == "leglob"
					or unitDef.name == "legnavyfrigate"
					or unitDef.name == "armamb"
					or unitDef.name == "cortoast"
					or unitDef.name == "armvang"
				then
					unitExempt = true
					if i == 1 then --Calculating using first weapon only
						setEnergyAndMetalCosts(weaponDef)

						if weaponDef.type == "BeamLaser" then
							addDPS(calculateLaserDPS(weaponDef, weaponDef.damages[0]))
						elseif weaponDef.customParams.cluster then -- Bullets that shoot other, smaller bullets
							addDPS(calculateClusterDPS(weaponDef, weaponDef.damages[0]))
						elseif weapons[i].onlyTargets.vtol ~= nil then
							addDPS(calculateWeaponDPS(weaponDef, weaponDef.damages[armorIndex.vtol])) --Damage to air category
						else
							addDPS(calculateWeaponDPS(weaponDef, weaponDef.damages[0])) --Damage to default armor category
						end
					end
				elseif unitDef.name == "corkorg" then --excluding korstomp from dps calculation for juggernaut
					unitExempt = true
					if i == 1 then
						local defDmg
						defDmg = weaponDef.damages[0] --Damage to default armor category
						addDPS(calculateWeaponDPS(weaponDef, defDmg))
					end

					if i == 2 then
						setEnergyAndMetalCosts(weaponDef)
						addDPS(calculateLaserDPS(weaponDef, weaponDef.damages[0]))
					end

					if i == 3 then
						addDPS(calculateWeaponDPS(weaponDef, weaponDef.damages[0])) --Damage to default armor category
					end
				elseif weaponDef.customParams.area_onhit_damage and weaponDef.customParams.area_onhit_time then
					unitExempt = true
					addDPS(calculateAreaDPS(weaponDef, weaponDef.damages[0]))
				elseif weaponDef.customParams.cluster then -- Bullets that explode into other, smaller bullets
					unitExempt = true
					addDPS(calculateClusterDPS(weaponDef, weaponDef.damages[0]))
				elseif weaponDef.customParams.speceffect == "split" then -- Bullets that split into other, smaller bullets
					unitExempt = true
					local splitd = WeaponDefNames[weaponDef.customParams.speceffect_def].damages[0]
					local splitn = weaponDef.customParams.number or 1
					addDPS(calculateWeaponDPS(weaponDef, splitd * splitn))
				elseif weaponDef.customParams.spark_forkdamage then -- Lightning
					unitExempt = true
					addDPS(calculateWeaponDPS(weaponDef, weaponDef.damages[0]))
					-- Sparks cannot retarget the original unit they hit, so add them as secondary damages.
					local forkDamageRate = weaponDef.customParams.spark_forkdamage
					addSecondaryDPS(calculateWeaponDPS(weaponDef, weaponDef.damages[0] * forkDamageRate))
					if unitExempt and weaponDef.paralyzer then -- DPS => EMP
						unitDefInfo[unitDefID].minemp = unitDefInfo[unitDefID].mindps
						unitDefInfo[unitDefID].maxemp = unitDefInfo[unitDefID].maxdps
						unitDefInfo[unitDefID].mindps = nil
						unitDefInfo[unitDefID].maxdps = nil
					end
				end

				if unitDefInfo[unitDefID].mainWeapon == 0 then
					unitDefInfo[unitDefID].mainWeapon = i
					unitDefInfo[unitDefID].range = weaponDef.range
					unitDefInfo[unitDefID].reloadTime = weaponDef.customParams.dronesuesestockpile
							and weaponDef.stockpileTime
						or weaponDef.reload
				end
				if weaponDef.type == "BeamLaser" and not unitExempt then -- BeamLaser dps calc
					local defDmg

					if weapons[1].onlyTargets.vtol ~= nil then --if main weapon isn't dedicated aa, then all weapons calculate using default armor category
						defDmg = weaponDef.damages[armorIndex.vtol]
					else
						defDmg = weaponDef.damages[0]
					end

					setEnergyAndMetalCosts(weaponDef)

					if weaponDef.paralyzer ~= true then
						addDPS(calculateLaserDPS(weaponDef, defDmg))
					else
						local minemp, maxemp = calculateLaserDPS(weaponDef, weaponDef.damages[0])
						unitDefInfo[unitDefID].minemp = (unitDefInfo[unitDefID].minemp or 0) + minemp
						unitDefInfo[unitDefID].maxemp = (unitDefInfo[unitDefID].maxemp or 0) + maxemp
					end
				elseif weaponDef.paralyzer == true and unitDef.name ~= "armthor" then -- exclude thor emp missile
					local defDmg = weaponDef.damages[0] --Damage to default armor category
					local emp = math_floor(defDmg * weaponDef.salvoSize / weaponDef.reload)
					unitDefInfo[unitDefID].minemp = emp
					unitDefInfo[unitDefID].maxemp = emp
					unitDefInfo[unitDefID].range = weaponDef.range
					unitDefInfo[unitDefID].reloadTime = weaponDef.reload
				end
				if weaponDef.type ~= "BeamLaser" and weaponDef.paralyzer ~= true and not unitExempt then
					local defDmg

					if weapons[1].onlyTargets.vtol ~= nil then --if main weapon isn't dedicated aa, then all weapons calculate using default armor category
						defDmg = weaponDef.damages[armorIndex.vtol]
					else
						defDmg = weaponDef.damages[0]
					end

					if defDmg > 0 then
						addDPS(calculateWeaponDPS(weaponDef, defDmg))
						setEnergyAndMetalCosts(weaponDef)
					end
				end
			end
		end
		for i = 1, #weapons do
			if not unitDefInfo[unitDefID].weapons then
				unitDefInfo[unitDefID].weapons = {}
				unitDefInfo[unitDefID].mindps = 0
				unitDefInfo[unitDefID].maxdps = 0
				unitDefInfo[unitDefID].range = 0
				unitDefInfo[unitDefID].reloadTime = 0
				unitDefInfo[unitDefID].mainWeapon = 0
			end
			local weaponDef = WeaponDefs[weapons[i].weaponDef]
			-- Only groups 0 [always active] and 1 [primary weapon set] are aggregated.
			-- Others might be checked for abilities still, e.g. antinuke interceptors.
			if showWeaponGroups[weaponDef.customParams.weapons_group] and weaponDef.customParams.bogus ~= "1" then
				refreshUnitWeaponInfo(i, weaponDef, weaponDef.customParams.weapons_role ~= "secondary")
			end
		end
		if unitDefInfo[unitDefID].mainWeapon == 0 then
			unitDefInfo[unitDefID].mainWeapon = 1 -- All the unit's weapons were fakes.
		end

		if
			unitDef.customParams.unitgroup
			and unitDef.customParams.unitgroup == "explo"
			and unitDef.deathExplosion
			and WeaponDefNames[unitDef.deathExplosion]
		then
			local weapon = WeaponDefs[WeaponDefNames[unitDef.deathExplosion].id]
			if weapon then
				local dmg = weapon.damages[Game.armorTypes.default]
				unitDefInfo[unitDefID].mindps = dmg
				unitDefInfo[unitDefID].maxdps = dmg
				unitDefInfo[unitDefID].reloadTime = nil
			end
		end
	end

	-- Account for sub-unit damages, namely carriers and drones.
	local mins = { "mindps", "minemp" }
	local maxs = { "maxdps", "maxemp" }
	for unitDefID, unitDef in pairs(UnitDefs) do
		local unitInfo = unitDefInfo[unitDefID]
		for index, weapon in ipairs(unitDef.weapons) do
			local weaponDef = WeaponDefs[weapon.weaponDef]
			if weaponDef.customParams.carried_unit and UnitDefNames[weaponDef.customParams.carried_unit] then
				local droneCount = weaponDef.customParams.maxunits or 1
				local droneDef = UnitDefNames[weaponDef.customParams.carried_unit]
				local droneInfo = unitDefInfo[droneDef.id]

				for _, key in ipairs(mins) do
					if droneInfo[key] then
						unitInfo[key] = (unitInfo[key] or 0) -- times zero drones == zero
					end
				end

				for _, key in ipairs(maxs) do
					if droneInfo[key] then
						unitInfo[key] = (unitInfo[key] or 0) + (droneInfo[key] * droneCount)
					end
				end
			end
		end
	end

	-- Convert aggregated values to display formats last to avoid rounding errors.
	local summedKeys = { "mindps", "maxdps", "minemp", "maxemp" }
	for unitDefID, unitInfo in pairs(unitDefInfo) do
		for _, key in pairs(summedKeys) do
			if type(unitInfo[key]) == "number" then
				unitInfo[key] = math_floor(unitInfo[key])
			end
		end
	end
end

local groups, unitGroup = {}, {} -- retrieves from buildmenu in initialize
local unitOrder = {} -- retrieves from buildmenu in initialize

local function clearSelectionUnitpicWarmQueue()
	local warm = selectionUnitpicWarm
	for defID in pairs(warm.queuedSet) do
		warm.queuedSet[defID] = nil
	end
	for i = 1, warm.count do
		warm.queued[i] = nil
	end
	warm.count = 0
end

local function queueSelectionUnitpicWarm(unitDefID)
	local warm = selectionUnitpicWarm
	if unitDefID and not warm.warmed[unitDefID] and not warm.queuedSet[unitDefID] then
		warm.count = warm.count + 1
		warm.queued[warm.count] = unitDefID
		warm.queuedSet[unitDefID] = true
	end
end

local function queueSelectionUnitpicWarmFromSelection(sel)
	clearSelectionUnitpicWarmQueue()
	local warm = selectionUnitpicWarm
	local candidateSet = warm.candidateSet
	for defID in pairs(candidateSet) do
		candidateSet[defID] = nil
	end
	for i = 1, #sel do
		local unitDefID = spGetUnitDefID(sel[i])
		if unitDefID then
			candidateSet[unitDefID] = true
		end
	end
	for _, unitDefID in pairs(unitOrder) do
		if candidateSet[unitDefID] then
			queueSelectionUnitpicWarm(unitDefID)
			candidateSet[unitDefID] = nil
		end
	end
	for unitDefID in pairs(candidateSet) do
		queueSelectionUnitpicWarm(unitDefID)
		candidateSet[unitDefID] = nil
	end
end

local function flushSelectionUnitpicWarmQueue()
	local warm = selectionUnitpicWarm
	local count = warm.count
	if count <= 0 then
		return true
	end

	tracy.ZoneBeginN("W:Info:SelectionUnitpicWarmup")
	local limit = math_min(count, selectionUnitpicWarmPerFrame)
	for i = 1, limit do
		local unitDefID = warm.queued[i]
		if unitDefID then
			if glTexture("#" .. unitDefID) then
				warm.warmed[unitDefID] = true
			end
			warm.queuedSet[unitDefID] = nil
		end
	end
	glTexture(false)
	if limit < count then
		for i = limit + 1, count do
			local unitDefID = warm.queued[i]
			local newIndex = i - limit
			warm.queued[newIndex] = unitDefID
			warm.queued[i] = nil
		end
		warm.count = count - limit
	else
		for i = 1, count do
			warm.queued[i] = nil
		end
		warm.count = 0
	end
	tracy.ZoneEnd()

	return warm.count == 0
end

local unitDisabled = {}
local minWaterUnitDepth = -11
local showWaterUnits = false
local _, _, mapMinWater, _ = Spring.GetGroundExtremes()
if mapMinWater <= minWaterUnitDepth then
	showWaterUnits = true
end
-- make them a disabled unit (instead of removing it entirely)
if not showWaterUnits then
	for unitDefID, _ in pairs(isWaterUnit) do
		unitDisabled[unitDefID] = true
	end
end

local showGeothermalUnits = false
local function checkGeothermalFeatures()
	showGeothermalUnits = false
	local geoThermalFeatures = {}
	for defID, def in pairs(FeatureDefs) do
		if def.geoThermal then
			geoThermalFeatures[defID] = true
		end
	end
	local features = Spring.GetAllFeatures()
	for i = 1, #features do
		if geoThermalFeatures[Spring.GetFeatureDefID(features[i])] then
			showGeothermalUnits = true
			break
		end
	end
	-- make them a disabled unit (instead of removing it entirely)
	for unitDefID, _ in pairs(isGeothermalUnit) do
		if not showGeothermalUnits then
			unitDisabled[unitDefID] = true
		else
			if not isWaterUnit[unitDefID] or showWaterUnits then
				unitDisabled[unitDefID] = nil
			end
		end
	end
end

local function checkGuishader(force)
	tracy.ZoneBeginN("W:Info:CheckGuishader")
	dlistGuishader = WG.FlowUI.guishaderCheckDlist(dlistGuishader, "info", function()
		RectRound(backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4], elementCorner, 0, 1, 0, 0)
	end, force)
	tracy.ZoneEnd()
end

function widget:PlayerChanged(playerID)
	myTeamID = Spring.GetLocalTeamID()
	mySpec = Spring.GetSpectatingState()
end

function widget:ViewResize()
	tracy.ZoneBeginN("W:Info:ViewResize")
	ViewResizeUpdate = true

	vsx, vsy = Spring.GetViewGeometry()

	width = 0.2125
	height = 0.14 * ui_scale
	width = width / (vsx / vsy) * 1.78 -- make smaller for ultrawide screens
	width = width * ui_scale
	-- make pixel aligned
	height = math_floor(height * vsy) / vsy
	width = math_floor(width * vsx) / vsx

	bgpadding = WG.FlowUI.elementPadding
	elementCorner = WG.FlowUI.elementCorner

	RectRound = WG.FlowUI.Draw.RectRound
	UiElement = WG.FlowUI.Draw.Element
	UiUnit = WG.FlowUI.Draw.Unit

	backgroundRect = { 0, 0, width * vsx, height * vsy }

	doUpdate = true
	if infoBgTex then
		gl.DeleteTexture(infoBgTex)
		infoBgTex = nil
	end
	if infoTex then
		gl.DeleteTexture(infoTex)
		infoTex = nil
	end

	checkGuishader(true)

	font, loadedFontSize = WG.fonts.getFont()
	font2 = WG.fonts.getFont(2)
	tracy.ZoneEnd()
end

function GetColor(colormap, slider)
	local coln = #colormap
	if slider >= 1 then
		local col = colormap[coln]
		return col[1], col[2], col[3], col[4]
	end
	if slider < 0 then
		slider = 0
	elseif slider > 1 then
		slider = 1
	end
	local posn = 1 + (coln - 1) * slider
	local iposn = math_floor(posn)
	local aa = posn - iposn
	local ia = 1 - aa

	local col1, col2 = colormap[iposn], colormap[iposn + 1]

	return col1[1] * ia + col2[1] * aa,
		col1[2] * ia + col2[2] * aa,
		col1[3] * ia + col2[3] * aa,
		col1[4] * ia + col2[4] * aa
end

function widget:GameFrame()
	isPregame = false
	if checkGeothermalFeatures then
		checkGeothermalFeatures()
		checkGeothermalFeatures = nil
		-- LOCAL MOD (2026-09-27): stock gui_info.lua used the single-arg
		-- widgetHandler:RemoveCallIn("GameFrame") shorthand, which only
		-- exists on the RESTRICTED per-widget widgetHandler proxy that
		-- ordinary widgets (without handler=true) receive. Adding
		-- handler=true above (needed for IsWidgetKnown/DisableWidgetRaw in
		-- widget:Initialize()) swaps this widget over to the full/raw
		-- widgetHandler object instead, which doesn't have that implicit-
		-- self shorthand -- it needs the callin name AND an explicit widget
		-- reference, same convention confirmed in gui_buildmenu.lua (another
		-- stock BAR widget with handler=true): widgetHandler:
		-- RemoveWidgetCallIn(name, widgetInstance).
		widgetHandler:RemoveWidgetCallIn("GameFrame", self)
	end
end

-------------------------------------------------------------------------------
--- LOCAL MOD (2026-09-27): team-color icon recolor
-------------------------------------------------------------------------------
-- Same technique and the same three faction hue bands as
-- gui_gridmenu_teamcolor.lua's own "LOCAL MOD" section (see that file for
-- the full sampling methodology that derived these bands from real shipped
-- unitpics/*.dds icons) -- duplicated here rather than shared, since each
-- widget is its own file with its own private global environment.
--
-- Fails safe: if gl.LuaShader isn't available, or the shader doesn't
-- compile, this feature silently does nothing -- the real info panel below
-- is completely unaffected either way.
--
-- NOTE ON `local`: same reasoning as gui_gridmenu_teamcolor.lua -- these are
-- genuine Lua GLOBALS (no `local` keyword), both to sidestep Lua 5.1's
-- 200-local-per-main-chunk ceiling on a file already this size, and because
-- each widget's own private global environment table means this can't
-- collide with another widget's globals -- confirmed via grep against this
-- file that none of these names (TEAMCOLOR_RECOLOR_*, teamColorRecolor*,
-- rgbToHue, DrawTeamColorRecolor) were already in use here.

TEAMCOLOR_RECOLOR_ENABLED = true -- flip to false to disable without deleting any code

-- TEMP DIAGNOSTIC (2026-09-28): flip to true to visualize which pixels the
-- shader's hue/saturation gate is actually matching on a live icon, instead
-- of guessing from offline pixel sampling. When on, every pixel that FAILS
-- the matchArm/matchCor/matchLeg test is drawn as opaque magenta/cyan
-- (instead of fully transparent) wherever the source icon itself is opaque
-- -- so a real in-game screenshot shows exactly what this shader thinks is
-- or isn't "trim". This is how the too-narrow Legion hue band (see
-- TEAMCOLOR_RECOLOR_HUE_MAX_LEG below) was actually found and confirmed --
-- left in place, defaulted off, in case the band needs further tuning later.
TEAMCOLOR_RECOLOR_DEBUG_MASK = false

-- TEMP DIAGNOSTIC (2026-09-28, armadvsol spatial-restriction orientation):
-- flip to true to visualize texCoord.t directly instead of any hue/saturation
-- match -- every icon's pixels are painted RED (top third of the drawn icon,
-- texCoord.t > 0.667), GREEN (middle third), or BLUE (bottom third),
-- bypassing all normal recolor logic entirely. Needed because two rounds of
-- guessing armadvsol's restrictArmVMin/VMax window (see
-- TEAMCOLOR_RECOLOR_SPATIAL_RESTRICT below) both produced wrong or
-- inconclusive live results -- this settles, from one screenshot, exactly
-- which physical part of an icon (as actually rendered on screen) corresponds
-- to which texCoord.t range, removing the guesswork.
--
-- RESULT (2026-09-28): confirmed via a live screenshot of the small info-card
-- icon -- screen-top showed BLUE (low t), screen-bottom showed RED (high t).
-- The mapping is DIRECT (t = row_norm of the source DDS, no flip); see the
-- corrected armadvsol window above. Turned back off now that its job is
-- done, left in place in case another icon needs the same diagnosis later.
TEAMCOLOR_RECOLOR_DEBUG_VCOORD = false

-- TEMP DIAGNOSTIC (2026-09-28, corllt/corhllt horizontal-restriction
-- orientation): flip to true to visualize texCoord.s directly instead of any
-- hue/saturation match -- every icon's pixels are painted RED (screen-right
-- third, texCoord.s > 0.667), GREEN (middle third), or BLUE (screen-left
-- third), bypassing all normal recolor logic entirely. Needed because
-- TexRectRound's x-coordinate formula (xNorm = (x - px) * invWidth, no "1 -"
-- flip) is structurally different from its y-coordinate one (which DID have
-- a "1 -" flip and yet still turned out to map directly) -- so the confirmed
-- vertical result above does not by itself prove the horizontal direction.
--
-- RESULT (2026-09-28): confirmed via a live screenshot -- screen-left showed
-- BLUE (low s), screen-right showed RED (high s), exactly matching the
-- shader's original, un-flipped assumption. The mapping is DIRECT, same as
-- texCoord.t. This means the earlier "flip" correction applied to
-- corllt/corhllt's hMin/hMax window (see the old TEAMCOLOR_RECOLOR_SPATIAL_
-- RESTRICT comment, now superseded below) was chasing the wrong theory --
-- the real problem was never axis orientation, see the
-- TEAMCOLOR_RECOLOR_LINE_EXCLUDE comment below for what it actually was.
-- Turned back off now that its job is done, left in place for future use.
TEAMCOLOR_RECOLOR_DEBUG_HCOORD = false

-- TEMP DIAGNOSTIC (2026-09-28, corllt/corhllt beam-vs-trim boundary): see the
-- debugCorMaskMode uniform comment in the fragment shader above. Flip to
-- true to overlay magenta on every pixel the current matchCor condition
-- (hue, sat, and whatever spatial restriction is live) still lets recolor,
-- on the real live-rendered icon.
--
-- RESULT (2026-09-28): with the (already-flipped) hMin/hMax box live, this
-- showed the icon almost ENTIRELY solid magenta -- the box was barely
-- restricting anything, confirming the flip fix never worked. Real pixel
-- extraction + connected-component clustering (see TEAMCOLOR_RECOLOR_LINE_
-- EXCLUDE below) showed why: the false-positive beam/blast region and the
-- legitimate trim region overlap on BOTH texCoord axes, so no axis-aligned
-- box (in either direction) can separate them -- a diagonal cut is needed.
-- Turned back off now that the box has been replaced by a line-exclude test;
-- left in place for future troubleshooting.
TEAMCOLOR_RECOLOR_DEBUG_CORMASK = false

-- Armada: default cyan-blue trim.
TEAMCOLOR_RECOLOR_HUE_MIN_ARM = 0.50
TEAMCOLOR_RECOLOR_HUE_MAX_ARM = 0.66

-- Cortex: default red trim. Wraps through hue 0/1.
TEAMCOLOR_RECOLOR_HUE_MIN_COR = 0.95
TEAMCOLOR_RECOLOR_HUE_MAX_COR = 0.035

-- Legion: default green trim.
-- LOCAL MOD (2026-09-28, band-width fix): MAX was 0.37, which turned out to
-- cut the band off right before the trim's own densest, most saturated
-- region. Direct pixel analysis of the live legafus.dds (pulled straight out
-- of the game's asset pool, not a guess) showed a huge, highly-saturated
-- cluster (median sat 0.6-0.9) sitting at hue 0.34-0.40, mostly ABOVE the
-- old 0.37 ceiling -- confirmed in-game via a magenta/cyan debug overlay:
-- EVERY Legion unit's icon was landing 100% outside the hue band (all
-- magenta, zero cyan), not merely under-saturated. Widened to 0.44 to cover
-- that whole cluster with margin; still well clear of Armada's band (starts
-- at 0.50), so there's no new collision risk.
TEAMCOLOR_RECOLOR_HUE_MIN_LEG = 0.27
TEAMCOLOR_RECOLOR_HUE_MAX_LEG = 0.44

-- Scavengers: default purple trim.
-- LOCAL MOD (2026-09-28, new band): user reported "Scav Epic Fusion Reactor"
-- (armafust3_scav, i.e. the Scavenger-side clone of the Armada Adv Fusion
-- Reactor, built via a runtime unit-duplication gadget for the "_scav"
-- variant) showing its stock purple trim in the info panel instead of the
-- player's own team color, even though its real 3D battlefield model
-- correctly showed team color. Investigated via the same real-asset-pool
-- extraction methodology as the Legion band-width fix: the "_scav" variant
-- of a unit does NOT reuse the plain faction buildpic (e.g. ARMAFUS.DDS) --
-- the shipped archive also carries a wholly separate, Scavenger-specific
-- buildpic per unit at unitpics/scavengers/<name>.dds (armafust3.dds,
-- corafust3.dds, legafust3.dds all confirmed present as distinct files/md5s
-- from their plain-faction counterparts), and it's THAT file the recolor
-- shader actually samples for a "_scav"-suffixed unitDefID. Pulled and
-- histogrammed all three real unitpics/scavengers/*.dds files: despite
-- coming from three different faction models, all three share one common,
-- highly-saturated purple accent cluster (median hue 0.78-0.82, i.e. this is
-- a single shared "this is Scavenger tech" palette applied uniformly across
-- factions, not a per-faction color) -- confirming this needed a genuinely
-- new 4th band, not a widening of any existing one. Set with margin to cover
-- the 5th-95th percentile hue range measured across all three real assets
-- (armafust3_scav ~0.70-0.84, corafust3_scav ~0.75-0.88, legafust3_scav
-- ~0.75-0.78), while staying clear of Armada's band (ends at 0.66) and
-- Cortex's band (starts at 0.95).
TEAMCOLOR_RECOLOR_HUE_MIN_SCAV = 0.68
TEAMCOLOR_RECOLOR_HUE_MAX_SCAV = 0.90

TEAMCOLOR_RECOLOR_SAT_THRESHOLD = 0.30 -- ignore low-saturation pixels (grays/whites/blacks/shadows)

teamColorRecolorShader = nil

teamColorRecolorVertexShader = [[
	varying vec2 texCoord;
	void main() {
		texCoord = gl_MultiTexCoord0.st;
		gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
	}
]]

teamColorRecolorFragmentShader = [[
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
	// LOCAL MOD (2026-09-28, spatial restriction): see the long comment above
	// TEAMCOLOR_RECOLOR_SPATIAL_RESTRICT for the full rationale. Defaults to
	// [0.0, 1.0] (the whole icon, i.e. a no-op) for every unit except ones
	// with an explicit override -- currently only armadvsol's Armada band.
	uniform float restrictArmVMin;
	uniform float restrictArmVMax;
	// LOCAL MOD (2026-09-28, T1 laser tower false positive): corllt/corhllt's
	// own Cortex-band red trim and their laser beam's red glow occupy the
	// same hue/saturation range (unlike armbeamer/armllt's beams, which are a
	// DIFFERENT faction's hue entirely and so are handled by the sat-threshold
	// override instead -- see TEAMCOLOR_RECOLOR_SAT_THRESHOLD_OVERRIDE). An
	// axis-aligned texCoord.s (horizontal) box was tried first and confirmed
	// NOT to work (see TEAMCOLOR_RECOLOR_DEBUG_CORMASK's RESULT note above) --
	// real pixel extraction showed the beam/blast region and the legitimate
	// trim region overlap on both texCoord axes, so no box in either
	// direction can separate them. Replaced with a linear (diagonal) cut in
	// (s,t) space instead: a point is EXCLUDED (treated as beam, not trim)
	// when lineExcludeCorA*s + lineExcludeCorB*t + lineExcludeCorC > 0. Each
	// unit's a/b/c come from fitting a logistic-regression decision boundary
	// to real extracted-icon pixels labeled by connected-component cluster
	// identity -- see TEAMCOLOR_RECOLOR_LINE_EXCLUDE below for the full
	// methodology and per-unit fit quality. Defaults to a=0, b=0, c=-1 (the
	// expression is always -1, never > 0, i.e. a no-op) for every unit
	// without an override.
	uniform float lineExcludeCorA;
	uniform float lineExcludeCorB;
	uniform float lineExcludeCorC;
	// TEAMCOLOR_RECOLOR_CIRCLE_EXCLUDE (2026-09-28, corllt muzzle blast): a
	// single linear cut can only bisect a round region, not exclude all of
	// it -- confirmed by a live screenshot showing corllt's circular muzzle
	// blast half-recolored (the half on the trim side of the line). Adds a
	// second, radial exclusion test OR'd with the line test above: a point
	// is EXCLUDED when its distance from (circleExcludeCorX,
	// circleExcludeCorY) in (s,t) space is < circleExcludeCorR. Defaults to
	// circleExcludeCorR=0.0, a no-op (distance is never negative, so
	// distance < 0 is never true) for every unit without an override -- see
	// TEAMCOLOR_RECOLOR_CIRCLE_EXCLUDE below for the fitted per-unit values.
	uniform float circleExcludeCorX;
	uniform float circleExcludeCorY;
	uniform float circleExcludeCorR;
	// TEAMCOLOR_RECOLOR_RESCUE_INCLUDE (2026-09-28, corllt torso-plate wedge):
	// a small legitimate trim wedge sits close enough to the beam that the
	// LINE_EXCLUDE fit's diagonal cut (tuned for the head/torso/base-ring
	// boundary far above it) wrongly clips it too -- confirmed by a live
	// screenshot circling it, and by re-checking the real extracted icon's
	// pixels directly: the wedge is excluded by the line even though its
	// brightness (~0.71) matches legitimate trim, not the beam (~0.96) a few
	// pixels away. Rather than re-fitting the whole line and risking new
	// regressions elsewhere, this adds a targeted rescue: a point that would
	// otherwise be excluded (by the line OR the circle above) is forced back
	// to "keep" when its distance from (rescueCorX, rescueCorY) is <
	// rescueCorR. Defaults to rescueCorR=0.0, a no-op (distance is never
	// negative, so distance < 0 is never true) for every unit without an
	// override -- see TEAMCOLOR_RECOLOR_RESCUE_INCLUDE below for the fitted
	// per-unit values.
	uniform float rescueCorX;
	uniform float rescueCorY;
	uniform float rescueCorR;
	uniform float debugMode;
	// TEMP DIAGNOSTIC (2026-09-28, armadvsol spatial-restriction orientation):
	// see TEAMCOLOR_RECOLOR_DEBUG_VCOORD above. When on, every icon's pixels
	// are painted by a 3-band split of their own texCoord.t, bypassing all
	// normal recolor logic, so a live screenshot can show definitively which
	// physical part of an icon (top/middle/bottom on screen) corresponds to
	// which texCoord.t range -- resolving the orientation question that two
	// rounds of guessing on armadvsol's vMin/vMax window failed to nail.
	uniform float debugVCoordMode;
	// TEMP DIAGNOSTIC (2026-09-28, corllt/corhllt horizontal-restriction
	// orientation): same idea as debugVCoordMode above, but splits by
	// texCoord.s (horizontal) instead of .t (vertical) -- RED for the
	// screen-right third, GREEN for the middle, BLUE for the screen-left
	// third. Needed because TexRectRound's x-coordinate formula has no "1 -"
	// flip (unlike its y-coordinate one), so the vertical mapping already
	// confirmed direct doesn't by itself prove the horizontal one is too.
	uniform float debugHCoordMode;
	// TEMP DIAGNOSTIC (2026-09-28, corllt/corhllt beam-vs-trim boundary): the
	// horizontal-mapping question is settled (debugHCoordMode confirmed a
	// DIRECT mapping, no flip), but the beam still bled through after both
	// the original and the flipped window -- meaning this was never really
	// an orientation problem, and guessing a third window blind risks a
	// third wrong answer. This paints the REAL icon as-is, but tints any
	// pixel currently satisfying the FULL matchCor condition (hue, sat, AND
	// whatever spatial restriction is live -- at the time this was written,
	// the restrictCorHMin/HMax box; now lineExcludeCorA/B/C, see
	// TEAMCOLOR_RECOLOR_LINE_EXCLUDE) solid magenta -- so a screenshot shows
	// exactly which live, real-size, real-mip-blended pixels are being
	// recolored right now, including whether the beam/blast is among them.
	uniform float debugCorMaskMode;
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
		if (lo <= hi) {
			return (hue >= lo && hue <= hi);
		}
		return (hue >= lo || hue <= hi);
	}

	void main() {
		// TEMP DIAGNOSTIC (2026-09-28): see debugVCoordMode above. Short-circuits
		// everything else -- paints RED for the screen-top third of the icon
		// (texCoord.t closest to 1, since TexRectRound's yc = 1 - yNorm means
		// t=1 at the top of the drawn quad and t=0 at the bottom), GREEN for
		// the middle third, BLUE for the bottom third, so a screenshot directly
		// shows which physical part of the icon maps to which texCoord.t band.
		if (debugVCoordMode > 0.5) {
			if (texCoord.t > 0.6666) {
				gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
			} else if (texCoord.t > 0.3333) {
				gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0);
			} else {
				gl_FragColor = vec4(0.0, 0.0, 1.0, 1.0);
			}
			return;
		}

		// TEMP DIAGNOSTIC (2026-09-28): see debugHCoordMode above. RED for the
		// screen-right third of the icon (texCoord.s closest to 1, if the
		// x-coordinate mapping turns out direct same as y's did), GREEN for
		// the middle third, BLUE for the screen-left third.
		if (debugHCoordMode > 0.5) {
			if (texCoord.s > 0.6666) {
				gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
			} else if (texCoord.s > 0.3333) {
				gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0);
			} else {
				gl_FragColor = vec4(0.0, 0.0, 1.0, 1.0);
			}
			return;
		}

		vec4 texColor = texture2D(tex0, texCoord);
		vec3 hsv = rgb2hsv(texColor.rgb);

		// LOCAL MOD (2026-09-27, per-band threshold fix): each faction band now
		// has its OWN saturation gate instead of one shared satThreshold --
		// see gui_gridmenu_teamcolor.lua's own copy of this shader for the full
		// rationale (lets a per-unit override suppress just ONE band's false
		// positive without touching another band's legitimate trim on the
		// same icon).
		// LOCAL MOD (2026-09-28, spatial restriction): armadvsol's solar-panel
		// glass and its leg/connector trim share statistically indistinguishable
		// hue/saturation/value in the source art (confirmed via real pixel
		// sampling -- no threshold-based fix can separate them), so the Armada
		// band additionally gates on texCoord.t (the icon's vertical UV
		// coordinate) for units with a spatial override. restrictArmVMin/VMax
		// default to [0.0, 1.0] (full range, i.e. a no-op) for every unit
		// without one -- see TEAMCOLOR_RECOLOR_SPATIAL_RESTRICT below.
		bool matchArm = inHueBand(hsv.x, refHueMinArm, refHueMaxArm) && hsv.y >= satThresholdArm
			&& texCoord.t >= restrictArmVMin && texCoord.t <= restrictArmVMax;
		// LOCAL MOD (2026-09-28, T1 laser tower false positive): see the
		// comment above lineExcludeCorA/B/C. Same anti-leak-safe default
		// (a=0,b=0,c=-1, a no-op) as every other per-band override uniform.
		bool corLineExclude = (lineExcludeCorA * texCoord.s + lineExcludeCorB * texCoord.t + lineExcludeCorC) > 0.0;
		// LOCAL MOD (2026-09-28, corllt muzzle blast): see the comment above
		// circleExcludeCorX/Y/R. Same anti-leak-safe default (r=0, a no-op)
		// as every other per-band override uniform.
		float corBlastDist = distance(texCoord, vec2(circleExcludeCorX, circleExcludeCorY));
		bool corCircleExclude = corBlastDist < circleExcludeCorR;
		// LOCAL MOD (2026-09-28, corllt torso-plate wedge): see the comment
		// above rescueCorX/Y/R. Same anti-leak-safe default (r=0, a no-op) as
		// every other per-band override uniform. Rescue wins over either
		// exclude test -- it un-excludes, it never excludes something the
		// other two tests would otherwise have kept.
		float corRescueDist = distance(texCoord, vec2(rescueCorX, rescueCorY));
		bool corRescue = corRescueDist < rescueCorR;
		bool corExcluded = (corLineExclude || corCircleExclude) && !corRescue;
		bool matchCor = inHueBand(hsv.x, refHueMinCor, refHueMaxCor) && hsv.y >= satThresholdCor
			&& !corExcluded;
		bool matchLeg = inHueBand(hsv.x, refHueMinLeg, refHueMaxLeg) && hsv.y >= satThresholdLeg;
		// LOCAL MOD (2026-09-28): 4th band for Scavenger-tech "_scav" unit
		// variants, which sample a wholly separate unitpics/scavengers/*.dds
		// buildpic with its own shared purple accent -- see the comment above
		// TEAMCOLOR_RECOLOR_HUE_MIN_SCAV for the full investigation.
		bool matchScav = inHueBand(hsv.x, refHueMinScav, refHueMaxScav) && hsv.y >= satThresholdScav;

		// TEMP DIAGNOSTIC: see debugCorMaskMode above. Short-circuits with the
		// real icon shown as-is, magenta only where matchCor (the live,
		// currently-deployed condition, restriction included) is true.
		if (debugCorMaskMode > 0.5) {
			if (matchCor) {
				gl_FragColor = vec4(1.0, 0.0, 1.0, texColor.a);
			} else {
				gl_FragColor = texColor;
			}
			return;
		}

		if (matchArm || matchCor || matchLeg || matchScav) {
			// LOCAL MOD (2026-09-27, accuracy fix): also carry over the team
			// color's own SATURATION, not just its hue -- see the matching
			// comment in gui_gridmenu_teamcolor.lua's own copy of this
			// shader for the full rationale (muted/brownish team colors were
			// reading as vivid red, pale team colors were reading as the
			// icon's own default saturation). hsv.z (brightness) is left
			// alone so the icon's own shading is preserved.
			hsv.x = targetHue;
			hsv.y = targetSat;
			gl_FragColor = vec4(hsv2rgb(hsv), texColor.a);
		} else if (debugMode > 0.5) {
			// TEMP DIAGNOSTIC round 2: the first pass (flat magenta) showed
			// the WHOLE legafus icon failing to match -- this splits WHY,
			// so a screenshot tells us which failure mode we're in without
			// another guess-and-redeploy cycle:
			//   CYAN   = hue IS inside the Legion band, but saturation fell
			//            short of satThresholdLeg (a real threshold/render
			//            problem -- lower the Legion threshold for this unit)
			//   MAGENTA = hue isn't in ANY band at all (a hue problem, not a
			//            saturation problem -- the threshold is irrelevant,
			//            something upstream of matching is wrong)
			bool hueInLegBandIgnoringSat = inHueBand(hsv.x, refHueMinLeg, refHueMaxLeg);
			if (hueInLegBandIgnoringSat) {
				gl_FragColor = vec4(0.0, 1.0, 1.0, texColor.a);
			} else {
				gl_FragColor = vec4(1.0, 0.0, 1.0, texColor.a);
			}
		} else {
			gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
		}
	}
]]

-- Plain-Lua RGB->hue (0..1), identical to gui_gridmenu_teamcolor.lua's own copy.
function rgbToHue(r, g, b)
	local maxc = math_max(r, g, b)
	local minc = math_min(r, g, b)
	local delta = maxc - minc
	if delta <= 0.00001 then
		return 0 -- undefined hue (gray) -- caller treats this as "no recolor"
	end
	local hue
	if maxc == r then
		hue = ((g - b) / delta) % 6
	elseif maxc == g then
		hue = (b - r) / delta + 2
	else
		hue = (r - g) / delta + 4
	end
	return hue / 6
end

-- Plain-Lua RGB->saturation (0..1), identical to gui_gridmenu_teamcolor.lua's own copy.
function rgbToSat(r, g, b)
	local maxc = math_max(r, g, b)
	if maxc <= 0.00001 then
		return 0 -- pure black: no meaningful saturation
	end
	local minc = math_min(r, g, b)
	return (maxc - minc) / maxc
end

-- LOCAL MOD (2026-09-27): per-unit, PER-BAND saturation-threshold override,
-- identical rationale and data as gui_gridmenu_teamcolor.lua's own copy of
-- this same table -- see the long comment above that file's
-- TEAMCOLOR_RECOLOR_SAT_THRESHOLD_OVERRIDE for the full investigation
-- (real pixel-sampling of LEGAFUS.DDS confirmed the false positive; a full
-- per-unit EXCLUSION list was tried first and reverted because it also
-- killed the icon's own legitimate trim recoloring entirely -- "makes the
-- legion afuses green and it sucks"; a single shared-threshold override was
-- tried next and also reverted, since raising ONE shared satThreshold still
-- cut into the legitimate Legion-band trim, and the real in-game render
-- filtered out far more of it than raw source-pixel sampling predicted --
-- reported back as the icon still showing fully stock green). The actual
-- fix gates each hue band with its OWN saturation threshold, so this icon's
-- Armada-band gate (where the false-positive "electric arc" pixels live) can
-- be pushed high enough to never match anything, while its Legion-band gate
-- (the real green trim) stays at the normal shared default -- zero tradeoff,
-- since there's no legitimate reason for real Armada-hue trim on a Legion
-- icon in the first place. 1.5 is the "never matches" sentinel value (real
-- saturation never exceeds 1.0).
-- LOCAL MOD (2026-09-28, coradvsol/legadvsol false positive): the SAME
-- shared blue solar-panel material that caused the armadvsol false positive
-- also appears on Cortex's and Legion's own Advanced Solar Collector icons
-- (confirmed via real pixel extraction: coradvsol has 264 Armada-hue
-- saturated pixels, legadvsol has 109 -- both clustered narrowly, unlike
-- armadvsol's much larger false-positive area). Unlike armadvsol, THESE two
-- don't need the spatial-restriction mechanism at all: Cortex's own
-- legitimate trim is red-band (hue 0.95-0.035) and Legion's is green-band
-- (hue 0.27-0.44), both entirely disjoint from the Armada band (0.50-0.66)
-- by construction -- so there is no legitimate reason for ANY Armada-hue
-- pixel to exist on either unit's icon, the same reasoning that justified
-- the legafus/legafust3 "never matches" sentinel below. Pushing their
-- Armada-band threshold to 1.5 fully suppresses the false positive with
-- zero risk to their own (differently-hued) real trim recolor.
-- LOCAL MOD (2026-09-28, T1 laser tower false positive): armbeamer's laser
-- beam glow is purple-hued (falls in the SCAV band, meant for the unrelated
-- Scavenger-tech purple accent -- pure coincidence of hue, armbeamer has
-- nothing to do with Scavengers) and armllt's laser beam is red-hued (falls
-- in the COR band -- also pure coincidence, armllt has nothing to do with
-- Cortex). Confirmed via real pixel extraction + a magenta overlay of each
-- band's match: both bands' matches land EXACTLY on the beam graphic and
-- nowhere on the icon's own legitimate (Armada-band) blue trim, so the same
-- "never matches" sentinel used for legafus/coradvsol/legadvsol fully
-- suppresses each false positive with zero effect on the real trim recolor.
TEAMCOLOR_RECOLOR_SAT_THRESHOLD_OVERRIDE = {
	legafus = { arm = 1.5 },
	legafust3 = { arm = 1.5 },
	coradvsol = { arm = 1.5 },
	legadvsol = { arm = 1.5 },
	armbeamer = { scav = 1.5 },
	armllt = { cor = 1.5 },
}

-- LOCAL MOD (2026-09-28, armadvsol false positive): the Advanced Solar
-- Collector's solar-panel glass (a fixed blue material property, should
-- NEVER recolor) and its small leg/connector trim (legitimately should
-- track team color) occupy the SAME hue/saturation/value range in the
-- source art -- confirmed via real extracted-pixel percentile analysis
-- (panel avgHue=0.603/avgSat=0.717/avgVal=0.721 vs legs
-- avgHue=0.596/avgSat=0.707/avgVal=0.678, effectively indistinguishable).
-- Every previous false-positive fix in this shader (Legion's legafus arc,
-- the Scavenger band, etc.) was solvable with hue/saturation alone; this
-- one isn't, so this is the first band that also gates on WHERE in the
-- icon a pixel sits: texCoord.t is the icon's vertical UV coordinate.
--
-- CORRECTED (2026-09-28, after a first deploy left the icon fully
-- unrecolored -- neither panel nor legs). A live in-game debug diagnostic
-- (paint by texCoord.t: red = t>0.667, green = 0.333-0.667, blue = t<0.333)
-- confirmed the mapping is DIRECT, not flipped: screen-top of the drawn
-- icon is LOW t, screen-bottom is HIGH t, matching the DDS file's own row
-- order (row 0 = top of image = low t). So orientation was never the bug.
-- The real cause: the first window (0.60-0.90) reached back into the
-- panel's own row range (dense cluster ends sharply at row 163 of 256,
-- t=0.637) and also included the SPARSEST, lowest-density edge of the legs
-- cluster (rows 172-191, count 17-49 per 4-row block) -- exactly the kind
-- of thin, low-saturation-after-downscaling content that BAR's own icon
-- mip-blur washes out below the saturation gate at actual render size
-- (the same lesson learned from the Legion hue-band investigation).
-- Retightened to sit on the legs cluster's DENSEST, most robust rows
-- (192-207, count 104-241 per 4-row block -- by far the strongest signal
-- in the whole cluster) with a small margin on each side, and now starts
-- comfortably clear of the panel's row-163 cutoff.
-- Every unit without an entry here gets vMin=0.0/vMax=1.0 (full range,
-- i.e. a complete no-op) so this can never affect any other icon.
-- LOCAL MOD (2026-09-28, T1 laser tower false positive, corllt/corhllt):
-- unlike armbeamer/armllt above, corllt's and corhllt's laser beams are RED
-- -- the SAME hue as their own legitimate Cortex-band trim (confirmed via
-- real pixel extraction: no saturation or value threshold cleanly separates
-- the two populations, the same "same-hue" problem armadvsol's panel/legs
-- had). Two rounds of an axis-aligned texCoord.s (horizontal) box on the COR
-- band -- first a guessed window, then its mirrored "flip" -- both failed
-- (confirmed live via TEAMCOLOR_RECOLOR_DEBUG_CORMASK's near-total-magenta
-- result): real pixel-cluster analysis showed why a box can never work here,
-- for either unit -- the beam/blast blob's bounding box overlaps the
-- legitimate trim's bounding box on BOTH texCoord axes. See
-- TEAMCOLOR_RECOLOR_LINE_EXCLUDE below for the mechanism that replaced it.
TEAMCOLOR_RECOLOR_SPATIAL_RESTRICT = {
	armadvsol = { arm = { vMin = 0.68, vMax = 0.84 } },
}

-- LOCAL MOD (2026-09-28, T1 laser tower false positive, corllt/corhllt --
-- real fix): replaces the corllt/corhllt entries formerly in
-- TEAMCOLOR_RECOLOR_SPATIAL_RESTRICT above (removed, see its comment) with a
-- linear/diagonal cut in (s,t) texture-coordinate space instead of an
-- axis-aligned box, since the false-positive beam/blast region and the
-- legitimate trim region overlap on both axes and no box can separate them.
--
-- Methodology: the real corllt.dds/corhllt.dds unitpics were extracted and
-- converted to PNG, the same Cortex hue/saturation match the shader itself
-- uses was computed per-pixel offline, and scipy.ndimage.label found the
-- resulting match mask's separate connected-component blobs. A
-- logistic-regression classifier was then fit on (s,t) coordinates to find
-- the linear decision boundary a*s + b*t + c = 0 that best separates a
-- "keep" (trim) labeled population from an "exclude" (beam/blast) labeled
-- one -- a pixel is EXCLUDED, i.e. treated as beam and denied recolor, when
-- a*s + b*t + c > 0. Each fit was visually confirmed against the real
-- extracted icon before being deployed here.
--
-- corhllt's clusters are labeled by mean VALUE (HSV brightness): its
-- beam/muzzle-blast blobs are bright/white-hot (meanVal ~0.89-0.98) while
-- its legitimate matte-red trim panels are notably darker (meanVal
-- ~0.42-0.76), and -- crucially -- its twin-turret geometry keeps the two
-- gun housings' own red panels spatially disconnected from either beam in
-- the connected-component analysis, so labeling by cluster identity alone
-- was safe.
--
-- CORRECTED (2026-09-28, user screenshot: base recolored, gun turret head
-- stayed stock red): the FIRST corllt fit (a=8.1262, b=-13.1285, c=2.2661,
-- deployed alongside corhllt's fit above) used the single biggest connected
-- blob as "exclude" without checking what it contained -- and unlike
-- corhllt, corllt's single gun barrel sits close enough to its own blast
-- that the housing's red head/torso panels and the beam+blast fused into
-- ONE 7,184px connected blob, so that fit wrongly excluded the whole gun
-- head from recoloring along with the real beam. Re-fit using explicit
-- rectangular regions of the real extracted icon (head+torso box, base-ring
-- box) as "keep" ground truth instead of blob identity, letting the
-- classifier find the true beam-only diagonal -- confirmed visually against
-- the real icon (head, torso, and base all stay red/recolorable; only the
-- blast+beam diagonal is excluded) before redeploying.
--
--   corllt:  a=23.6226 b=-6.9825  c=-11.9803  (93.6% training accuracy;
--            corrected fit -- see above)
--   corhllt: a=17.2151 b=-2.6811  c=-9.1859  (89.6% training accuracy --
--            good but imperfect; corhllt's twin beams are two separate thin
--            diagonal streaks from two different gun points rather than one
--            blob, a harder shape for a single straight cut, but the fitted
--            line still cleanly excludes the whole beam-side region while
--            leaving the turret body and base trim intact)
--
-- Every unit without an entry here gets a=0, b=0, c=-1 (the expression is
-- always -1, never > 0, i.e. a complete no-op) so this can never affect any
-- other icon.
TEAMCOLOR_RECOLOR_LINE_EXCLUDE = {
	corllt = { cor = { a = 23.6226, b = -6.9825, c = -11.9803 } },
	corhllt = { cor = { a = 17.2151, b = -2.6811, c = -9.1859 } },
}

-- TEAMCOLOR_RECOLOR_CIRCLE_EXCLUDE (2026-09-28, corllt muzzle blast "half
-- red"): user screenshot showed corllt's turret head now correctly
-- recoloring after the LINE_EXCLUDE fit above, but the circular muzzle
-- blast at the gun's tip was only HALF excluded -- the half on the trim
-- side of the fitted line stayed included and wrongly recolored, since a
-- single straight cut can only bisect a round region, not exclude all of
-- it. Fixed by adding a second exclusion primitive, OR'd with the line
-- test: a point is excluded when its (s,t) distance from
-- (circleExcludeCorX, circleExcludeCorY) is < circleExcludeCorR.
--
-- CORRECTED (2026-09-28, user screenshot with arrows: "if you bring it
-- lower it should work"): the FIRST circle fit (x=0.60, y=0.28, r=0.15) was
-- centered/sized by eye against a coordinate-grid overlay of the real icon
-- and looked clean in isolation, but a live screenshot showed it reaching
-- up and left into the turret's own solid-red head panel and the torso's
-- red edge strip below the collar -- both still stock red where they
-- should recolor. A closer, un-tinted zoomed crop of the real icon showed
-- why: those panels are flat-shaded with sharp edges (highlight lines,
-- vent-slot details) right up against the muzzle, so the original circle's
-- upper-left arc clipped straight through them. Re-centered further
-- down-right, tucked against the barrel tip rather than the wider glow's
-- fuzzy outer edge, and shrunk slightly so its boundary stays clear of
-- every sharp panel edge (confirmed numerically: 0 of the solid head
-- diamond's pixels, 0 of the base-ring's, 0 of any pixel at s<=0.45, fall
-- inside the new circle) while still fully covering the specific lobe of
-- the blast that was wrongly recoloring.
--
-- CORRECTED AGAIN (2026-09-28, user screenshot with a hand-drawn blue
-- crescent: "if we can expand to the left it's almost there now"): the
-- SECOND fit (x=0.65, y=0.37, r=0.12) fixed the head/torso clipping, but
-- was tucked in tight enough that it left a thin crescent-shaped sliver of
-- the blast's own glow -- right where it wraps around the barrel's base,
-- between the collar and the main blast core -- still on the keep side,
-- so that sliver stayed wrongly recolored. Confirmed against the same
-- keep/exclude pixel overlay used throughout this investigation: a small
-- cyan "peninsula" reaching down from the collar into the blast region,
-- exactly matching the user's hand-drawn crescent. Widened the radius and
-- shifted the center up-left slightly to absorb that peninsula, re-checked
-- that this still doesn't reach the solid head diamond, the base ring, or
-- anything at s<=0.45 (still 0 pixels each).
--
-- CORRECTED A THIRD TIME (2026-09-28, user screenshot: "arrows point to just
-- a little more expansion to the left to cover teamcolor showing in the
-- blast"): the THIRD fit (x=0.62, y=0.35, r=0.14) fixed the barrel-base
-- crescent, but its lower edge still fell just short of the blast's actual
-- extent where it meets the collar -- a thin strip of team color (~150px in
-- the real icon) was still showing inside what should read as solid blast.
-- Grown and re-centered slightly down: 262 of that strip's 267 pixels now
-- fall inside the new circle, still with 0 pixels of the solid head
-- diamond, 0 of the base-ring, and 0 at s<=0.45 caught (re-checked again at
-- this size).
--
--   corllt: x=0.62 y=0.37 r=0.16  (was x=0.62 y=0.35 r=0.14)
--
-- corhllt was checked too (same method: painted every Cor-matched pixel by
-- current keep/exclude status over the full real icon) and does NOT have
-- this bug -- both of its twin-turret muzzle blasts fall entirely on the
-- exclude side of its existing line fit already, with no overlap, so it
-- gets no entry here.
--
-- Every unit without an entry here gets r=0 (distance is never negative, so
-- distance < 0 is never true, i.e. a complete no-op) so this can never
-- affect any other icon.
TEAMCOLOR_RECOLOR_CIRCLE_EXCLUDE = {
	corllt = { cor = { x = 0.62, y = 0.37, r = 0.16 } },
}

-- TEAMCOLOR_RECOLOR_RESCUE_INCLUDE (2026-09-28, corllt torso-plate wedge
-- caught by the LINE fit): the SAME screenshot above also circled a small
-- red wedge on the torso, well below and outside the blast circle entirely
-- -- a separate bug from the blast, in the original LINE_EXCLUDE fit rather
-- than the circle. Re-checking the real icon confirmed it: a small (~267px)
-- triangular sliver of legitimate torso-plate trim (mean brightness ~0.71,
-- consistent with trim, not the ~0.96 of the beam glow immediately next to
-- it) sits just inside the line's "exclude" half-plane, even though it has
-- nothing to do with the beam. Re-fitting the line to exclude this one
-- wedge risked reopening one of the three previous rounds of regressions on
-- the OTHER side of the boundary, so instead this rescues it directly: a
-- small circle that forces matchCor back to true regardless of what the
-- line or the blast circle above say, for any unit with an entry here.
-- Confirmed the rescue circle stays clear of the real beam glow immediately
-- next to the wedge (0 pixels of that ~90px, ~0.96-brightness cluster fall
-- inside it).
--
--   corllt: x=0.71 y=0.665 r=0.06
--
-- Every unit without an entry here gets r=0 (distance is never negative, so
-- distance < 0 is never true, i.e. a complete no-op) so this can never
-- affect any other icon.
TEAMCOLOR_RECOLOR_RESCUE_INCLUDE = {
	corllt = { cor = { x = 0.71, y = 0.665, r = 0.06 } },
}

-- Draws the recolor pass for one already-drawn unit icon at (x1,y1)-(x2,y2),
-- the same rect and the same "usedZoom + 0.02" offset convention passed to
-- the real UiUnit(...)/WG.FlowUI.Draw.Unit call just before it, so this
-- overlay lines up pixel-perfectly with the icon that call just drew.
-- Takes plain x1/y1/x2/y2 (not a "rect" table like gridmenu's version) since
-- that's what this file's own two call sites already have on hand.
function DrawTeamColorRecolor(x1, y1, x2, y2, cornerSizeArg, unitTexture, usedZoom, unitDefID)
	if not TEAMCOLOR_RECOLOR_ENABLED or not teamColorRecolorShader then
		return
	end

	-- LOCAL MOD (2026-09-27): per-unit, per-band saturation-threshold
	-- override, see the comment above TEAMCOLOR_RECOLOR_SAT_THRESHOLD_OVERRIDE.
	-- Each band independently falls back to the normal shared threshold
	-- unless this unit's override table supplies that specific band.
	local satThresholdArmForThisDraw = TEAMCOLOR_RECOLOR_SAT_THRESHOLD
	local satThresholdCorForThisDraw = TEAMCOLOR_RECOLOR_SAT_THRESHOLD
	local satThresholdLegForThisDraw = TEAMCOLOR_RECOLOR_SAT_THRESHOLD
	local satThresholdScavForThisDraw = TEAMCOLOR_RECOLOR_SAT_THRESHOLD
	-- LOCAL MOD (2026-09-28, spatial restriction): see the comment above
	-- TEAMCOLOR_RECOLOR_SPATIAL_RESTRICT. Defaults to the full [0.0, 1.0]
	-- range (a no-op) for every unit except an explicit override.
	local restrictArmVMinForThisDraw = 0.0
	local restrictArmVMaxForThisDraw = 1.0
	-- LOCAL MOD (2026-09-28, T1 laser tower false positive -- real fix): see
	-- the comment above TEAMCOLOR_RECOLOR_LINE_EXCLUDE. a=0,b=0,c=-1 is a
	-- no-op (the expression is always -1, never > 0, so corLineExclude is
	-- always false) for every unit without an override.
	local lineExcludeCorAForThisDraw = 0.0
	local lineExcludeCorBForThisDraw = 0.0
	local lineExcludeCorCForThisDraw = -1.0
	-- LOCAL MOD (2026-09-28, corllt muzzle blast -- real fix): see the
	-- comment above TEAMCOLOR_RECOLOR_CIRCLE_EXCLUDE. r=0 is a no-op
	-- (distance is never negative, so distance < r is always false) for
	-- every unit without an override.
	local circleExcludeCorXForThisDraw = 0.0
	local circleExcludeCorYForThisDraw = 0.0
	local circleExcludeCorRForThisDraw = 0.0
	-- LOCAL MOD (2026-09-28, corllt torso-plate wedge): see the comment
	-- above TEAMCOLOR_RECOLOR_RESCUE_INCLUDE. r=0 is a no-op (distance is
	-- never negative, so distance < r is always false) for every unit
	-- without an override.
	local rescueCorXForThisDraw = 0.0
	local rescueCorYForThisDraw = 0.0
	local rescueCorRForThisDraw = 0.0
	if unitDefID then
		local uDef = UnitDefs[unitDefID]
		local override = uDef and TEAMCOLOR_RECOLOR_SAT_THRESHOLD_OVERRIDE[uDef.name]
		if override then
			satThresholdArmForThisDraw = override.arm or satThresholdArmForThisDraw
			satThresholdCorForThisDraw = override.cor or satThresholdCorForThisDraw
			satThresholdLegForThisDraw = override.leg or satThresholdLegForThisDraw
			satThresholdScavForThisDraw = override.scav or satThresholdScavForThisDraw
		end
		local spatialOverride = uDef and TEAMCOLOR_RECOLOR_SPATIAL_RESTRICT[uDef.name]
		if spatialOverride and spatialOverride.arm then
			restrictArmVMinForThisDraw = spatialOverride.arm.vMin or restrictArmVMinForThisDraw
			restrictArmVMaxForThisDraw = spatialOverride.arm.vMax or restrictArmVMaxForThisDraw
		end
		local lineExcludeOverride = uDef and TEAMCOLOR_RECOLOR_LINE_EXCLUDE[uDef.name]
		if lineExcludeOverride and lineExcludeOverride.cor then
			lineExcludeCorAForThisDraw = lineExcludeOverride.cor.a or lineExcludeCorAForThisDraw
			lineExcludeCorBForThisDraw = lineExcludeOverride.cor.b or lineExcludeCorBForThisDraw
			lineExcludeCorCForThisDraw = lineExcludeOverride.cor.c or lineExcludeCorCForThisDraw
		end
		local circleExcludeOverride = uDef and TEAMCOLOR_RECOLOR_CIRCLE_EXCLUDE[uDef.name]
		if circleExcludeOverride and circleExcludeOverride.cor then
			circleExcludeCorXForThisDraw = circleExcludeOverride.cor.x or circleExcludeCorXForThisDraw
			circleExcludeCorYForThisDraw = circleExcludeOverride.cor.y or circleExcludeCorYForThisDraw
			circleExcludeCorRForThisDraw = circleExcludeOverride.cor.r or circleExcludeCorRForThisDraw
		end
		local rescueOverride = uDef and TEAMCOLOR_RECOLOR_RESCUE_INCLUDE[uDef.name]
		if rescueOverride and rescueOverride.cor then
			rescueCorXForThisDraw = rescueOverride.cor.x or rescueCorXForThisDraw
			rescueCorYForThisDraw = rescueOverride.cor.y or rescueCorYForThisDraw
			rescueCorRForThisDraw = rescueOverride.cor.r or rescueCorRForThisDraw
		end
	end

	local tr, tg, tb = Spring.GetTeamColor(myTeamID)
	if not tr then
		return
	end

	-- A near-gray team color has no meaningful hue to recolor towards --
	-- skip rather than shift to an arbitrary/unstable hue.
	local maxc, minc = math_max(tr, tg, tb), math_min(tr, tg, tb)
	if maxc - minc <= 0.02 then
		return
	end

	local targetHue = rgbToHue(tr, tg, tb)
	local targetSat = rgbToSat(tr, tg, tb)

	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	glColor(1, 1, 1, 1)
	glTexture(unitTexture)
	teamColorRecolorShader:Activate()
	teamColorRecolorShader:SetUniform("targetHue", targetHue)
	teamColorRecolorShader:SetUniform("targetSat", targetSat)
	-- TEMP DIAGNOSTIC: see TEAMCOLOR_RECOLOR_DEBUG_MASK above.
	teamColorRecolorShader:SetUniform("debugMode", TEAMCOLOR_RECOLOR_DEBUG_MASK and 1 or 0)
	-- TEMP DIAGNOSTIC: see TEAMCOLOR_RECOLOR_DEBUG_VCOORD above.
	teamColorRecolorShader:SetUniform("debugVCoordMode", TEAMCOLOR_RECOLOR_DEBUG_VCOORD and 1 or 0)
	-- TEMP DIAGNOSTIC: see TEAMCOLOR_RECOLOR_DEBUG_HCOORD above.
	teamColorRecolorShader:SetUniform("debugHCoordMode", TEAMCOLOR_RECOLOR_DEBUG_HCOORD and 1 or 0)
	-- TEMP DIAGNOSTIC: see TEAMCOLOR_RECOLOR_DEBUG_CORMASK above.
	teamColorRecolorShader:SetUniform("debugCorMaskMode", TEAMCOLOR_RECOLOR_DEBUG_CORMASK and 1 or 0)
	-- LOCAL MOD (2026-09-27): all three per-band satThreshold uniforms are
	-- always set explicitly (default or overridden), same reasoning as
	-- gui_gridmenu_teamcolor.lua's own copy of this line -- this is one
	-- shared shader instance reused across every icon's draw call, so
	-- skipping any of these when there's no override would leak whatever the
	-- PREVIOUS icon's draw set (possibly a Legion-only override) into
	-- unrelated icons drawn right after it.
	teamColorRecolorShader:SetUniform("satThresholdArm", satThresholdArmForThisDraw)
	teamColorRecolorShader:SetUniform("satThresholdCor", satThresholdCorForThisDraw)
	teamColorRecolorShader:SetUniform("satThresholdLeg", satThresholdLegForThisDraw)
	teamColorRecolorShader:SetUniform("satThresholdScav", satThresholdScavForThisDraw)
	-- LOCAL MOD (2026-09-28): same anti-leak discipline as the satThreshold
	-- uniforms above -- always set explicitly (default or overridden) since
	-- this is one shared shader instance reused across every icon's draw.
	teamColorRecolorShader:SetUniform("restrictArmVMin", restrictArmVMinForThisDraw)
	teamColorRecolorShader:SetUniform("restrictArmVMax", restrictArmVMaxForThisDraw)
	teamColorRecolorShader:SetUniform("lineExcludeCorA", lineExcludeCorAForThisDraw)
	teamColorRecolorShader:SetUniform("lineExcludeCorB", lineExcludeCorBForThisDraw)
	teamColorRecolorShader:SetUniform("lineExcludeCorC", lineExcludeCorCForThisDraw)
	teamColorRecolorShader:SetUniform("circleExcludeCorX", circleExcludeCorXForThisDraw)
	teamColorRecolorShader:SetUniform("circleExcludeCorY", circleExcludeCorYForThisDraw)
	teamColorRecolorShader:SetUniform("circleExcludeCorR", circleExcludeCorRForThisDraw)
	teamColorRecolorShader:SetUniform("rescueCorX", rescueCorXForThisDraw)
	teamColorRecolorShader:SetUniform("rescueCorY", rescueCorYForThisDraw)
	teamColorRecolorShader:SetUniform("rescueCorR", rescueCorRForThisDraw)
	gl.BeginEnd(GL_QUADS, WG.FlowUI.Draw.TexRectRound, x1, y1, x2, y2, cornerSizeArg, 1, 1, 1, 1, usedZoom + 0.02)
	teamColorRecolorShader:Deactivate()
	glTexture(false)
end

function widget:Initialize()
	tracy.ZoneBeginN("W:Info:Initialize")
	isPregame = Spring.GetGameFrame() < 1

	-- LOCAL MOD (2026-09-27): this widget is a modified copy of the stock
	-- "Info" widget (see the file-header comment for the full rationale).
	-- Disable the real one so only this copy is ever actually drawing the
	-- selected-unit info panel -- otherwise both would be active at once.
	if widgetHandler:IsWidgetKnown("Info") then
		widgetHandler:DisableWidgetRaw("Info")
	end

	-- LOCAL MOD (2026-09-27): team-color icon recolor shader, see its own
	-- section above for the actual GLSL/rationale. Fails safe: leaves
	-- teamColorRecolorShader nil (DrawTeamColorRecolor then no-ops) if
	-- shaders aren't supported or this one fails to compile.
	if gl.LuaShader then
		teamColorRecolorShader = gl.LuaShader({
			vertex = teamColorRecolorVertexShader,
			fragment = teamColorRecolorFragmentShader,
			uniformInt = { tex0 = 0 },
			uniformFloat = {
				targetHue = 0,
				targetSat = 0,
				refHueMinArm = TEAMCOLOR_RECOLOR_HUE_MIN_ARM,
				refHueMaxArm = TEAMCOLOR_RECOLOR_HUE_MAX_ARM,
				refHueMinCor = TEAMCOLOR_RECOLOR_HUE_MIN_COR,
				refHueMaxCor = TEAMCOLOR_RECOLOR_HUE_MAX_COR,
				refHueMinLeg = TEAMCOLOR_RECOLOR_HUE_MIN_LEG,
				refHueMaxLeg = TEAMCOLOR_RECOLOR_HUE_MAX_LEG,
				refHueMinScav = TEAMCOLOR_RECOLOR_HUE_MIN_SCAV,
				refHueMaxScav = TEAMCOLOR_RECOLOR_HUE_MAX_SCAV,
				satThresholdArm = TEAMCOLOR_RECOLOR_SAT_THRESHOLD,
				satThresholdCor = TEAMCOLOR_RECOLOR_SAT_THRESHOLD,
				satThresholdLeg = TEAMCOLOR_RECOLOR_SAT_THRESHOLD,
				satThresholdScav = TEAMCOLOR_RECOLOR_SAT_THRESHOLD,
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
				debugMode = 0,
				debugVCoordMode = 0,
				debugHCoordMode = 0,
				debugCorMaskMode = 0,
			},
		}, "InfoTeamColorRecolor")
		if not teamColorRecolorShader:Initialize() then
			Spring.Echo(
				"[Info] team-color icon recolor shader failed to compile -- disabling that effect only, the info panel itself is unaffected"
			)
			teamColorRecolorShader = nil
		end
	end

	tracy.ZoneBeginN("W:Info:Initialize:RefreshUnitInfo")
	refreshUnitInfo()
	tracy.ZoneEnd()

	tracy.ZoneBeginN("W:Info:Initialize:CheckGeothermal")
	checkGeothermalFeatures()
	tracy.ZoneEnd()

	widget:ViewResize()

	WG.info = {}
	WG.info.getShowBuilderBuildlist = function()
		return showBuilderBuildlist
	end
	WG.info.setShowBuilderBuildlist = function(value)
		showBuilderBuildlist = value
	end
	WG.info.getDisplayMapPosition = function()
		return displayMapPosition
	end
	WG.info.setDisplayMapPosition = function(value)
		displayMapPosition = value
	end
	WG.info.getAlwaysShow = function()
		return alwaysShow
	end
	WG.info.setAlwaysShow = function(value)
		alwaysShow = value
	end
	WG.info.displayUnitID = function(unitID)
		cfgDisplayUnitID = unitID
	end
	WG.info.clearDisplayUnitID = function()
		cfgDisplayUnitID = nil
	end
	WG.info.displayUnitDefID = function(unitDefID)
		cfgDisplayUnitDefID = unitDefID
	end
	WG.info.clearDisplayUnitDefID = function()
		cfgDisplayUnitDefID = nil
	end
	WG.info.getPosition = function()
		return width, height
	end
	WG.info.getIsShowing = function()
		return infoShows
	end
	WG.info.setCustomHover = function(hType, hData)
		-- Allow external widgets to supply custom hover info (e.g., PIP window)
		customHoverType = hType
		customHoverData = hData
	end
	WG.info.clearCustomHover = function()
		customHoverType = nil
		customHoverData = nil
	end
	if WG.buildmenu then
		if WG.buildmenu.getGroups then
			groups, unitGroup = WG.buildmenu.getGroups()
		end
		if WG.buildmenu.getOrder then
			unitOrder = WG.buildmenu.getOrder()

			-- order buildoptions
			for uDefID, def in pairs(unitDefInfo) do
				if def.buildOptions then
					local temp = {}
					for i, udid in pairs(def.buildOptions) do
						temp[udid] = i
					end
					local newBuildOptions = {}
					local newBuildOptionsCount = 0
					for k, orderUDefID in pairs(unitOrder) do
						if temp[orderUDefID] then
							newBuildOptionsCount = newBuildOptionsCount + 1
							newBuildOptions[newBuildOptionsCount] = orderUDefID
						end
					end
					unitDefInfo[uDefID].buildOptions = newBuildOptions
				end
			end
		end
	end

	Spring.SetDrawSelectionInfo(false) -- disables springs default display of selected units count
	Spring.SendCommands("tooltip 0")

	if WG.rankicons then
		rankTextures = WG.rankicons.getRankTextures()
	end

	bfcolormap = {}
	local hpcolormap = { { 1, 0.0, 0.0, 1 }, { 0.8, 0.60, 0.0, 1 }, { 0.0, 0.75, 0.0, 1 } }
	for hp = 0, 100 do
		bfcolormap[hp] = { GetColor(hpcolormap, hp * 0.01) }
	end
	tracy.ZoneEnd()
end

function widget:Shutdown()
	-- LOCAL MOD (2026-09-27): team-color icon recolor shader cleanup.
	if teamColorRecolorShader then
		teamColorRecolorShader:Finalize()
		teamColorRecolorShader = nil
	end

	Spring.SetDrawSelectionInfo(true) --disables springs default display of selected units count
	Spring.SendCommands("tooltip 1")
	if infoBgTex then
		gl.DeleteTexture(infoBgTex)
	end
	if infoTex then
		gl.DeleteTexture(infoTex)
	end
	if WG.guishader and dlistGuishader then
		WG.FlowUI.guishaderDeleteDlist("info")
		dlistGuishader = nil
	end
end

local sec2 = 0
local sec = 0
local lastCameraPanMode = false
local lastMouseOffScreen = false
function widget:Update(dt)
	tracy.ZoneBeginN("W:Info:Update")
	infoShows = false
	local x, y, b, b2, b3, mouseOffScreen, cameraPanMode = spGetMouseState()

	-- Early exit for common case
	if not alwaysShow and ((cameraPanMode and not doUpdate) or mouseOffScreen) and not isPregame then
		if SelectedUnitsCount == 0 then
			if dlistGuishader then
				WG.guishader.DeleteDlist("info")
				dlistGuishader = nil
			end
		end
		tracy.ZoneEnd()
		return
	end

	-- Only check changes when camera or mouse state changes
	if lastCameraPanMode ~= cameraPanMode or lastMouseOffScreen ~= mouseOffScreen then
		tracy.ZoneBeginN("W:Info:Update:CheckChangesState")
		lastCameraPanMode = cameraPanMode
		lastMouseOffScreen = mouseOffScreen
		checkChanges()
		doUpdate = true
		tracy.ZoneEnd()
	end

	sec2 = sec2 + dt
	if sec2 > 0.5 then
		tracy.ZoneBeginN("W:Info:Update:HalfSecond")
		sec2 = 0

		if not rankTextures and WG.rankicons then
			rankTextures = WG.rankicons.getRankTextures()
		end

		local _, _, mapMinWater, _ = Spring.GetGroundExtremes()
		if mapMinWater <= minWaterUnitDepth then
			if not showWaterUnits then
				showWaterUnits = true

				for unitDefID, _ in pairs(isWaterUnit) do
					if not isGeothermalUnit[unitDefID] or showGeothermalUnits then -- make sure geothermal units keep being disabled if that should be the case
						unitDisabled[unitDefID] = nil
					end
				end
			end
		end
		tracy.ZoneEnd()
	end

	sec = sec + dt
	if sec > 0.035 then
		tracy.ZoneBeginN("W:Info:Update:CheckChangesTick")
		sec = 0
		checkChanges()
		if alwaysShow or not emptyInfo then
			checkGuishader()
		end
		tracy.ZoneEnd()
	end

	if ViewResizeUpdate then
		ViewResizeUpdate = nil
	end

	if doUpdate or (doUpdateClock and os_clock() >= doUpdateClock) or (os_clock() >= doUpdateClock2) then
		tracy.ZoneBeginN("W:Info:Update:ScheduleTexture")
		doUpdateClock = nil
		doUpdateClock2 = os_clock() + 0.9
		updateTex = true
		doUpdate = nil
		lastUpdateClock = os_clock()
		tracy.ZoneEnd()
	end

	if displayUnitID and not Spring.ValidUnitID(displayUnitID) then
		displayMode = "text"
		displayUnitID = nil
		displayUnitDefID = nil
	end

	if not alwaysShow and (cameraPanMode or mouseOffScreen) and SelectedUnitsCount == 0 and not isPregame then
		tracy.ZoneEnd()
		return
	end

	if alwaysShow or not emptyInfo or (isPregame and not mySpec) then
		infoShows = true
	end
	tracy.ZoneEnd()
end

local function DrawRectRoundCircle(x, y, z, radius, cs, centerOffset, color1, color2)
	if not color2 then
		color2 = color1
	end
	--centerOffset = 0
	local coords = {
		{ x - radius + cs, z + radius, y }, -- top left
		{ x + radius - cs, z + radius, y }, -- top right
		{ x + radius, z + radius - cs, y }, -- right top
		{ x + radius, z - radius + cs, y }, -- right bottom
		{ x + radius - cs, z - radius, y }, -- bottom right
		{ x - radius + cs, z - radius, y }, -- bottom left
		{ x - radius, z - radius + cs, y }, -- left bottom
		{ x - radius, z + radius - cs, y }, -- left top
	}
	local cs2 = cs * (centerOffset / radius)
	local coords2 = {
		{ x - centerOffset + cs2, z + centerOffset, y }, -- top left
		{ x + centerOffset - cs2, z + centerOffset, y }, -- top right
		{ x + centerOffset, z + centerOffset - cs2, y }, -- right top
		{ x + centerOffset, z - centerOffset + cs2, y }, -- right bottom
		{ x + centerOffset - cs2, z - centerOffset, y }, -- bottom right
		{ x - centerOffset + cs2, z - centerOffset, y }, -- bottom left
		{ x - centerOffset, z - centerOffset + cs2, y }, -- left bottom
		{ x - centerOffset, z + centerOffset - cs2, y }, -- left top
	}
	for i = 1, 8 do
		local i2 = (i >= 8 and 1 or i + 1)
		gl.Color(color2)
		gl.Vertex(coords[i][1], coords[i][2], coords[i][3])
		gl.Vertex(coords[i2][1], coords[i2][2], coords[i2][3])
		gl.Color(color1)
		gl.Vertex(coords2[i2][1], coords2[i2][2], coords2[i2][3])
		gl.Vertex(coords2[i][1], coords2[i][2], coords2[i][3])
	end
end
local function RectRoundCircle(x, y, z, radius, cs, centerOffset, color1, color2)
	gl.BeginEnd(GL_QUADS, DrawRectRoundCircle, x, y, z, radius, cs, centerOffset, color1, color2)
end

-- Cache for kill counts to avoid expensive spGetUnitRulesParam calls every frame
local killCountCache = {}
local killCountCacheTime = 0

local function drawSelectionCell(cellID, uDefID, usedZoom, highlightColor)
	tracy.ZoneBeginN("W:Info:DrawSelection:Cell")
	if not usedZoom then
		usedZoom = defaultCellZoom
	end
	local unitTexture = "#" .. uDefID
	if not selectionUnitpicWarm.warmed[uDefID] then
		tracy.ZoneBeginN("W:Info:DrawSelection:Cell:TextureWarmFallback")
		if glTexture(unitTexture) then
			selectionUnitpicWarm.warmed[uDefID] = true
		end
		glTexture(false)
		tracy.ZoneEnd()
	end

	tracy.ZoneBeginN("W:Info:DrawSelection:Cell:UiUnit")
	glColor(1, 1, 1, 1)
	UiUnit(
		cellRect[cellID][1] + cellPadding,
		cellRect[cellID][2] + cellPadding,
		cellRect[cellID][3],
		cellRect[cellID][4],
		cornerSize,
		1,
		1,
		1,
		1,
		usedZoom,
		nil,
		nil,
		unitTexture,
		nil,
		groups[unitGroup[uDefID]]
	)
	-- LOCAL MOD (2026-09-27): team-color icon recolor, see the "LOCAL MOD"
	-- section above widget:Initialize() for the shader/rationale.
	DrawTeamColorRecolor(
		cellRect[cellID][1] + cellPadding,
		cellRect[cellID][2] + cellPadding,
		cellRect[cellID][3],
		cellRect[cellID][4],
		cornerSize,
		unitTexture,
		usedZoom,
		uDefID
	)
	tracy.ZoneEnd()

	tracy.ZoneBeginN("W:Info:DrawSelection:Cell:CountText")
	local selCount = selUnitsCounts[uDefID]
	-- unit count - calculate fontSize once
	local fontSize = math_min(gridHeight * 0.17, cellsize * 0.6) * (1 - ((1 + string.len(selCount)) * 0.066))
	if selCount > 1 then
		--font2:Begin(true)
		font2:Print(
			cachedColorStrings.white .. selCount,
			cellRect[cellID][3] - cellPadding - (fontSize * 0.09),
			cellRect[cellID][2] + (fontSize * 0.3),
			fontSize,
			"ro"
		)
		--font2:End()
	end
	tracy.ZoneEnd()

	tracy.ZoneBeginN("W:Info:DrawSelection:Cell:KillCount")
	-- kill count - cached to reduce expensive calls
	local currentTime = os_clock()
	local kills = 0

	-- Only update kill cache every 0.5 seconds
	if currentTime - killCountCacheTime > 0.5 then
		killCountCacheTime = currentTime
		-- Clear old cache
		for k in pairs(killCountCache) do
			killCountCache[k] = nil
		end
	end

	-- Check if we have cached value for this unitdef
	if killCountCache[uDefID] then
		kills = killCountCache[uDefID]
	else
		-- Calculate kills (expensive)
		local unitsSortedForDef = selUnitsSorted[uDefID]
		for i = 1, #unitsSortedForDef do
			local unitKills = spGetUnitRulesParam(unitsSortedForDef[i], "kills")
			if unitKills then
				kills = kills + unitKills
			end
		end
		killCountCache[uDefID] = kills
	end
	tracy.ZoneEnd()
	if kills > 0 then
		tracy.ZoneBeginN("W:Info:DrawSelection:Cell:KillDraw")
		local size = math_floor((cellRect[cellID][3] - (cellRect[cellID][1] + (cellPadding * 0.5))) * 0.33)
		glColor(0.88, 0.88, 0.88, 0.66)
		glTexture(":l:LuaUI/Images/skull.dds")
		glTexRect(
			cellRect[cellID][3] - size + (cellPadding * 0.5),
			cellRect[cellID][4] - size - (cellPadding * 0.5),
			cellRect[cellID][3] + (cellPadding * 0.5),
			cellRect[cellID][4] - (cellPadding * 0.5)
		)
		glTexture(false)
		--font2:Begin(true)
		font2:Print(
			cachedColorStrings.white .. kills,
			cellRect[cellID][3] - (size * 0.5) + (cellPadding * 0.5),
			cellRect[cellID][4] - (cellPadding * 0.5) - (size * 0.5) - (fontSize * 0.19),
			fontSize * 0.66,
			"oc"
		)
		--font2:End()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

local function drawSelection()
	tracy.ZoneBeginN("W:Info:DrawSelection")
	tracy.ZoneBeginN("W:Info:DrawSelection:Query")
	selUnitsCounts = spGetSelectedUnitsCounts()
	selUnitsSorted = spGetSelectedUnitsSorted()
	selUnitTypes = 0

	-- Reuse existing table instead of creating new one
	if not selectionCells then
		selectionCells = {}
	else
		-- Clear existing entries
		for i = #selectionCells, 1, -1 do
			selectionCells[i] = nil
		end
	end

	for k, uDefID in pairs(unitOrder) do
		if selUnitsSorted[uDefID] then
			if type(selUnitsSorted[uDefID]) == "table" then
				selUnitTypes = selUnitTypes + 1
				selectionCells[selUnitTypes] = uDefID
			end
		end
	end
	tracy.ZoneEnd()

	-- draw selection totals
	--local stats = getSelectionTotals(selectionCells)
	local fontSize = (height * vsy * 0.115) * (0.95 - ((1 - ui_scale) * 0.5))
	local heightVar = 0
	local heightStep = (fontSize * 1.36)
	font2:Begin(true)
	font2:SetOutlineColor(0, 0, 0, 1)
	font2:Print(
		tooltipTextColor
			.. #selectedUnits
			.. tooltipLabelTextColor
			.. "  "
			.. getCachedTranslation("ui.info.unitsselected"),
		backgroundRect[1] + contentPadding,
		backgroundRect[4] - contentPadding - (fontSize * 1.2) - heightVar,
		(fontSize * 1.23),
		"o"
	)
	font2:End()
	font:Begin(true)
	font:SetOutlineColor(0, 0, 0, 1)
	heightVar = heightVar + (fontSize * 0.85)

	-- loop all unitdefs/cells (but not individual unitID's)
	local totalMetalValue = 0
	local totalEnergyValue = 0
	local totalBuildPower = 0

	for i = 1, #selectionCells do
		local unitDefID = selectionCells[i]
		local unitDefData = unitDefInfo[unitDefID]
		local count = selUnitsCounts[unitDefID]
		-- metal cost
		if unitDefData.metalCost then
			totalMetalValue = totalMetalValue + (unitDefData.metalCost * count)
		end
		-- energy cost
		if unitDefData.energyCost then
			totalEnergyValue = totalEnergyValue + (unitDefData.energyCost * count)
		end
		-- build power
		if unitDefData.buildSpeed and unitDefData.buildSpeed > 0 then
			totalBuildPower = totalBuildPower + (unitDefData.buildSpeed * count)
		end
	end

	-- Only calculate resources for limited set of units (expensive operation)
	-- Limit to first 50 units to avoid frame drops during large selections
	local totalMetalMake, totalMetalUse, totalEnergyMake, totalEnergyUse = 0, 0, 0, 0
	local totalKills = 0
	local unitsToCheck = cellHovered and selUnitsSorted[selectionCells[cellHovered]] or selectedUnits
	local maxUnitsToCheck = math.min(50, #unitsToCheck)
	tracy.ZoneBeginN("W:Info:DrawSelection:ResourceTotals")
	for i = 1, maxUnitsToCheck do
		local unitID = unitsToCheck[i]
		local metalMake, metalUse, energyMake, energyUse = spGetUnitResources(unitID)
		if metalMake then
			local pairedID = spGetUnitRulesParam(unitID, "pairedUnitID")
			if pairedID then
				local mm, mu, em, eu = spGetUnitResources(pairedID)
				if mm then
					metalMake, metalUse, energyMake, energyUse =
						metalMake + mm, metalUse + mu, energyMake + em, energyUse + eu
				end
			end
			totalMetalMake = totalMetalMake + metalMake
			totalMetalUse = totalMetalUse + metalUse
			totalEnergyMake = totalEnergyMake + energyMake
			totalEnergyUse = totalEnergyUse + energyUse
		end
		local kills = spGetUnitRulesParam(unitID, "kills")
		if kills then
			totalKills = totalKills + kills
		end
	end

	-- Scale up if we only checked a subset
	if maxUnitsToCheck < #unitsToCheck then
		local scale = #unitsToCheck / maxUnitsToCheck
		totalMetalMake = totalMetalMake * scale
		totalMetalUse = totalMetalUse * scale
		totalEnergyMake = totalEnergyMake * scale
		totalEnergyUse = totalEnergyUse * scale
		totalKills = math.floor(totalKills * scale)
	end
	tracy.ZoneEnd()

	local valuePlusColor = "\255\180\255\180"
	local valueMinColor = "\255\255\180\180"
	if totalMetalUse > 0 or totalMetalMake > 0 then
		heightVar = heightVar + heightStep
		font:Print(
			tooltipLabelTextColor
				.. getCachedTranslation("ui.info.m")
				.. "   "
				.. (totalMetalMake > 0 and valuePlusColor .. "+" .. (totalMetalMake < 10 and round(totalMetalMake, 1) or round(
					totalMetalMake,
					0
				)) .. "  " or "")
				.. (
					totalMetalUse > 0
						and valueMinColor .. "-" .. (totalMetalUse < 10 and round(totalMetalUse, 1) or round(
							totalMetalUse,
							0
						))
					or ""
				),
			backgroundRect[1] + contentPadding,
			backgroundRect[4] - (bgpadding * 2.4) - (fontSize * 0.8) - heightVar,
			fontSize,
			"o"
		)
	end
	if totalEnergyUse > 0 or totalEnergyMake > 0 then
		heightVar = heightVar + heightStep
		font:Print(
			tooltipLabelTextColor
				.. getCachedTranslation("ui.info.e")
				.. "   "
				.. (totalEnergyMake > 0 and valuePlusColor .. "+" .. (totalEnergyMake < 10 and round(totalEnergyMake, 1) or round(
					totalEnergyMake,
					0
				)) .. "  " or "")
				.. (
					totalEnergyUse > 0
						and valueMinColor .. "-" .. (totalEnergyUse < 10 and round(totalEnergyUse, 1) or round(
							totalEnergyUse,
							0
						))
					or ""
				),
			backgroundRect[1] + contentPadding,
			backgroundRect[4] - (bgpadding * 2.4) - (fontSize * 0.8) - heightVar,
			fontSize,
			"o"
		)
	end

	-- metal cost
	heightVar = heightVar + heightStep
	font:Print(
		tooltipLabelTextColor
			.. getCachedTranslation("ui.info.costm")
			.. "   "
			.. tooltipValueWhiteColor
			.. string.formatSI(totalMetalValue),
		backgroundRect[1] + contentPadding,
		backgroundRect[4] - (bgpadding * 2.4) - (fontSize * 0.8) - heightVar,
		fontSize,
		"o"
	)

	-- energy cost
	heightVar = heightVar + heightStep
	font:Print(
		tooltipLabelTextColor
			.. getCachedTranslation("ui.info.coste")
			.. "\255\255\255\128   "
			.. string.formatSI(totalEnergyValue),
		backgroundRect[1] + contentPadding,
		backgroundRect[4] - (bgpadding * 2.4) - (fontSize * 0.8) - heightVar,
		fontSize,
		"o"
	)

	-- Buildpower
	if totalBuildPower > 0 then
		heightVar = heightVar + heightStep
		font:Print(
			tooltipLabelTextColor
				.. getCachedTranslation("ui.info.buildpower")
				.. "   "
				.. tooltipValueYellowColor
				.. string.formatSI(totalBuildPower),
			backgroundRect[1] + contentPadding,
			backgroundRect[4] - (bgpadding * 2.4) - (fontSize * 0.8) - heightVar,
			fontSize,
			"o"
		)
	end

	-- kills
	if totalKills > 0 then
		heightVar = heightVar + heightStep
		font:Print(
			tooltipLabelTextColor .. getCachedTranslation("ui.info.kills") .. "   " .. tooltipValueColor .. totalKills,
			backgroundRect[1] + contentPadding,
			backgroundRect[4] - (bgpadding * 2.4) - (fontSize * 0.8) - heightVar,
			fontSize,
			"o"
		)
	end
	font:End()

	-- selected units grid area
	local gridWidth = math_floor((backgroundRect[3] - backgroundRect[1] - bgpadding) * 0.6) -- leaving some room for the totals
	gridHeight = math_floor((backgroundRect[4] - backgroundRect[2]) - bgpadding)

	-- Reuse customInfoArea table
	if not customInfoArea then
		customInfoArea = {}
	end
	customInfoArea[1] = backgroundRect[3] - gridWidth
	customInfoArea[2] = backgroundRect[2]
	customInfoArea[3] = backgroundRect[3] - bgpadding
	customInfoArea[4] = backgroundRect[2] + gridHeight

	-- draw selected unit icons
	tracy.ZoneBeginN("W:Info:DrawSelection:Grid")
	tracy.ZoneBeginN("W:Info:DrawSelection:Grid:Layout")
	local rows = 2
	local maxRows = 15 -- just to be sure
	local colls = math_ceil(selUnitTypes / rows)
	cellsize = math_floor(math_min(gridWidth / colls, gridHeight / rows))
	while cellsize < gridHeight / (rows + 1) do
		rows = rows + 1
		colls = math_ceil(selUnitTypes / rows)
		cellsize = math_min(gridWidth / colls, gridHeight / rows)
		if rows > maxRows then
			break
		end
	end

	-- adjust grid size to add some padding at the top and right side
	cellsize = math_floor((cellsize * (1 - (0.04 / rows))) + 0.5) -- leave some space at the top
	cellPadding = math_max(1, math_floor(cellsize * 0.03))
	customInfoArea[3] = customInfoArea[3] - cellPadding -- leave space at the right side
	tracy.ZoneEnd()

	-- draw grid (bottom right to top left)
	-- Reuse cellRect table
	tracy.ZoneBeginN("W:Info:DrawSelection:Grid:CellRects")
	if not cellRect then
		cellRect = {}
	else
		-- Clear old entries
		for i = #cellRect, 1, -1 do
			cellRect[i] = nil
		end
	end
	texOffset = (0.03 * rows) * zoomMult
	cornerSize = math_max(1, cellPadding * 0.9)
	if texOffset > 0.25 then
		texOffset = 0.25
	end
	tracy.ZoneEnd()

	tracy.ZoneBeginN("W:Info:DrawSelection:Grid:Cells")
	local cellID = selUnitTypes
	for row = 1, rows do
		for coll = 1, colls do
			if selectionCells[cellID] then
				--local uDefID = selectionCells[cellID]
				local cellRectEntry = cellRect[cellID]
				if not cellRectEntry then
					cellRectEntry = {}
					cellRect[cellID] = cellRectEntry
				end
				cellRectEntry[1] = math_ceil(customInfoArea[3] - cellPadding - (coll * cellsize))
				cellRectEntry[2] = math_ceil(customInfoArea[2] + cellPadding + ((row - 1) * cellsize))
				cellRectEntry[3] = math_ceil(customInfoArea[3] - cellPadding - ((coll - 1) * cellsize))
				cellRectEntry[4] = math_ceil(customInfoArea[2] + cellPadding + (row * cellsize))
				drawSelectionCell(cellID, selectionCells[cellID], texOffset)
			end
			cellID = cellID - 1
			if cellID <= 0 then
				break
			end
		end
		if cellID <= 0 then
			break
		end
	end
	tracy.ZoneEnd()
	glTexture(false)
	glColor(1, 1, 1, 1)
	tracy.ZoneEnd()
	tracy.ZoneEnd()
end

local function GetAIName(teamID)
	local _, _, _, name, _, options = Spring.GetAIInfo(teamID)
	local niceName = Spring.GetGameRulesParam("ainame_" .. teamID)
	if niceName then
		name = niceName
		--if Spring.Utilities.ShowDevUI() and options.profile then
		--	name = name .. " [" .. options.profile .. "]"
		--end
	end
	return BAR.I18N("ui.playersList.aiName", { name = name })
end

local function drawUnitInfo()
	tracy.ZoneBeginN("W:Info:DrawUnitInfo")
	local fontSize = (height * vsy * 0.123) * (0.94 - ((1 - math.max(1.05, ui_scale)) * 0.4))

	local iconSize = math.floor(fontSize * 4.4)
	local iconPadding = math.floor(fontSize * 0.22)

	if unitDefInfo[displayUnitDefID].buildPic then
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:BuildPic")
		local iconX = backgroundRect[1] + iconPadding
		local iconY = backgroundRect[4] - iconPadding - bgpadding
		-- unit icon
		glColor(1, 1, 1, 1)
		UiUnit(
			iconX,
			iconY - iconSize,
			iconX + iconSize,
			iconY,
			nil,
			1,
			1,
			1,
			1,
			0.03,
			nil,
			nil,
			"#" .. displayUnitDefID,
			(unitDefInfo[displayUnitDefID].icontype and ":l:" .. unitDefInfo[displayUnitDefID].icontype or nil),
			groups[unitGroup[displayUnitDefID]],
			{ unitDefInfo[displayUnitDefID].metalCost, unitDefInfo[displayUnitDefID].energyCost }
		)
		-- LOCAL MOD (2026-09-27): team-color icon recolor. cornerSize here
		-- mirrors WG.FlowUI.Draw.Unit's own default-cs formula
		-- (max(1, floor(width * 0.024))) since the real UiUnit call above
		-- passed cornerSize=nil and let it compute that default internally.
		DrawTeamColorRecolor(
			iconX,
			iconY - iconSize,
			iconX + iconSize,
			iconY,
			math_max(1, math_floor(iconSize * 0.024)),
			"#" .. displayUnitDefID,
			0.03,
			displayUnitDefID
		)
		tracy.ZoneEnd()
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:BuildText")
		-- price
		local function AddSpaces(price)
			if price >= 1000 then
				return string.format("%s %03d", AddSpaces(math_floor(price / 1000)), price % 1000)
			end
			return price
		end
		local halfSize = iconSize * 0.5
		local padding = (halfSize + halfSize) * 0.045
		local size = (halfSize + halfSize) * 0.195
		local metalPriceText = "\255\245\245\245" .. AddSpaces(unitDefInfo[displayUnitDefID].metalCost)
		local energyPriceText = "\n\255\255\255\000" .. AddSpaces(unitDefInfo[displayUnitDefID].energyCost)
		local energyPriceTextHeight = font2:GetTextHeight(energyPriceText) * size

		font2:Begin(true)
		font2:SetOutlineColor(0, 0, 0, 1)
		font2:Print(
			metalPriceText,
			iconX + iconSize - padding,
			iconY - halfSize - halfSize + padding + (size * 1.07) + energyPriceTextHeight,
			size,
			"ro"
		)
		font2:Print(
			energyPriceText,
			iconX + iconSize - padding,
			iconY - halfSize - halfSize + padding + (size * 1.07),
			size,
			"ro"
		)
		font2:End()
		tracy.ZoneEnd()
	end
	iconSize = iconSize + iconPadding

	local mindps, maxdps, minemp, maxemp, range, metalExtraction, stockpile, maxRange, exp, metalMake, metalUse, energyMake, energyUse
	tracy.ZoneBeginN("W:Info:DrawUnitInfo:DescriptionWrap")
	local text, unitDescriptionLines = font:WrapText(
		unitDefInfo[displayUnitDefID].description,
		(contentWidth - iconSize) * (loadedFontSize / fontSize)
	)
	tracy.ZoneEnd()

	if displayUnitID then
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:RankKills")
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:RankKills:Rank")
		exp = spGetUnitExperience(displayUnitID)
		if exp and exp > 0.009 and WG.rankicons and rankTextures then
			if displayUnitID then
				local rank = WG.rankicons.getRank(displayUnitDefID, exp)
				if rankTextures[rank] then
					local rankIconSize = math_floor((height * vsy * 0.24) + 0.5)
					local rankIconMarginX = math_floor((height * vsy * 0.015) + 0.5)
					local rankIconMarginY = math_floor((height * vsy * 0.18) + 0.5)
					glColor(1, 1, 1, 0.88)
					glTexture(":l:" .. rankTextures[rank])
					glTexRect(
						backgroundRect[3] - rankIconMarginX - rankIconSize,
						backgroundRect[4] - rankIconMarginY - rankIconSize,
						backgroundRect[3] - rankIconMarginX,
						backgroundRect[4] - rankIconMarginY
					)
					glTexture(false)
					glColor(1, 1, 1, 1)
				end
			end
		end
		tracy.ZoneEnd()
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:RankKills:Kills")
		local kills = spGetUnitRulesParam(displayUnitID, "kills")
		if kills and kills > 0 then
			local rankIconSize = math_floor((height * vsy * 0.16))
			local rankIconMarginY = math_floor((height * vsy * 0.07) + 0.5)
			local rankIconMarginX = math_floor((height * vsy * 0.053) + 0.5)
			glColor(0.7, 0.7, 0.7, 0.55)
			glTexture(":l:LuaUI/Images/skull.dds")
			glTexRect(
				backgroundRect[3] - rankIconMarginX - rankIconSize,
				backgroundRect[4] - rankIconMarginY - rankIconSize,
				backgroundRect[3] - rankIconMarginX,
				backgroundRect[4] - rankIconMarginY
			)
			glTexture(false)
			font2:Begin(true)
			font2:SetOutlineColor(0, 0, 0, 1)
			font2:Print(
				"\255\215\215\215" .. kills,
				backgroundRect[3] - rankIconMarginX - (rankIconSize * 0.5),
				backgroundRect[4] - (rankIconMarginY * 2.05) - (fontSize * 0.31),
				fontSize * 0.87,
				"oc"
			)
			font2:End()
		end
		tracy.ZoneEnd()
		tracy.ZoneEnd()
	end

	tracy.ZoneBeginN("W:Info:DrawUnitInfo:Header")

	local unitNameColor = tooltipTitleColor
	if SelectedUnitsCount > 0 then
		if
			displayMode ~= "unitdef"
			or (
				WG.buildmenu
				and (
					activeCmdID
					and activeCmdID < 0
					and (not WG.buildmenu.hoverID or (-activeCmdID == WG.buildmenu.hoverID))
				)
			)
		then
			unitNameColor = "\255\125\255\125"
		end
	end
	local descriptionColor = "\255\240\240\240"
	local healthColor = "\255\100\255\100"

	local labelColor = "\255\205\205\205"
	local valueColor = "\255\255\255\255"
	local valuePlusColor = "\255\180\255\180"
	local valueMinColor = "\255\255\180\180"

	-- custom unit info background
	local width = contentWidth * 0.82
	local height = (backgroundRect[4] - backgroundRect[2]) * (unitDescriptionLines > 1 and 0.495 or 0.6)

	-- unit tooltip
	font:Begin(true)
	font:SetOutlineColor(0, 0, 0, 1)
	font:Print(
		descriptionColor .. text,
		backgroundRect[3] - width + bgpadding,
		backgroundRect[4] - contentPadding - (fontSize * 2.17),
		fontSize * 0.94,
		"o"
	)
	font:End()

	-- unit name
	local nameFontSize = fontSize * 1.12
	local humanName = unitDefInfo[displayUnitDefID].translatedHumanName
	humanName = string.gsub(humanName, "Scavenger", "Scav")
	if font:GetTextWidth(humanName) * nameFontSize > width * 1.05 then
		while font:GetTextWidth(humanName) * nameFontSize > width do
			humanName = string.sub(humanName, 1, string.len(humanName) - 1)
		end
		humanName = humanName .. "..."
	end
	font2:Begin(true)
	font2:SetOutlineColor(0, 0, 0, 1)
	font2:Print(
		unitNameColor .. humanName,
		backgroundRect[3] - width + bgpadding,
		backgroundRect[4] - contentPadding - (nameFontSize * 0.76),
		nameFontSize,
		"o"
	)
	--font2:End()

	-- custom unit info area
	customInfoArea = {
		math_floor(backgroundRect[3] - width - bgpadding),
		math_floor(backgroundRect[2]),
		math_floor(backgroundRect[3] - bgpadding),
		math_floor(backgroundRect[2] + height),
	}

	if
		displayMode ~= "unitdef"
		or not showBuilderBuildlist
		or not unitDefInfo[displayUnitDefID].buildOptions
		or not (WG.buildmenu and WG.buildmenu.hoverID)
	then
		RectRound(
			customInfoArea[1],
			customInfoArea[2],
			customInfoArea[3],
			customInfoArea[4],
			elementCorner * 0.66,
			1,
			0,
			0,
			0,
			{ 0.8, 0.8, 0.8, 0.07 },
			{ 0.8, 0.8, 0.8, 0.1 }
		)
	end
	tracy.ZoneEnd()

	local contentPaddingLeft = contentPadding * 0.6
	local texSize = fontSize * 0.6

	local leftSideHeight = (backgroundRect[4] - backgroundRect[2]) * 0.47
	local posY1 = math_floor(backgroundRect[2] + leftSideHeight)
		- contentPadding
		- ((math_floor(backgroundRect[2] + leftSideHeight) - math_floor(backgroundRect[2])) * 0.1)
	local posY2 = math_floor(backgroundRect[2] + leftSideHeight)
		- contentPadding
		- ((math_floor(backgroundRect[2] + leftSideHeight) - math_floor(backgroundRect[2])) * 0.38)
	local posY3 = math_floor(backgroundRect[2] + leftSideHeight)
		- contentPadding
		- ((math_floor(backgroundRect[2] + leftSideHeight) - math_floor(backgroundRect[2])) * 0.67)

	local valueY1, valueY2, valueY3 = "", "", ""
	local health, maxHealth, _, _, buildProgress
	tracy.ZoneBeginN("W:Info:DrawUnitInfo:LiveStats")
	if displayUnitID then
		local metalMake, metalUse, energyMake, energyUse = spGetUnitResources(displayUnitID)
		if metalMake then
			local pairedID = spGetUnitRulesParam(displayUnitID, "pairedUnitID")
			if pairedID then
				local mm, mu, em, eu = spGetUnitResources(pairedID)
				if mm then
					metalMake, metalUse, energyMake, energyUse =
						metalMake + mm, metalUse + mu, energyMake + em, energyUse + eu
				end
			end
			valueY1 = (
				metalMake > 0
					and valuePlusColor .. "+" .. (metalMake < 10 and round(metalMake, 1) or round(metalMake, 0)) .. " "
				or ""
			)
				.. (
					metalUse > 0
						and valueMinColor .. "-" .. (metalUse < 10 and round(metalUse, 1) or round(metalUse, 0))
					or ""
				)
			valueY2 = (
				energyMake > 0
					and valuePlusColor .. "+" .. (energyMake < 10 and round(energyMake, 1) or round(energyMake, 0)) .. " "
				or ""
			)
				.. (
					energyUse > 0
						and valueMinColor .. "-" .. (energyUse < 10 and round(energyUse, 1) or round(energyUse, 0))
					or ""
				)
			valueY3 = ""
		end

		-- display health value/bar
		health, maxHealth = spGetUnitHealth(displayUnitID)
		if health then
			local color = bfcolormap[math.clamp(math_floor((health / maxHealth) * 100), 0, 100)]
			valueY3 = BAR.Utilities.ConvertColor(color[1], color[2], color[3]) .. math_floor(health)
		end

		-- display unit owner name
		local teamID = Spring.GetUnitTeam(displayUnitID)
		if mySpec or (myTeamID ~= teamID) then
			local _, playerID, _, isAiTeam = Spring.GetTeamInfo(teamID, false)
			local name = Spring.GetPlayerInfo(playerID, false)
			name = ((WG.playernames and WG.playernames.getPlayername) and WG.playernames.getPlayername(playerID))
				or name
			if isAiTeam then
				name = GetAIName(teamID)
			end
			if not mySpec and Spring.GetModOptions().teamcolors_anonymous_mode ~= "disabled" then
				name = anonymousName
			end
			if name then
				local fontSizeOwner = fontSize * 0.87
				--if not mySpec and Spring.GetModOptions().teamcolors_anonymous_mode ~= 'disabled' then
				--	name = ColourString(Spring.GetConfigInt("anonymousColorR", 255)/255, Spring.GetConfigInt("anonymousColorG", 0)/255, Spring.GetConfigInt("anonymousColorB", 0)/255) .. name
				--else
				name = spColorString(Spring.GetTeamColor(teamID)) .. name
				--end
				font2:Print(
					name,
					backgroundRect[3] - bgpadding - bgpadding,
					backgroundRect[2] + (fontSizeOwner * 0.44),
					fontSizeOwner,
					"or"
				)
			end
		end
	else
		valueY3 = healthColor .. unitDefInfo[displayUnitDefID].health
	end
	tracy.ZoneEnd()

	tracy.ZoneBeginN("W:Info:DrawUnitInfo:ResourceIcons")
	glColor(1, 1, 1, 1)
	local texDetailSize = math_floor(texSize * 4)
	if valueY1 ~= "" then
		glTexture(":lr" .. texDetailSize .. "," .. texDetailSize .. ":LuaUI/Images/metal.png")
		glTexRect(
			backgroundRect[1] + contentPaddingLeft - (texSize * 0.6),
			posY1 - texSize,
			backgroundRect[1] + contentPaddingLeft + (texSize * 1.4),
			posY1 + texSize
		)
	end
	if valueY2 ~= "" then
		glTexture(":lr" .. texDetailSize .. "," .. texDetailSize .. ":LuaUI/Images/energy.png")
		glTexRect(
			backgroundRect[1] + contentPaddingLeft - (texSize * 0.6),
			posY2 - texSize,
			backgroundRect[1] + contentPaddingLeft + (texSize * 1.4),
			posY2 + texSize
		)
	end
	if valueY3 ~= "" then
		glTexture(":lr" .. texDetailSize .. "," .. texDetailSize .. ":LuaUI/Images/info_health.png")
		glTexRect(
			backgroundRect[1] + contentPaddingLeft - (texSize * 0.6),
			posY3 - texSize,
			backgroundRect[1] + contentPaddingLeft + (texSize * 1.4),
			posY3 + texSize
		)
	end
	glTexture(false)

	-- metal
	local fontSize2 = fontSize * 0.87
	local contentPaddingLeft = contentPaddingLeft + texSize + (contentPadding * 0.5)
	font2:Print(valueY1, backgroundRect[1] + contentPaddingLeft, posY1 - (fontSize2 * 0.31), fontSize2, "o")
	-- energy
	font2:Print(valueY2, backgroundRect[1] + contentPaddingLeft, posY2 - (fontSize2 * 0.31), fontSize2, "o")
	-- health
	font2:Print(valueY3, backgroundRect[1] + contentPaddingLeft, posY3 - (fontSize2 * 0.31), fontSize2, "o")
	font2:End()
	tracy.ZoneEnd()

	cellRect = nil

	-- draw unit buildoption icons
	if
		displayMode == "unitdef"
		and showBuilderBuildlist
		and unitDefInfo[displayUnitDefID].buildOptions
		and not hideBuildlist
	then
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:BuildOptions")
		gridHeight = math_ceil(height * 0.975)
		local rows = 2
		local colls = math_ceil(#unitDefInfo[displayUnitDefID].buildOptions / rows)
		cellsize = math_floor((math_min(width / colls, gridHeight / rows)) + 0.5)
		if cellsize < gridHeight / 3 then
			rows = 3
			colls = math_ceil(#unitDefInfo[displayUnitDefID].buildOptions / rows)
			cellsize = math_floor((math_min(width / colls, gridHeight / rows)) + 0.5)
		end

		-- draw grid (bottom right to top left)
		local cellID = #unitDefInfo[displayUnitDefID].buildOptions
		cellPadding = math_floor((cellsize * 0.022) + 0.5)
		-- Clear and reuse cellRect table
		if not cellRect then
			cellRect = {}
		else
			for i = #cellRect, 1, -1 do
				cellRect[i] = nil
			end
		end
		for row = 1, rows do
			for coll = 1, colls do
				if unitDefInfo[displayUnitDefID].buildOptions[cellID] then
					local uDefID = unitDefInfo[displayUnitDefID].buildOptions[cellID]
					cellRect[cellID] = {
						math_floor(customInfoArea[3] - cellPadding - (coll * cellsize)),
						math_floor(customInfoArea[2] + cellPadding + ((row - 1) * cellsize)),
						math_floor(customInfoArea[3] - cellPadding - ((coll - 1) * cellsize)),
						math_floor(customInfoArea[2] + cellPadding + (row * cellsize)),
					}
					local disabled = (unitRestricted[uDefID] or unitDisabled[uDefID])
					if disabled then
						glColor(0.4, 0.4, 0.4, 1)
					else
						glColor(1, 1, 1, 1)
					end
					UiUnit(
						cellRect[cellID][1] + cellPadding,
						cellRect[cellID][2] + cellPadding,
						cellRect[cellID][3],
						cellRect[cellID][4],
						cellPadding * 1.3,
						1,
						1,
						1,
						1,
						0.1,
						nil,
						disabled and 0 or nil,
						"#" .. uDefID,
						(unitDefInfo[uDefID].icontype and ":l:" .. unitDefInfo[uDefID].icontype or nil),
						groups[unitGroup[uDefID]],
						{ unitDefInfo[uDefID].metalCost, unitDefInfo[uDefID].energyCost }
					)
				end
				cellID = cellID - 1
				if cellID <= 0 then
					break
				end
			end
			if cellID <= 0 then
				break
			end
		end
		glTexture(false)
		glColor(1, 1, 1, 1)
		tracy.ZoneEnd()

		-- draw transported unit list
	elseif
		displayMode == "unit"
		and unitDefInfo[displayUnitDefID].transport
		and (Spring.GetUnitIsTransporting(displayUnitID) and #Spring.GetUnitIsTransporting(displayUnitID) or 0) > 0
	then
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:Transported")
		local units = Spring.GetUnitIsTransporting(displayUnitID)
		if #units > 0 then
			gridHeight = math_ceil(height * 0.975)
			local rows = 2
			local colls = math_ceil(#units / rows)
			cellsize = math_floor((math_min(width / colls, gridHeight / rows)) + 0.5)
			if cellsize < gridHeight / 3 then
				rows = 3
				colls = math_ceil(#units / rows)
				cellsize = math_floor((math_min(width / colls, gridHeight / rows)) + 0.5)
			end

			-- draw grid (bottom right to top left)
			local cellID = #units
			cellPadding = math_floor((cellsize * 0.022) + 0.5)
			cornerSize = math_max(1, cellPadding * 0.9)
			-- Clear and reuse cellRect table
			if not cellRect then
				cellRect = {}
			else
				for i = #cellRect, 1, -1 do
					cellRect[i] = nil
				end
			end
			for row = 1, rows do
				for coll = 1, colls do
					if units[cellID] then
						local uDefID = spGetUnitDefID(units[cellID])
						cellRect[cellID] = {
							math_floor(customInfoArea[3] - cellPadding - (coll * cellsize)),
							math_floor(customInfoArea[2] + cellPadding + ((row - 1) * cellsize)),
							math_floor(customInfoArea[3] - cellPadding - ((coll - 1) * cellsize)),
							math_floor(customInfoArea[2] + cellPadding + (row * cellsize)),
						}
						UiUnit(
							cellRect[cellID][1] + cellPadding,
							cellRect[cellID][2] + cellPadding,
							cellRect[cellID][3],
							cellRect[cellID][4],
							cellPadding * 1.3,
							1,
							1,
							1,
							1,
							0.1,
							nil,
							nil,
							"#" .. uDefID,
							(unitDefInfo[uDefID].icontype and ":l:" .. unitDefInfo[uDefID].icontype or nil),
							groups[unitGroup[uDefID]],
							{ unitDefInfo[uDefID].metalCost, unitDefInfo[uDefID].energyCost }
						)
					end
					cellID = cellID - 1
					if cellID <= 0 then
						break
					end
				end
				if cellID <= 0 then
					break
				end
			end
			glTexture(false)
			glColor(1, 1, 1, 1)
		end
		tracy.ZoneEnd()
	else
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:StatsText")
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:StatsText:Collect")
		-- unit/unitdef info (without buildoptions)

		contentPadding = contentPadding * 0.95
		local contentPaddingLeft = customInfoArea[1] + contentPadding

		-- Use string buffer for concatenation to reduce allocations
		clearStringBuffer()
		local bufferIndex = 0
		local separator = ""
		local infoFontsize = fontSize * 0.89
		-- to determine what to show in what order
		local function addTextInfo(label, value)
			bufferIndex = bufferIndex + 1
			stringBuffer[bufferIndex] = labelColor
			bufferIndex = bufferIndex + 1
			stringBuffer[bufferIndex] = separator
			bufferIndex = bufferIndex + 1
			stringBuffer[bufferIndex] = string.upper(label:sub(1, 1))
			bufferIndex = bufferIndex + 1
			stringBuffer[bufferIndex] = label:sub(2)
			bufferIndex = bufferIndex + 1
			stringBuffer[bufferIndex] = valueColor
			if value and label ~= "" then
				bufferIndex = bufferIndex + 1
				stringBuffer[bufferIndex] = " "
				bufferIndex = bufferIndex + 1
				stringBuffer[bufferIndex] = value
			end
			separator = ",   "
		end

		-- unit specific info
		if unitDefInfo[displayUnitDefID].mindps then
			mindps = unitDefInfo[displayUnitDefID].mindps
		end
		if unitDefInfo[displayUnitDefID].maxdps then
			maxdps = unitDefInfo[displayUnitDefID].maxdps
		end
		if unitDefInfo[displayUnitDefID].minemp then
			minemp = unitDefInfo[displayUnitDefID].minemp
		end
		if unitDefInfo[displayUnitDefID].maxemp then
			maxemp = unitDefInfo[displayUnitDefID].maxemp
		end
		if unitDefInfo[displayUnitDefID].range then
			range = unitDefInfo[displayUnitDefID].range
		end

		-- get unit specific data
		if displayMode == "unit" then
			-- get lots of unit info from functions: https://springrts.com/wiki/Lua_SyncedRead
			if unitDefInfo[displayUnitDefID].mainWeapon ~= nil then
				maxRange = Spring.GetUnitWeaponState(displayUnitID, unitDefInfo[displayUnitDefID].mainWeapon, "range")
			else
				maxRange = range
			end
			if not exp then
				exp = spGetUnitExperience(displayUnitID)
			end
		else
			-- get unitdef specific data
			if unitDefInfo[displayUnitDefID].maxWeaponRange then
				maxRange = range
			end
		end

		if unitDefInfo[displayUnitDefID].weapons then
			local reloadTimeSpeedup = 1.0
			local currentReloadTime = unitDefInfo[displayUnitDefID].reloadTime
			if exp and exp > 0.009 then
				addTextInfo(BAR.I18N("ui.info.xp"), round(exp, 2))
				addTextInfo(
					BAR.I18N("ui.info.maxhealth"),
					"+" .. round((maxHealth / unitDefInfo[displayUnitDefID].health - 1) * 100, 0) .. "%"
				)
				currentReloadTime =
					spGetUnitWeaponState(displayUnitID, unitDefInfo[displayUnitDefID].mainWeapon, "reloadTimeXP")
				if unitDefInfo[displayUnitDefID].reloadTime then
					reloadTimeSpeedup = currentReloadTime / unitDefInfo[displayUnitDefID].reloadTime
					local reloadTimeSpeedupPercentage = tonumber(round((1 - reloadTimeSpeedup) * 100, 0))
					if reloadTimeSpeedupPercentage > 0 then
						addTextInfo(BAR.I18N("ui.info.reload"), "-" .. reloadTimeSpeedupPercentage .. "%")
					end
				end
			end

			-- basic dps display
			if mindps and mindps > 0 and mindps == maxdps then
				local dps = round(mindps / reloadTimeSpeedup, 0)
				addTextInfo(BAR.I18N("ui.info.dps"), dps)

			-- dps range
			elseif mindps ~= maxdps then
				local min = round(mindps / reloadTimeSpeedup, 0)
				local max = round(maxdps / reloadTimeSpeedup, 0)
				addTextInfo("DPS", min .. "-" .. max)
			end

			-- emp dps display
			if minemp and minemp > 0 and minemp == maxemp then
				local emp = round(minemp / reloadTimeSpeedup, 0)
				addTextInfo("DPS(EMP)", emp)

			-- more emp dps
			elseif minemp ~= maxemp then
				local min = round(minemp / reloadTimeSpeedup, 0)
				local max = round(maxemp / reloadTimeSpeedup, 0)
				addTextInfo("DPS(EMP)", min .. "-" .. max)
			end

			if unitDefInfo[displayUnitDefID].maxCoverage then
				addTextInfo(BAR.I18N("ui.info.coverrange"), unitDefInfo[displayUnitDefID].maxCoverage)
			elseif maxRange and not unitDefInfo[displayUnitDefID].shieldOnly then
				addTextInfo(BAR.I18N("ui.info.weaponrange"), math_floor(maxRange))
			end
			if currentReloadTime and currentReloadTime > 0 then
				addTextInfo(BAR.I18N("ui.info.reloadtime"), round(currentReloadTime, 2))
			end

			if unitDefInfo[displayUnitDefID].energyPerShot then
				addTextInfo(BAR.I18N("ui.info.energyshot"), unitDefInfo[displayUnitDefID].energyPerShot)
			end
			if unitDefInfo[displayUnitDefID].metalPerShot then
				addTextInfo(BAR.I18N("ui.info.metalshot"), unitDefInfo[displayUnitDefID].metalPerShot)
			end
		end
		-- shield display
		if unitDefInfo[displayUnitDefID].shieldCapacity then
			addTextInfo(BAR.I18N("ui.info.shieldcapacity"), unitDefInfo[displayUnitDefID].shieldCapacity)
			addTextInfo(BAR.I18N("ui.info.shieldrange"), unitDefInfo[displayUnitDefID].shieldRange)
			addTextInfo(BAR.I18N("ui.info.shieldrechargerate"), unitDefInfo[displayUnitDefID].shieldRechargeRate)
			addTextInfo(BAR.I18N("ui.info.shieldrechargecost"), unitDefInfo[displayUnitDefID].shieldRechargeCost)
		end

		if unitDefInfo[displayUnitDefID].stealth then
			addTextInfo(BAR.I18N("ui.info.stealthy"), nil)
		end

		if unitDefInfo[displayUnitDefID].cloakCost then
			if unitDefInfo[displayUnitDefID].cloakCostMoving then
				addTextInfo(
					BAR.I18N("ui.info.cloakcost"),
					unitDefInfo[displayUnitDefID].cloakCost .. "/" .. unitDefInfo[displayUnitDefID].cloakCostMoving
				)
			else
				addTextInfo(BAR.I18N("ui.info.cloakcost"), unitDefInfo[displayUnitDefID].cloakCost)
			end
		end

		if unitDefInfo[displayUnitDefID].speed then
			addTextInfo(BAR.I18N("ui.info.speed"), unitDefInfo[displayUnitDefID].speed)
		elseif unitDefInfo[displayUnitDefID].speedMin then
			local min = unitDefInfo[displayUnitDefID].speedMin
			local max = unitDefInfo[displayUnitDefID].speedMax
			addTextInfo(BAR.I18N("ui.info.speed"), min .. "-" .. max)
		end
		if unitDefInfo[displayUnitDefID].reverseSpeed then
			addTextInfo(BAR.I18N("ui.info.reversespeed"), unitDefInfo[displayUnitDefID].reverseSpeed)
		end

		if unitDefInfo[displayUnitDefID].buildSpeed then
			addTextInfo(BAR.I18N("ui.info.buildpower"), unitDefInfo[displayUnitDefID].buildSpeed)
		end

		--if unitDefInfo[displayUnitDefID].armorType and unitDefInfo[displayUnitDefID].armorType ~= 'standard' then
		--	addTextInfo('armor', unitDefInfo[displayUnitDefID].armorType)
		--end

		if unitDefInfo[displayUnitDefID].sightDistance then
			addTextInfo(BAR.I18N("ui.info.los"), round(unitDefInfo[displayUnitDefID].sightDistance, 0))
		end
		if
			unitDefInfo[displayUnitDefID].airSightDistance
			and (unitDefInfo[displayUnitDefID].airUnit or unitDefInfo[displayUnitDefID].isAaUnit)
		then
			addTextInfo(BAR.I18N("ui.info.airlos"), round(unitDefInfo[displayUnitDefID].airSightDistance, 0))
		end
		if unitDefInfo[displayUnitDefID].radarDistance then
			addTextInfo(BAR.I18N("ui.info.radar"), round(unitDefInfo[displayUnitDefID].radarDistance, 0))
		end
		if unitDefInfo[displayUnitDefID].sonarDistance then
			addTextInfo(BAR.I18N("ui.info.sonar"), round(unitDefInfo[displayUnitDefID].sonarDistance, 0))
		end
		if unitDefInfo[displayUnitDefID].radarDistanceJam then
			addTextInfo(BAR.I18N("ui.info.jamrange"), round(unitDefInfo[displayUnitDefID].radarDistanceJam, 0))
		end
		if unitDefInfo[displayUnitDefID].sonarDistanceJam then
			addTextInfo(BAR.I18N("ui.info.sonarjamrange"), round(unitDefInfo[displayUnitDefID].sonarDistanceJam, 0))
		end
		if unitDefInfo[displayUnitDefID].seismicDistance then
			addTextInfo(BAR.I18N("ui.info.seismic"), unitDefInfo[displayUnitDefID].seismicDistance)
		end
		--addTextInfo('mass', round(Spring.GetUnitMass(displayUnitID),0))
		--addTextInfo('radius', round(Spring.GetUnitRadius(displayUnitID),0))
		--addTextInfo('height', round(Spring.GetUnitHeight(displayUnitID),0))

		if unitDefInfo[displayUnitDefID].metalmaker then
			addTextInfo(BAR.I18N("ui.info.eneededforconversion"), unitDefInfo[displayUnitDefID].metalmaker[1])
			addTextInfo(
				BAR.I18N("ui.info.convertedm"),
				round(
					unitDefInfo[displayUnitDefID].metalmaker[1] / (1 / unitDefInfo[displayUnitDefID].metalmaker[2]),
					1
				)
			)
		end
		if unitDefInfo[displayUnitDefID].energyStorage > 0 then
			addTextInfo(BAR.I18N("ui.info.estorage"), unitDefInfo[displayUnitDefID].energyStorage)
		end
		if unitDefInfo[displayUnitDefID].metalStorage > 0 then
			addTextInfo(BAR.I18N("ui.info.mstorage"), unitDefInfo[displayUnitDefID].metalStorage)
		end

		if unitDefInfo[displayUnitDefID].transport then
			if unitDefInfo[displayUnitDefID].transport[1] < 5001 then
				addTextInfo(BAR.I18N("ui.info.transport_light", { highlightColor = valueColor }), nil)
			end
			if unitDefInfo[displayUnitDefID].transport[1] > 5000 then
				addTextInfo(BAR.I18N("ui.info.transport_heavy", { highlightColor = valueColor }), nil)
			end
			addTextInfo(BAR.I18N("ui.info.transportcapacity"), unitDefInfo[displayUnitDefID].transport[3])
		end
		tracy.ZoneEnd()

		-- Build final text from buffer
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:StatsText:Wrap")
		local text = table.concat(stringBuffer)
		text, _ = font:WrapText(
			text,
			((backgroundRect[3] - bgpadding - bgpadding - bgpadding) - (backgroundRect[1] + contentPaddingLeft))
				* (loadedFontSize / infoFontsize)
		)

		-- prune number of lines
		local lines = string_lines(text)
		clearStringBuffer()
		bufferIndex = 0
		for i, line in pairs(lines) do
			bufferIndex = bufferIndex + 1
			stringBuffer[bufferIndex] = line
			-- only 4 fully fit, but showing 5, so the top part of text shows and indicates there is more to see somehow
			if i == 5 then
				break
			end
			if i < 5 then
				bufferIndex = bufferIndex + 1
				stringBuffer[bufferIndex] = "\n"
			end
		end
		text = table.concat(stringBuffer)
		lines = nil
		tracy.ZoneEnd()

		-- display unit(def) info text
		tracy.ZoneBeginN("W:Info:DrawUnitInfo:StatsText:Print")
		font:Begin(true)
		font:SetTextColor(1, 1, 1, 1)
		font:SetOutlineColor(0.1, 0.1, 0.1, 1)
		font:Print(
			text,
			customInfoArea[3] - width + (width * 0.025),
			customInfoArea[4] - contentPadding - (infoFontsize * 0.55),
			infoFontsize,
			"o"
		)
		font:End()
		tracy.ZoneEnd()

		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

local function drawEngineTooltip()
	tracy.ZoneBeginN("W:Info:DrawEngineTooltip")
	local mouseX, mouseY, lmb, mmb, rmb, mouseOffScreen, cameraPanMode = spGetMouseState()
	if not cameraPanMode and not mouseOffScreen then
		local fontSize = (height * vsy * 0.11) * (0.95 - ((1 - ui_scale) * 0.5))
		if showEngineTooltip then
			-- display default plaintext engine tooltip
			local text, _ = font:WrapText(currentTooltip, contentWidth * (loadedFontSize / fontSize))
			font:Begin(true)
			font:SetTextColor(1, 1, 1, 1)
			font:SetOutlineColor(0.1, 0.1, 0.1, 1)
			font:Print(
				text,
				backgroundRect[1] + contentPadding,
				backgroundRect[4] - contentPadding - (fontSize * 0.8),
				fontSize,
				"o"
			)
			font:End()
		else
			local heightStep = (fontSize * 1.4)
			-- Only trace screen ray if we don't have a custom hover (e.g., from PIP window)
			if not customHoverType then
				hoverType, hoverData = spTraceScreenRay(mouseX, mouseY)
			end
			if hoverType == "ground" then
				local desc, coords = spTraceScreenRay(mouseX, mouseY, true)
				local groundType1, groundType2, metal, hardness, tankSpeed, botSpeed, hoverSpeed, shipSpeed, receiveTracks =
					Spring.GetGroundInfo(coords[1], coords[3])
				local text = ""
				local height = 0
				font:Begin(true)
				font:SetTextColor(1, 1, 1, 1)
				font:SetOutlineColor(0.1, 0.1, 0.1, 1)
				if displayMapPosition then
					font:Print(
						tooltipValueColor .. math.floor(hoverData[1]) .. ",",
						backgroundRect[1] + contentPadding,
						backgroundRect[4] - contentPadding - (fontSize * 0.8) - height,
						fontSize,
						"o"
					)
					font:Print(
						math.floor(hoverData[3]),
						backgroundRect[1] + contentPadding + (fontSize * 3.2),
						backgroundRect[4] - contentPadding - (fontSize * 0.8) - height,
						fontSize,
						"o"
					)
					font:Print(
						tooltipLabelTextColor
							.. BAR.I18N("ui.info.elevation")
							.. "  "
							.. tooltipValueColor
							.. math.floor(Spring.GetGroundHeight(coords[1], coords[3])),
						backgroundRect[1] + contentPadding + (fontSize * 6.6),
						backgroundRect[4] - contentPadding - (fontSize * 0.8) - height,
						fontSize,
						"o"
					)
					height = height + heightStep
				end
				if tankSpeed ~= 1 or botSpeed ~= 1 or hoverSpeed ~= 1 or (shipSpeed ~= 1 and coords[2] <= 0) then
					text = ""
					if tankSpeed ~= 1 then
						text = text
							.. (text ~= "" and "   " or "")
							.. tooltipLabelTextColor
							.. BAR.I18N("ui.info.tank")
							.. " "
							.. tooltipValueColor
							.. math.floor(tankSpeed * 100)
							.. "%"
					end
					if botSpeed ~= 1 then
						text = text
							.. (text ~= "" and "   " or "")
							.. tooltipLabelTextColor
							.. BAR.I18N("ui.info.bot")
							.. " "
							.. tooltipValueColor
							.. math.floor(botSpeed * 100)
							.. "%"
					end
					if hoverSpeed ~= 1 then
						text = text
							.. (text ~= "" and "   " or "")
							.. tooltipLabelTextColor
							.. BAR.I18N("ui.info.hover")
							.. " "
							.. tooltipValueColor
							.. math.floor(hoverSpeed * 100)
							.. "%"
					end
					if shipSpeed ~= 1 and coords[2] <= 0 then
						text = text
							.. (text ~= "" and "   " or "")
							.. tooltipLabelTextColor
							.. BAR.I18N("ui.info.ship")
							.. " "
							.. tooltipValueColor
							.. math.floor(shipSpeed * 100)
							.. "%"
					end
					if groundType2 and groundType2 ~= "" then
						font2:Begin(true)
						font2:SetOutlineColor(0, 0, 0, 1)
						font2:Print(
							tooltipLabelTextColor .. groundType2,
							backgroundRect[1] + contentPadding,
							backgroundRect[4] - contentPadding - (fontSize * 1) - height,
							(fontSize * 1.2),
							"o"
						)
						font2:End()
						height = height + (fontSize * 0.25)
						height = height + heightStep
					end
					font:Print(
						tooltipDarkTextColor .. BAR.I18N("ui.info.speedmultipliers") .. "   " .. text,
						backgroundRect[1] + contentPadding,
						backgroundRect[4] - contentPadding - (fontSize * 0.8) - height,
						fontSize,
						"o"
					)
				elseif not displayMapPosition then
					emptyInfo = true
				end
				--if metal > 0 then
				--	height = height + heightStep
				--	font:Print(tooltipLabelTextColor..Spring.I18N('ui.info.metal')..' '..tooltipValueColor..math.floor(metal), backgroundRect[1] + contentPadding, backgroundRect[4] - contentPadding - (fontSize * 0.8) - height, fontSize, "o")
				--end
				--if hardness ~= 1 then
				--	height = height + heightStep
				--	font:Print(tooltipLabelTextColor..Spring.I18N('ui.info.hardness')..' '..tooltipValueColor..math.floor(hardness), backgroundRect[1] + contentPadding, backgroundRect[4] - contentPadding - (fontSize * 0.8) - height, fontSize, "o")
				--end
				font:End()
			elseif hoverType == "feature" then
				local featureDefID = Spring.GetFeatureDefID(hoverData)
				local text = FeatureDefs[featureDefID].tooltip
				local height = 0
				if text == "" then
					text = FeatureDefs[featureDefID].translatedDescription
				end
				if text and text ~= "" then
					font2:Begin(true)
					font2:SetOutlineColor(0, 0, 0, 1)
					font2:Print(
						tooltipTitleColor .. text,
						backgroundRect[1] + contentPadding,
						backgroundRect[4] - contentPadding - (fontSize * 1.2) - height,
						(fontSize * 1.4),
						"o"
					)
					font2:End()
					height = height + (fontSize * 0.5)
				end
				font:Begin(true)
				font:SetTextColor(1, 1, 1, 1)
				font:SetOutlineColor(0.1, 0.1, 0.1, 1)
				text = ""
				local metal, _, energy, _ = Spring.GetFeatureResources(hoverData)
				if energy > 0 then
					height = height + heightStep
					text = tooltipLabelTextColor
						.. BAR.I18N("ui.info.energy")
						.. "  \255\255\255\000"
						.. string.formatSI(energy)
					font:Print(
						text,
						backgroundRect[1] + contentPadding,
						backgroundRect[4] - contentPadding - (fontSize * 0.8) - height,
						fontSize,
						"o"
					)
				end
				if metal > 0 then
					height = height + heightStep
					text = tooltipLabelTextColor
						.. BAR.I18N("ui.info.metal")
						.. "  "
						.. tooltipValueColor
						.. string.formatSI(metal)
					font:Print(
						text,
						backgroundRect[1] + contentPadding,
						backgroundRect[4] - contentPadding - (fontSize * 0.8) - height,
						fontSize,
						"o"
					)
				end
				font:End()
			else
				emptyInfo = true
			end
		end
	else
		if cameraPanMode and #selectedUnits > 0 then
			checkChanges()
		else
			emptyInfo = true
		end
	end
	tracy.ZoneEnd()
end

local function drawInfoBackground()
	UiElement(
		backgroundRect[1],
		backgroundRect[2],
		backgroundRect[3],
		backgroundRect[4],
		0,
		1,
		0,
		0,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil
	)
end

local function drawInfo()
	tracy.ZoneBeginN("W:Info:DrawInfo")
	emptyInfo = false

	contentPadding = (height * vsy * 0.075) * (0.95 - ((1 - ui_scale) * 0.5))
	contentWidth = backgroundRect[3] - backgroundRect[1] - contentPadding - contentPadding

	if displayMode == "selection" then
		drawSelection()
	elseif displayMode ~= "text" and displayUnitDefID then
		drawUnitInfo()
	else
		drawEngineTooltip()
	end
	tracy.ZoneEnd()
end

local function LeftMouseButton(unitDefID, unitTable)
	local alt, ctrl, meta, shift = spGetModKeyState()
	local acted = false
	if not ctrl then
		-- select units of icon type
		if alt or meta then
			acted = true
			spSelectUnitArray({ unitTable[1] }) -- only 1
		else
			acted = true
			spSelectUnitArray(unitTable)
		end
	else
		-- select all units of the icon type
		local sorted = spGetTeamUnitsSorted(myTeamID)
		local units = sorted[unitDefID]
		if units then
			acted = true
			spSelectUnitArray(units, shift)
		end
	end
	selectedUnits = spGetSelectedUnits()
	SelectedUnitsCount = spGetSelectedUnitsCount()
	if acted then
		Spring.PlaySoundFile(sound_button, 0.5, "ui")
	end
end

local function MiddleMouseButton(unitDefID, unitTable)
	local _, ctrl, _, _ = spGetModKeyState()
	if ctrl then
		-- center the view on the entire selection
		Spring.SendCommands(viewSelectionCmd)
	else
		-- center the view on this type on unit
		spSelectUnitArray(unitTable)
		Spring.SendCommands(viewSelectionCmd)
		spSelectUnitArray(selectedUnits)
	end
	selectedUnits = spGetSelectedUnits()
	SelectedUnitsCount = spGetSelectedUnitsCount()
	Spring.PlaySoundFile(sound_button, 0.5, "ui")
end

local function RightMouseButton(unitDefID, unitTable)
	local _, ctrl, _, _ = spGetModKeyState()

	-- remove selected units of icon type
	-- Clear and reuse map table instead of creating new one
	for k in pairs(rightMouseButtonMap) do
		rightMouseButtonMap[k] = nil
	end
	for i = 1, #selectedUnits do
		rightMouseButtonMap[selectedUnits[i]] = true
	end
	for _, uid in ipairs(unitTable) do
		rightMouseButtonMap[uid] = nil
		if ctrl then
			break -- only remove 1 unit
		end
	end
	spSelectUnitMap(rightMouseButtonMap)
	selectedUnits = spGetSelectedUnits()
	SelectedUnitsCount = spGetSelectedUnitsCount()
	Spring.PlaySoundFile(sound_button2, 0.5, "ui")
end

function widget:MousePress(x, y, button)
	if Spring.IsGUIHidden() then
		return
	end
	if
		infoShows and math_isInRect(x, y, backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4])
	then
		return true
	end
end

-- makes sure it gets unloaded at a free spot
local mapSizeX, mapSizeZ = Game.mapSizeX, Game.mapSizeZ
local function unloadTransport(transportID, unitID, x, z, shift, depth)
	if not depth then
		depth = 1
	end
	local radius = 20 * depth
	local orgX, orgZ = x, z
	local y = Spring.GetGroundHeight(x, z)
	local unitSphereRadius = 60 -- too low value will result in unload conflicts
	local areaUnits = Spring.GetUnitsInSphere(x, y, z, unitSphereRadius)
	if #areaUnits == 0 then -- unblocked spot!
		unloadParams[1], unloadParams[2], unloadParams[3], unloadParams[4] = x, y, z, unitID
		Spring.GiveOrderToUnit(transportID, CMD.UNLOAD_UNIT, unloadParams, shift and shiftTable or emptyTable)
	else
		-- unload is blocked by unit at ground just lets find free alternative spot in a radius around it
		local samples = 8
		local sideAngle = (math.pi * 2) / samples
		local foundUnloadSpot = false
		for i = 1, samples + 1 do
			x = x + (radius * math.cos(i * sideAngle))
			z = z + (radius * math.sin(i * sideAngle))
			if x > 0 and z > 0 and x < mapSizeX and z < mapSizeZ then
				y = Spring.GetGroundHeight(x, z)
				areaUnits = Spring.GetUnitsInSphere(x, y, z, unitSphereRadius)
				if #areaUnits == 0 then -- unblocked spot!
					local areaFeatures = Spring.GetFeaturesInSphere(x, y, z, unitSphereRadius)
					if #areaFeatures == 0 then
						unloadParams[1], unloadParams[2], unloadParams[3], unloadParams[4] = x, y, z, unitID
						Spring.GiveOrderToUnit(
							transportID,
							CMD.UNLOAD_UNIT,
							unloadParams,
							shift and shiftTable or emptyTable
						)
						foundUnloadSpot = true
						break
					end
				end
			end
		end
		-- try again with increased radius
		if not foundUnloadSpot and depth < 15 then -- limit depth for safety
			unloadTransport(transportID, unitID, orgX, orgZ, shift, depth + 1)
		end
	end
end

function widget:MouseRelease(x, y, button)
	if Spring.IsGUIHidden() then
		return
	end

	if
		displayMode
		and customInfoArea
		and math_isInRect(x, y, customInfoArea[1], customInfoArea[2], customInfoArea[3], customInfoArea[4])
	then
		-- selection
		if displayMode == "selection" and selectionCells and selectionCells[1] and cellRect then
			for cellID, unitDefID in pairs(selectionCells) do
				if
					cellRect[cellID]
					and math_isInRect(
						x,
						y,
						cellRect[cellID][1],
						cellRect[cellID][2],
						cellRect[cellID][3],
						cellRect[cellID][4]
					)
				then
					local unitTable = nil
					local index = 0
					for udid, uTable in pairs(selUnitsSorted) do
						if udid == unitDefID then
							unitTable = uTable
							break
						end
						index = index + 1
					end
					if unitTable == nil then
						return -1
					end

					if button == 1 then
						LeftMouseButton(unitDefID, unitTable)
					elseif button == 2 then
						MiddleMouseButton(unitDefID, unitTable)
					elseif button == 3 then
						RightMouseButton(unitDefID, unitTable)
					end
					return -1
				end
			end
		end

		-- transported unit list
		if displayMode == "unit" and button == 1 then
			local units = Spring.GetUnitIsTransporting(displayUnitID)
			if units and #units > 0 then
				for cellID, unitID in pairs(units) do
					if
						cellRect[cellID]
						and math_isInRect(
							x,
							y,
							cellRect[cellID][1],
							cellRect[cellID][2],
							cellRect[cellID][3],
							cellRect[cellID][4]
						)
					then
						local x, y, z = Spring.GetUnitPosition(displayUnitID)
						local alt, ctrl, meta, shift = spGetModKeyState()
						if shift then
							local cmdQueue = Spring.GetUnitCommands(displayUnitID, 35) or {}
							if cmdQueue[1] then
								if
									cmdQueue[#cmdQueue]
									and cmdQueue[#cmdQueue].id == CMD.MOVE
									and cmdQueue[#cmdQueue].params[3]
								then
									x, z = cmdQueue[#cmdQueue].params[1], cmdQueue[#cmdQueue].params[3]
									-- remove the last move command (to replace it with the unload cmd after)
									Spring.GiveOrderToUnit(displayUnitID, CMD.STOP, emptyTable, 0)
									for c = 1, #cmdQueue do
										if c < #cmdQueue then
											Spring.GiveOrderToUnit(
												displayUnitID,
												cmdQueue[c].id,
												cmdQueue[c].params,
												shiftTable
											)
										end
									end
								end
							end
						end
						unloadTransport(displayUnitID, unitID, math_floor(x), math_floor(z), shift)
						return -1
					end
				end
			end
		end
	end
	return -1
end

function widget:DrawScreen()
	tracy.ZoneBeginN("W:Info:DrawScreen")
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	local x, y, b, b2, b3, mouseOffScreen, cameraPanMode = spGetMouseState()

	if not alwaysShow and (cameraPanMode or mouseOffScreen) and SelectedUnitsCount == 0 and not isPregame then
		if dlistGuishader then
			WG.guishader.DeleteDlist("info")
			dlistGuishader = nil
		end
		tracy.ZoneEnd()
		return
	end

	if not infoBgTex then
		tracy.ZoneBeginN("W:Info:DrawScreen:CreateBackgroundTexture")
		infoBgTex = gl.CreateTexture(math_floor(width * vsx), math_floor(height * vsy), {
			target = GL.TEXTURE_2D,
			format = GL.RGBA,
			fbo = true,
		})
		gl.R2tHelper.RenderToTexture(infoBgTex, function()
			gl.Translate(-1, -1, 0)
			gl.Scale(2 / (width * vsx), 2 / (height * vsy), 0)
			drawInfoBackground()
		end, true)
		tracy.ZoneEnd()
	end
	if not infoTex then
		tracy.ZoneBeginN("W:Info:DrawScreen:CreateInfoTexture")
		infoTex = gl.CreateTexture(math_floor(width * vsx) * 2, math_floor(height * vsy) * 2, {
			target = GL.TEXTURE_2D,
			format = GL.RGBA,
			fbo = true,
		})
		tracy.ZoneEnd()
	end
	local warmedDisplayUnitpicThisFrame = false
	if
		displayMode ~= "selection"
		and displayUnitDefID
		and unitDefInfo[displayUnitDefID].buildPic
		and not selectionUnitpicWarm.warmed[displayUnitDefID]
	then
		tracy.ZoneBeginN("W:Info:DisplayUnitpicWarmup")
		warmedDisplayUnitpicThisFrame = true
		if glTexture("#" .. displayUnitDefID) then
			selectionUnitpicWarm.warmed[displayUnitDefID] = true
		end
		glTexture(false)
		tracy.ZoneEnd()
	end
	local selectionUnitpicsWarmDone = true
	local warmedSelectionUnitpicThisFrame = false
	if not warmedDisplayUnitpicThisFrame and selectionUnitpicWarm.count > 0 then
		warmedSelectionUnitpicThisFrame = true
		selectionUnitpicsWarmDone = flushSelectionUnitpicWarmQueue()
	end
	if
		infoTex
		and updateTex
		and selectionUnitpicsWarmDone
		and not warmedSelectionUnitpicThisFrame
		and not warmedDisplayUnitpicThisFrame
	then
		tracy.ZoneBeginN("W:Info:DrawScreen:RenderInfoTexture")
		updateTex = nil
		gl.R2tHelper.RenderToTexture(infoTex, function()
			gl.Translate(-1, -1, 0)
			gl.Scale(2 / (width * vsx), 2 / (height * vsy), 0)
			drawInfo()
		end, true)
		tracy.ZoneEnd()
	end

	if alwaysShow or not emptyInfo or (isPregame and (not mySpec or displayMapPosition)) then
		tracy.ZoneBeginN("W:Info:DrawScreen:BlendTextures")
		if infoBgTex then
			-- background element
			gl.R2tHelper.BlendTexRect(
				infoBgTex,
				backgroundRect[1],
				backgroundRect[2],
				backgroundRect[3],
				backgroundRect[4],
				true
			)
		end
		if infoTex then
			-- content
			gl.R2tHelper.BlendTexRect(
				infoTex,
				backgroundRect[1],
				backgroundRect[2],
				backgroundRect[3],
				backgroundRect[4],
				true
			)
		end
		tracy.ZoneEnd()
	elseif dlistGuishader then
		WG.guishader.DeleteDlist("info")
		dlistGuishader = nil
	end

	-- widget hovered
	if
		infoShows and math_isInRect(x, y, backgroundRect[1], backgroundRect[2], backgroundRect[3], backgroundRect[4])
	then
		tracy.ZoneBeginN("W:Info:DrawScreen:Hover")

		Spring.SetMouseCursor("cursornormal")

		-- selection grid
		if displayMode == "selection" and selectionCells and selectionCells[1] and cellRect then
			for cellID, unitDefID in pairs(selectionCells) do
				if
					cellRect[cellID]
					and math_isInRect(
						x,
						y,
						cellRect[cellID][1],
						cellRect[cellID][2],
						cellRect[cellID][3],
						cellRect[cellID][4]
					)
				then
					local cellZoom = hoverCellZoom
					local color = { 1, 1, 1 }
					if b then
						cellZoom = clickCellZoom
						color = { 0.36, 0.8, 0.3 }
					elseif b2 then
						cellZoom = clickCellZoom
						color = { 1, 0.66, 0.1 }
					elseif b3 then
						cellZoom = rightclickCellZoom
						color = { 1, 0.1, 0.1 }
					end
					cellZoom = cellZoom + math_min(0.33 * cellZoom * ((gridHeight / cellsize) - 2), 0.15) -- add extra zoom when small icons
					drawSelectionCell(
						cellID,
						selectionCells[cellID],
						texOffset + cellZoom,
						{ color[1], color[2], color[3], 0.1 }
					)
					-- highlight
					glBlending(GL_SRC_ALPHA, GL_ONE)
					if b or b2 or b3 then
						RectRound(
							cellRect[cellID][1] + cellPadding,
							cellRect[cellID][2] + cellPadding,
							cellRect[cellID][3],
							cellRect[cellID][4],
							cellPadding * 0.9,
							1,
							1,
							1,
							1,
							{ color[1], color[2], color[3], (b or b2 or b3) and 0.4 or 0.2 },
							{ color[1], color[2], color[3], (b or b2 or b3) and 0.07 or 0.04 }
						)
					else
						RectRound(
							cellRect[cellID][1] + cellPadding,
							cellRect[cellID][2] + cellPadding,
							cellRect[cellID][3],
							cellRect[cellID][4],
							cellPadding * 0.9,
							1,
							1,
							1,
							1,
							{ 1, 1, 1, 0.08 },
							{ 1, 1, 1, 0.08 }
						)
					end
					-- light border
					local halfSize = ((cellRect[cellID][3] - cellPadding) - cellRect[cellID][1]) * 0.5
					glBlending(GL_SRC_ALPHA, GL_ONE)
					RectRoundCircle(
						cellRect[cellID][1] + cellPadding + halfSize,
						0,
						cellRect[cellID][2] + cellPadding + halfSize,
						halfSize,
						cornerSize,
						halfSize - math_max(1, cellPadding),
						{ 1, 1, 1, 0.07 },
						{ 1, 1, 1, 0.07 }
					)
					glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

					--cellHovered = cellID
					break
				end
			end

			if WG.tooltip then
				local statsIndent = "  "
				local stats = ""
				--local cells = cellHovered and { [cellHovered] = selectionCells[cellHovered] } or selectionCells
				-- description
				if cellHovered then
					local text, _ = font:WrapText(
						unitDefInfo[selectionCells[cellHovered]].description,
						(backgroundRect[3] - backgroundRect[1]) * (loadedFontSize / 16)
					)
					stats = stats .. statsIndent .. tooltipTextColor .. text .. "\n\n"
				end
				local text
				local textTitle
				stats = "" --getSelectionTotals(cells)
				if cellHovered then
					textTitle = unitDefInfo[selectionCells[cellHovered]].translatedHumanName
						.. tooltipLabelTextColor
						.. (
							selUnitsCounts[selectionCells[cellHovered]] > 1
								and " x " .. tooltipTextColor .. selUnitsCounts[selectionCells[cellHovered]]
							or ""
						)
				else
					--textTitle = Spring.I18N('ui.info.selectedunits')..": " .. tooltipTextColor .. #selectedUnits
					text = selectionHowto
				end

				WG.tooltip.ShowTooltip("info", text, nil, nil, textTitle)
			end
		end

		-- transport load list
		if displayMode == "unit" and unitDefInfo[displayUnitDefID].transport and cellRect then
			local units = Spring.GetUnitIsTransporting(displayUnitID)
			if #units > 0 then
				for cellID, unitID in pairs(units) do
					if
						cellRect[cellID]
						and math_isInRect(
							x,
							y,
							cellRect[cellID][1],
							cellRect[cellID][2],
							cellRect[cellID][3],
							cellRect[cellID][4]
						)
					then
						local cellZoom = hoverCellZoom
						local color = { 1, 1, 1 }
						if b then
							cellZoom = clickCellZoom
							color = { 1, 0.85, 0.1 }
						end
						cellZoom = cellZoom + math_min(0.33 * cellZoom * ((gridHeight / cellsize) - 2), 0.15) -- add extra zoom when small icons

						-- highlight
						glBlending(GL_SRC_ALPHA, GL_ONE)
						if b then
							RectRound(
								cellRect[cellID][1] + cellPadding,
								cellRect[cellID][2] + cellPadding,
								cellRect[cellID][3],
								cellRect[cellID][4],
								cellPadding * 0.9,
								1,
								1,
								1,
								1,
								{ color[1], color[2], color[3], 0.3 },
								{ color[1], color[2], color[3], 0.3 }
							)
						else
							RectRound(
								cellRect[cellID][1] + cellPadding,
								cellRect[cellID][2] + cellPadding,
								cellRect[cellID][3],
								cellRect[cellID][4],
								cellPadding * 0.9,
								1,
								1,
								1,
								1,
								{ 1, 1, 1, 0.08 },
								{ 1, 1, 1, 0.08 }
							)
						end
						-- light border
						local halfSize = ((cellRect[cellID][3] - cellPadding) - cellRect[cellID][1]) * 0.5
						glBlending(GL_SRC_ALPHA, GL_ONE)
						RectRoundCircle(
							cellRect[cellID][1] + cellPadding + halfSize,
							0,
							cellRect[cellID][2] + cellPadding + halfSize,
							halfSize,
							cornerSize,
							halfSize - math_max(1, cellPadding),
							{ 1, 1, 1, 0.07 },
							{ 1, 1, 1, 0.07 }
						)
						glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

						--cellHovered = cellID
						break
					end
				end
			end
		elseif displayMode == "unit" then
			if WG.unitstats and WG.unitstats.showUnit then
				WG.unitstats.showUnit(displayUnitID)
			end
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

function checkChanges()
	tracy.ZoneBeginN("W:Info:CheckChanges")
	hideBuildlist = nil -- only set for pregame startunit
	local x, y, b, _, _, _, cameraPanMode = spGetMouseState()

	-- Use custom hover if provided by external widget (e.g., PIP window)
	-- or skip hover detection if PIP window is above (to prevent showing units below PIP)
	tracy.ZoneBeginN("W:Info:CheckChanges:Hover")
	if customHoverType and customHoverData then
		hoverType = customHoverType
		hoverData = customHoverData
	elseif WG.guiPip and WG.guiPip.IsAbove and WG.guiPip.IsAbove(x, y) then
		-- PIP window is above the cursor, don't detect anything below it
		hoverType = nil
		hoverData = nil
	else
		hoverType, hoverData = spTraceScreenRay(x, y)
	end
	tracy.ZoneEnd()

	local prevDisplayMode = displayMode
	local prevDisplayUnitDefID = displayUnitDefID
	local prevDisplayUnitID = displayUnitID

	-- determine what mode to display
	tracy.ZoneBeginN("W:Info:CheckChanges:ResolveMode")
	displayMode = "text"
	displayUnitID = nil
	displayUnitDefID = nil

	if isPregame and not mySpec then
		activeCmdID = WG["pregame-build"] and WG["pregame-build"].getPreGameDefID()
		activeCmdID = activeCmdID and -activeCmdID
	else
		activeCmdID = select(2, Spring.GetActiveCommand())
	end

	-- buildmenu unitdef
	if WG.buildmenu and WG.buildmenu.hoverID then
		displayMode = "unitdef"
		displayUnitDefID = WG.buildmenu.hoverID
	elseif cfgDisplayUnitDefID then
		displayMode = "unitdef"
		displayUnitDefID = cfgDisplayUnitDefID
	elseif activeCmdID and activeCmdID < 0 then
		displayMode = "unitdef"
		displayUnitDefID = -activeCmdID
	elseif cfgDisplayUnitID and Spring.ValidUnitID(cfgDisplayUnitID) then
		displayMode = "unit"
		displayUnitID = cfgDisplayUnitID
		displayUnitDefID = spGetUnitDefID(displayUnitID)
		if lastUpdateClock + 0.4 < os_clock() then
			-- unit stats could have changed meanwhile
			doUpdate = true
		end

		-- hovered unit
	elseif
		not cameraPanMode
		and not b
		and (customHoverType or not math_isInRect(
			x,
			y,
			backgroundRect[1],
			backgroundRect[2],
			backgroundRect[3],
			backgroundRect[4]
		))
		and hoverType
		and hoverType == "unit"
	then
		displayMode = "unit"
		displayUnitID = hoverData
		displayUnitDefID = spGetUnitDefID(displayUnitID)
		if not displayUnitDefID and SelectedUnitsCount >= 1 then
			if SelectedUnitsCount == 1 then
				displayUnitID = selectedUnits[1]
				displayUnitDefID = spGetUnitDefID(selectedUnits[1])
			else
				displayMode = "selection"
			end
		end
		if lastUpdateClock + 0.4 < os_clock() then
			-- unit stats could have changed meanwhile
			doUpdate = true
		end

		-- hovered feature
	elseif
		not cameraPanMode
		and (customHoverType or not math_isInRect(
			x,
			y,
			backgroundRect[1],
			backgroundRect[2],
			backgroundRect[3],
			backgroundRect[4]
		))
		and hoverType
		and hoverType == "feature"
	then
		displayMode = "feature"
		local featureID = hoverData
		local featureDefID = spGetFeatureDefID(featureID)
		local featureDef = FeatureDefs[featureDefID]
		if featureDef == nil then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return
		end
		local newTooltip = featureDef.translatedDescription or ""

		if featureDef.reclaimable then
			local metal, _, energy, _ = Spring.GetFeatureResources(featureID)
			local reclaimText = BAR.I18N("ui.reclaimInfo.metal", { metal = string.formatSI(metal) })
				.. "\255\255\255\128"
				.. " "
				.. BAR.I18N("ui.reclaimInfo.energy", { energy = string.formatSI(energy) })
			newTooltip = newTooltip .. "\n\n" .. reclaimText
		end

		if newTooltip ~= currentTooltip then
			currentTooltip = newTooltip
			doUpdate = true
		end

		-- selected unit
	elseif SelectedUnitsCount == 1 then
		displayMode = "unit"
		displayUnitID = selectedUnits[1]
		if displayUnitID then
			displayUnitDefID = spGetUnitDefID(displayUnitID)
			if lastUpdateClock + 0.4 < os_clock() then
				-- unit stats could have changed meanwhile
				doUpdate = true
			end
		end
		-- selection
	elseif SelectedUnitsCount > 1 then
		displayMode = "selection"

		-- tooltip text
	else
		local newTooltip = spGetCurrentTooltip()
		if newTooltip ~= currentTooltip then
			currentTooltip = newTooltip
			doUpdate = true
		end
	end

	-- display changed
	if
		prevDisplayMode ~= displayMode
		or prevDisplayUnitDefID ~= displayUnitDefID
		or prevDisplayUnitID ~= displayUnitID
	then
		doUpdate = true
	end

	if displayMode == "text" and isPregame then
		if not mySpec then
			displayMode = "unitdef"
			displayUnitDefID = Spring.GetTeamRulesParam(myTeamID, "startUnit")
			hideBuildlist = true
		else
			emptyInfo = true
		end
	end
	tracy.ZoneEnd()
	tracy.ZoneEnd()
end

function widget:SelectionChanged(sel)
	tracy.ZoneBeginN("W:Info:SelectionChanged")
	local newSelectedUnitsCount = spGetSelectedUnitsCount()
	if SelectedUnitsCount ~= 0 and newSelectedUnitsCount == 0 then
		doUpdate = true
		SelectedUnitsCount = 0
		-- Clear existing table instead of creating new one
		for i = #selectedUnits, 1, -1 do
			selectedUnits[i] = nil
		end
		clearSelectionUnitpicWarmQueue()
	end
	if newSelectedUnitsCount > 0 then
		SelectedUnitsCount = newSelectedUnitsCount
		selectedUnits = sel
		queueSelectionUnitpicWarmFromSelection(sel)
		-- Adaptive throttling: increase delay based on selection size
		local throttleDelay = 0.01
		if newSelectedUnitsCount >= 300 then
			throttleDelay = 0.03
		elseif newSelectedUnitsCount >= 160 then
			throttleDelay = 0.02
		elseif newSelectedUnitsCount >= 80 then
			throttleDelay = 0.015
		end

		local currentTime = os_clock()
		if not doUpdateClock or (currentTime - lastUpdateClock) > throttleDelay then
			doUpdateClock = currentTime + throttleDelay
		end
	end
	if not alwaysShow and select(7, spGetMouseState()) then -- cameraPanMode
		tracy.ZoneBeginN("W:Info:SelectionChanged:CheckChanges")
		checkChanges()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

function widget:LanguageChanged()
	refreshUnitInfo()
	widget:ViewResize()
end

function widget:GetConfigData(data)
	return {
		showBuilderBuildlist = showBuilderBuildlist,
		displayMapPosition = displayMapPosition,
		alwaysShow = alwaysShow,
	}
end

function widget:SetConfigData(data)
	if data.showBuilderBuildlist ~= nil then
		showBuilderBuildlist = data.showBuilderBuildlist
	end
	if data.displayMapPosition ~= nil then
		displayMapPosition = data.displayMapPosition
	end
	if data.alwaysShow ~= nil then
		alwaysShow = data.alwaysShow
	end
end
