local M = {}

local system = VFS.Include("gamedata/system.lua")
local teamOptions = VFS.Include("gamedata/team_options.lua")

local function Echo(...)
	Spring.Echo("[Team Tweaks]", ...)
end

local function DeepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local out = {}
	seen[value] = out

	for k, v in pairs(value) do
		out[DeepCopy(k, seen)] = DeepCopy(v, seen)
	end

	return out
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function SanitizeName(name)
	return tostring(name):lower():gsub("[^a-z0-9_]", "_")
end

local function TeamName(slot, original)
	return "rg_t" .. tostring(slot) .. "_" .. SanitizeName(original)
end

local function ParseTweaksForSlot(slot)
	local options = teamOptions.GetOptions(slot) or {}
	local tweaks = {}

	for name, value in pairs(options) do
		local tweakType = name:match("^tweak([a-z]+)%d*$")
		local index = tonumber(name:match("^tweak[a-z]+(%d*)$")) or 0

		if (tweakType == "defs" or tweakType == "units") and value and value ~= "" then
			tweaks[#tweaks + 1] = {
				name = name,
				type = tweakType,
				index = index,
				value = value,
			}
		end
	end

	table.sort(tweaks, function(a, b)
		if a.type == "defs" and b.type == "units" then
			return false
		elseif a.type == "units" and b.type == "defs" then
			return true
		end
		return a.index < b.index
	end)

	return tweaks
end

