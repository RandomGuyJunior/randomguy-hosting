local M = {}

local modOptions = Spring.GetModOptions()
local teamOptions = {}

local function ParseValue(value)
	if value == "true" then
		return true
	elseif value == "false" then
		return false
	end

	local numberValue = tonumber(value)

	if numberValue ~= nil then
		return numberValue
	end

	return value
end

local function IsEnabled(value)
	return value == true
		or value == 1
		or value == "1"
		or value == "true"
		or value == "enabled"
end

local function ParseOptionString(input)
	local result = {}

	if not input or input == "" then
		return result
	end

	for line in string.gmatch(input, "[^\r\n]+") do
		local key, value = string.match(
			line,
			"^%s*([^=]+)%s*=%s*(.-)%s*$"
		)

		if key and value and key ~= "" then
			result[string.lower(key)] = ParseValue(value)
		end
	end

	return result
end

for slot = 1, 8 do
	teamOptions[slot] = ParseOptionString(
		modOptions["team" .. slot .. "_options"]
	)
end

function M.GetOptions(slot)
	return teamOptions[slot]
end

function M.GetOption(slot, key, fallback)
	local options = teamOptions[slot]

	if options then
		local value = options[string.lower(key)]

		if value ~= nil then
			return value
		end
	end

	return fallback
end

function M.AnyTeamEnabled(key)
	key = string.lower(key)

	for slot = 1, 8 do
		if IsEnabled(teamOptions[slot][key]) then
			return true
		end
	end

	return false
end

function M.GlobalEnabled(key)
	return IsEnabled(modOptions[string.lower(key)])
end

-- Should our custom team implementation handle this feature at all?
--
-- Global ON:
-- BAR already handles everybody, so return false.
--
-- Global OFF + at least one team ON:
-- our team-specific implementation is required.
function M.TeamFeatureActive(key)
	key = string.lower(key)

	return not M.GlobalEnabled(key)
		and M.AnyTeamEnabled(key)
end

-- Is this feature active specifically for this Team slot?
-- This also respects the global override rule above.
function M.TeamHasFeature(slot, key)
	key = string.lower(key)

	if not M.TeamFeatureActive(key) then
		return false
	end

	return IsEnabled(M.GetOption(slot, key))
end

M.Options = teamOptions
M.IsEnabled = IsEnabled

return M