local function NewTracker(slot)
	local tracker = {
		slot = slot,
		working = {},
		created = {},
		deleted = {},
		reads = {},
		writes = {},
		proxyCache = {},
	}

	local function PathKey(parts)
		local out = {}
		for i = 1, #parts do
			out[i] = tostring(parts[i])
		end
		return table.concat(out, ".")
	end

	local function RecordRead(parts)
		tracker.reads[PathKey(parts)] = true
	end

	local function RecordWrite(parts, value)
		tracker.writes[PathKey(parts)] = value
	end

	local function GetRootValue(unitName)
		if tracker.deleted[unitName] then
			return nil
		end
		if tracker.working[unitName] ~= nil then
			return tracker.working[unitName]
		end
		return UnitDefs[unitName]
	end

	local function EnsureWorking(unitName)
		if tracker.working[unitName] == nil then
			local base = UnitDefs[unitName]
			if base ~= nil then
				tracker.working[unitName] = DeepCopy(base)
			else
				tracker.working[unitName] = {}
				tracker.created[unitName] = true
			end
		end
		tracker.deleted[unitName] = nil
		return tracker.working[unitName]
	end

	local function GetAtPath(unitName, path)
		local current = GetRootValue(unitName)
		if current == nil then
			return nil
		end

		for i = 1, #path do
			if type(current) ~= "table" then
				return nil
			end
			current = current[path[i]]
			if current == nil then
				return nil
			end
		end

		return current
	end

	local function EnsureParent(unitName, path)
		local current = EnsureWorking(unitName)

		for i = 1, #path do
			local key = path[i]
			if type(current[key]) ~= "table" then
				current[key] = {}
			end
			current = current[key]
		end

		return current
	end

	local MakeProxy

	local function Materialize(value, seen)
		if type(value) ~= "table" then
			return value
		end

		local meta = getmetatable(value)
		if meta and meta.__teamTweakProxy then
			local unitName = meta.__unitName
			local path = meta.__path
			return DeepCopy(GetAtPath(unitName, path) or {})
		end

		return DeepCopy(value, seen)
	end

	local function ProxyPairs(proxy)
		local meta = getmetatable(proxy)
		local source = GetAtPath(meta.__unitName, meta.__path)
		if type(source) ~= "table" then
			return function() return nil end
		end

		local keys = SortedKeys(source)
		local i = 0

		return function()
			i = i + 1
			local key = keys[i]
			if key == nil then
				return nil
			end
			return key, proxy[key]
		end
	end

	local function ProxyIPairs(proxy)
		local i = 0
		return function()
			i = i + 1
			local value = proxy[i]
			if value == nil then
				return nil
			end
			return i, value
		end
	end

	MakeProxy = function(unitName, path)
		local cacheKey = unitName .. "|" .. PathKey(path)
		if tracker.proxyCache[cacheKey] then
			return tracker.proxyCache[cacheKey]
		end

		local proxy = {}
		local meta = {
			__teamTweakProxy = true,
			__unitName = unitName,
			__path = path,
		}

		meta.__index = function(_, key)
			local full = { "UnitDefs", unitName }
			for i = 1, #path do
				full[#full + 1] = path[i]
			end
			full[#full + 1] = key
			RecordRead(full)

			local value = GetAtPath(unitName, path)
			value = type(value) == "table" and value[key] or nil

			if type(value) == "table" then
				local childPath = {}
				for i = 1, #path do childPath[i] = path[i] end
				childPath[#childPath + 1] = key
				return MakeProxy(unitName, childPath)
			end

			return value
		end

		meta.__newindex = function(_, key, value)
			local parent = EnsureParent(unitName, path)
			parent[key] = Materialize(value)

			local full = { "UnitDefs", unitName }
			for i = 1, #path do
				full[#full + 1] = path[i]
			end
			full[#full + 1] = key
			RecordWrite(full, parent[key])
		end

		meta.__len = function()
			local value = GetAtPath(unitName, path)
			return type(value) == "table" and #value or 0
		end

		meta.__pairs = function()
			return ProxyPairs(proxy)
		end

		meta.__ipairs = function()
			return ProxyIPairs(proxy)
		end

		setmetatable(proxy, meta)
		tracker.proxyCache[cacheKey] = proxy
		return proxy
	end

	local rootProxy = {}
	setmetatable(rootProxy, {
		__index = function(_, unitName)
			RecordRead({ "UnitDefs", unitName })
			local value = GetRootValue(unitName)
			if type(value) == "table" then
				return MakeProxy(unitName, {})
			end
			return value
		end,

		__newindex = function(_, unitName, value)
			if value == nil then
				tracker.working[unitName] = nil
				tracker.deleted[unitName] = true
			else
				tracker.working[unitName] = Materialize(value)
				if UnitDefs[unitName] == nil then
					tracker.created[unitName] = true
				end
				tracker.deleted[unitName] = nil
			end
			RecordWrite({ "UnitDefs", unitName }, value)
		end,

		__pairs = function()
			local names = {}
			local seen = {}

			for name in pairs(UnitDefs) do
				if not tracker.deleted[name] then
					names[#names + 1] = name
					seen[name] = true
				end
			end
			for name in pairs(tracker.working) do
				if not seen[name] and not tracker.deleted[name] then
					names[#names + 1] = name
				end
			end

			table.sort(names)
			local i = 0
			return function()
				i = i + 1
				local name = names[i]
				if not name then
					return nil
				end
				return name, rootProxy[name]
			end
		end,
	})

	local function SafePairs(value)
		local meta = type(value) == "table" and getmetatable(value)
		if meta and meta.__pairs then
			return meta.__pairs(value)
		end
		return pairs(value)
	end

	local function SafeIPairs(value)
		local meta = type(value) == "table" and getmetatable(value)
		if meta and meta.__ipairs then
			return meta.__ipairs(value)
		end
		return ipairs(value)
	end

	local function SafeNext(value, key)
		local meta = type(value) == "table" and getmetatable(value)
		if meta and meta.__teamTweakProxy then
			local iterator = SafePairs(value)
			local found = key == nil
			while true do
				local k, v = iterator()
				if k == nil then
					return nil
				end
				if found then
					return k, v
				end
				if k == key then
					found = true
				end
			end
		end
		return next(value, key)
	end

	local safeTable = {}
	for k, v in pairs(table) do
		safeTable[k] = v
	end

	safeTable.copy = function(value)
		return Materialize(value)
	end
	safeTable.deepcopy = safeTable.copy

	safeTable.insert = function(t, pos, value)
		if value == nil then
			value = pos
			pos = #t + 1
		end
		for i = #t, pos, -1 do
			t[i + 1] = t[i]
		end
		t[pos] = value
	end

	safeTable.remove = function(t, pos)
		pos = pos or #t
		local old = t[pos]
		for i = pos, #t - 1 do
			t[i] = t[i + 1]
		end
		t[#t] = nil
		return old
	end

	safeTable.concat = function(t, sep, i, j)
		local materialized = Materialize(t)
		return table.concat(materialized, sep, i, j)
	end

	safeTable.sort = function(t, comp)
		local materialized = Materialize(t)
		table.sort(materialized, comp)
		for i = 1, #materialized do
			t[i] = materialized[i]
		end
		for i = #materialized + 1, #t do
			t[i] = nil
		end
	end

	safeTable.mergeInPlace = function(target, source, overwrite)
		for k, v in SafePairs(source) do
			if type(v) == "table" and type(target[k]) == "table" then
				safeTable.mergeInPlace(target[k], v, overwrite)
			elseif overwrite or target[k] == nil then
				target[k] = v
			end
		end
		return target
	end

	local env = {
		UnitDefs = rootProxy,
		pairs = SafePairs,
		ipairs = SafeIPairs,
		next = SafeNext,
		table = safeTable,
		_G = false,
	}

	env._G = env

	setmetatable(env, {
		__index = function(_, key)
			if key == "rawset"
				or key == "rawget"
				or key == "setmetatable"
				or key == "getmetatable"
				or key == "setfenv"
				or key == "getfenv"
				or key == "loadstring"
				or key == "load"
				or key == "dofile"
				or key == "require"
			then
				return nil
			end
			return _G[key]
		end,
	})

	tracker.UnitDefs = rootProxy
	tracker.env = env
	tracker.materialize = Materialize

	return tracker
end

local function MergeStructured(proxy, source)
	for key, value in pairs(source) do
		if type(value) == "table" then
			if type(proxy[key]) ~= "table" then
				proxy[key] = {}
			end
			MergeStructured(proxy[key], value)
		else
			if value == "nil" then
				proxy[key] = nil
			else
				proxy[key] = value
			end
		end
	end
end

local function ExecuteTweakUnits(tracker, tweak)
	local ok, parsed = pcall(BAR.Utilities.CustomKeyToUsefulTable, tweak.value)
	if not ok or type(parsed) ~= "table" then
		return false, parsed
	end

	for unitName, changes in pairs(parsed) do
		local lowerName = string.lower(unitName)
		local lowered = system.lowerkeys(DeepCopy(changes))
		local unitProxy = tracker.UnitDefs[lowerName]

		if not unitProxy then
			return false, "tweakunits references unknown unit " .. tostring(lowerName)
		end

		MergeStructured(unitProxy, lowered)
	end

	return true
end

local function ExecuteTweakDefs(tracker, tweak)
	local okDecode, source = pcall(string.base64Decode, tweak.value)
	if not okDecode then
		return false, source
	end

	local fn, err = loadstring(source)
	if not fn then
		return false, err
	end

	setfenv(fn, tracker.env)

	local ok, result = pcall(fn)
	if not ok then
		return false, result
	end

	return true
end

local RUNTIME_SAFE_FIELDS = {
	health = true,
	workertime = true,
	builddistance = true,
	speed = true,
	maxvelocity = true,
	turnrate = true,
	sightdistance = true,
	airsightdistance = true,
	radardistance = true,
	sonardistance = true,
	extractsmetal = true,
	energymake = true,
	metalmake = true,
	energystorage = true,
	metalstorage = true,
	energyupkeep = true,
}

local function SplitPath(path)
	local parts = {}
	for part in tostring(path):gmatch("[^.]+") do
		parts[#parts + 1] = part
	end
	return parts
end

local function GetNested(root, parts, first)
	local value = root
	for i = first or 1, #parts do
		if type(value) ~= "table" then
			return nil
		end
		value = value[parts[i]]
	end
	return value
end

local function IsBuildOptionsPath(parts)
	return parts[3] == "buildoptions" or parts[3] == "buildOptions"
end

local function IsRuntimeSafeWrite(path)
	local parts = SplitPath(path)
	if parts[1] ~= "UnitDefs" or not parts[2] then
		return false
	end
	if IsBuildOptionsPath(parts) then
		return true
	end
	return #parts == 3 and RUNTIME_SAFE_FIELDS[string.lower(parts[3])] == true
end

local function SetCustomParam(unitDef, key, value)
	unitDef.customparams = unitDef.customparams or {}
	unitDef.customparams[key] = value
end

local function EncodeRuntimePatch(entries)
	local rows = {}
	for i = 1, #entries do
		local entry = entries[i]
		rows[#rows + 1] =
			entry.field
			.. "\t" .. tostring(entry.old or "")
			.. "\t" .. tostring(entry.new or "")
	end
	return table.concat(rows, "\n")
end

local function ToNameSet(options)
	local set = {}
	if type(options) == "table" then
		for _, name in pairs(options) do
			if type(name) == "string" then
				set[string.lower(name)] = true
			end
		end
	end
	return set
end

local function BuildOptionDiff(base, changed)
	local oldSet = ToNameSet(base)
	local newSet = ToNameSet(changed)
	local added, removed = {}, {}

	for name in pairs(newSet) do
		if not oldSet[name] then
			added[#added + 1] = name
		end
	end
	for name in pairs(oldSet) do
		if not newSet[name] then
			removed[#removed + 1] = name
		end
	end

	table.sort(added)
	table.sort(removed)
	return added, removed
end

local function RewriteNameList(value, nameMap)
	if type(value) ~= "string" then
		return value
	end

	local out = {}
	for token in value:gmatch("%S+") do
		out[#out + 1] = nameMap[string.lower(token)] or token
	end
	return table.concat(out, " ")
end

local function RewriteKnownReferences(unitDef, nameMap, hiddenNames)
	local cp = unitDef.customparams or unitDef.customParams
	if cp and cp.evolution_target then
		local target = string.lower(cp.evolution_target)
		if hiddenNames[target] then
			cp.evolution_target = nil
		else
			cp.evolution_target = nameMap[target] or cp.evolution_target
		end
	end

	local buildoptions = unitDef.buildoptions or unitDef.buildOptions
	if type(buildoptions) == "table" then
		local out = {}
		for i = 1, #buildoptions do
			local value = buildoptions[i]
			if type(value) ~= "string" or not hiddenNames[string.lower(value)] then
				if type(value) == "string" then
					value = nameMap[string.lower(value)] or value
				end
				out[#out + 1] = value
			end
		end
		for k in pairs(buildoptions) do buildoptions[k] = nil end
		for i = 1, #out do buildoptions[i] = out[i] end
	end

	local weapondefs = unitDef.weapondefs or unitDef.weaponDefs
	if type(weapondefs) == "table" then
		for _, weaponDef in pairs(weapondefs) do
			local wcp = weaponDef.customparams or weaponDef.customParams
			if wcp then
				if wcp.spawns_name then
					wcp.spawns_name = RewriteNameList(wcp.spawns_name, nameMap)
				end
				if wcp.spawns_debris then
					wcp.spawns_debris =
						nameMap[string.lower(wcp.spawns_debris)] or wcp.spawns_debris
				end
			end
		end
	end
end

local function MaterializeSlot(slot, tracker)
	local hiddenNames = {}
	for name in pairs(tracker.deleted) do
		hiddenNames[string.lower(name)] = true
	end

	local writesByUnit = {}
	for path in pairs(tracker.writes) do
		local parts = SplitPath(path)
		if parts[1] == "UnitDefs" and parts[2] then
			writesByUnit[parts[2]] = writesByUnit[parts[2]] or {}
			writesByUnit[parts[2]][#writesByUnit[parts[2]] + 1] = path
		end
	end

	local cloneNames = {}
	local runtimeNames = {}

	for unitName, paths in pairs(writesByUnit) do
		if tracker.deleted[unitName] then
			-- Team deletion means the unit is hidden from that team's build menus.
		elseif tracker.created[unitName] then
			cloneNames[unitName] = true
		else
			local allRuntime = true
			for i = 1, #paths do
				if not IsRuntimeSafeWrite(paths[i]) then
					allRuntime = false
					break
				end
			end
			if allRuntime then
				runtimeNames[unitName] = true
			else
				cloneNames[unitName] = true
			end
		end
	end

	local nameMap = {}
	for name in pairs(cloneNames) do
		nameMap[string.lower(name)] = TeamName(slot, name)
	end

	-- Runtime-only patches are carried through harmless customparams on the
	-- original definition. They are interpreted only by game_team_tweak_runtime.
	for unitName in pairs(runtimeNames) do
		local base = UnitDefs[unitName]
		local changed = tracker.working[unitName]
		local entries = {}

		for _, path in ipairs(writesByUnit[unitName]) do
			local parts = SplitPath(path)
			if not IsBuildOptionsPath(parts) then
				local field = string.lower(parts[3])
				entries[#entries + 1] = {
					field = field,
					old = base and base[parts[3]],
					new = changed and changed[parts[3]],
				}
			end
		end

		if #entries > 0 then
			table.sort(entries, function(a, b) return a.field < b.field end)
			SetCustomParam(
				base,
				"rg_team_runtime_patch_" .. slot,
				EncodeRuntimePatch(entries)
			)
		end

		local added, removed = BuildOptionDiff(
			base and (base.buildoptions or base.buildOptions),
			changed and (changed.buildoptions or changed.buildOptions)
		)
		if #added > 0 then
			SetCustomParam(base, "rg_team_build_add_" .. slot, table.concat(added, " "))
		end
		if #removed > 0 then
			SetCustomParam(base, "rg_team_build_remove_" .. slot, table.concat(removed, " "))
		end
	end

	-- Team-scoped UnitDef deletion is build-menu hiding. Record removals on
	-- every unchanged/runtime builder that exposes the deleted unit.
	for deletedName in pairs(hiddenNames) do
		for builderName, builderDef in pairs(UnitDefs) do
			if not cloneNames[builderName] then
				local options = builderDef.buildoptions or builderDef.buildOptions
				local optionSet = ToNameSet(options)
				if optionSet[deletedName] then
					local key = "rg_team_build_remove_" .. slot
					local existing = builderDef.customparams and builderDef.customparams[key]
					local names = ToNameSet(existing and string.split(existing, " ") or {})
					names[deletedName] = true
					local list = SortedKeys(names)
					SetCustomParam(builderDef, key, table.concat(list, " "))
				end
			end
		end
	end

	local clonedCount = 0
	for sourceName in pairs(cloneNames) do
		local targetName = nameMap[string.lower(sourceName)]
		local unitDef = DeepCopy(tracker.working[sourceName])
		system.lowerkeys(unitDef)
		unitDef.customparams = unitDef.customparams or {}
		unitDef.customparams.rg_team_tweak_slot = slot
		unitDef.customparams.rg_team_tweak_source = sourceName
		unitDef.customparams.rg_team_tweak_created =
			tracker.created[sourceName] and 1 or 0
		RewriteKnownReferences(unitDef, nameMap, hiddenNames)
		UnitDefs[targetName] = unitDef
		clonedCount = clonedCount + 1
	end

	Echo(
		"Team", slot,
		"runtime=" .. tostring(#SortedKeys(runtimeNames)),
		"cloned=" .. tostring(clonedCount),
		"hidden=" .. tostring(#SortedKeys(hiddenNames))
	)

	return true, nameMap
end

function M.Process()
	local any = false

	for slot = 1, 8 do
		local tweaks = ParseTweaksForSlot(slot)
		if #tweaks > 0 then
			any = true
			local tracker = NewTracker(slot)
			local failed = false

			for i = 1, #tweaks do
				local tweak = tweaks[i]
				local ok, err

				if tweak.type == "units" then
					ok, err = ExecuteTweakUnits(tracker, tweak)
				else
					ok, err = ExecuteTweakDefs(tracker, tweak)
				end

				if not ok then
					Echo(
						"Team", slot,
						tweak.name,
						"failed:", tostring(err)
					)
					failed = true
					break
				end
			end

			if not failed then
				local materialized, materializeResult =
					MaterializeSlot(slot, tracker)

				if not materialized then
					Echo(
						"Team", slot,
						"materialization failed:",
						tostring(materializeResult)
					)
				else
					Echo(
						"Team", slot,
						"reads=" .. tostring(#SortedKeys(tracker.reads)),
						"writes=" .. tostring(#SortedKeys(tracker.writes))
					)
				end
			end
		end
	end

	return any
end

return M
