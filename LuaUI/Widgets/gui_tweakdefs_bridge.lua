function widget:GetInfo()
    return {
        name = "Tweakdefs Bridge",
        desc = "Renames tweakdefs unit names/descriptions from infolog, including RandomGuy team-specific UnitDef clones. Alt+M: Toggle custom names.",
        author = 'Ambo',
        date = '2026-05-17',
        license = 'GNU GPL, v3 or later',
        layer = -999998,
        version = 7,
        enabled = true,
    }
end

local infolog = "infolog.txt"
local renamesActive = true

local CACHE_BYTES = 1000000
local MAX_BLOCKS = 16
local GROUP_WINDOW_BYTES = 500000
local MAX_MARKER_LINE_LENGTH = 200

local START_MARKER = "tweakdefs_rename_get_ready"
local END_MARKER = "tweakdefs_rename_end"
local COUNT_PATTERN = "^tweakdefs_rename_block_count:(%d+)$"

local instructions = {}

local function echo(msg)
    Spring.Echo("[TDB] " .. msg)
end

local function getInfologPayload(line)
    local payload = line and string.match(line, "^%[t=[^%]]+%]%[f=[^%]]+%]%s*(.*)$")
    if payload then
        payload = string.gsub(payload, "\r$", "")
    end
    return payload
end

local function isMarkerLine(line, marker)
    return getInfologPayload(line) == marker
end

local function getCountValue(line)
    local payload = getInfologPayload(line)
    if not payload then
        return nil
    end
    return string.match(payload, COUNT_PATTERN)
end

local function clampCount(value)
    local count = tonumber(value) or 1
    if count < 1 then
        return 1
    end
    if count > MAX_BLOCKS then
        return MAX_BLOCKS
    end
    return count
end

local function readLogTail()
    local f, err = io.open(infolog, "rb")
    if not f then
        echo("Could not open " .. infolog .. ": " .. tostring(err))
        return {}
    end

    local size = f:seek("end")
    if size > CACHE_BYTES then
        f:seek("set", size - CACHE_BYTES)
        f:read("*l") -- discard a likely partial line at the cache boundary
    else
        f:seek("set", 0)
    end

    local lines = {}
    while true do
        local pos = f:seek("cur", 0)
        local line = f:read("*l")
        if not line then
            break
        end
        lines[#lines + 1] = {
            pos = pos,
            endPos = f:seek("cur", 0),
            text = line,
        }
    end

    f:close()
    return lines
end

local function collectBlocksAndCounts(lines)
    local blocks = {}
    local counts = {}
    local currentBlock = nil

    for _, entry in ipairs(lines) do
        local line = entry.text

        if isMarkerLine(line, START_MARKER) then
            currentBlock = {
                startPos = entry.pos,
                endPos = entry.endPos,
                complete = false,
                lines = {},
            }
        elseif currentBlock and isMarkerLine(line, END_MARKER) then
            currentBlock.endPos = entry.endPos
            currentBlock.complete = true
            blocks[#blocks + 1] = currentBlock
            currentBlock = nil
        elseif currentBlock then
            currentBlock.lines[#currentBlock.lines + 1] = line
            currentBlock.endPos = entry.endPos
        end

        if line and #line < MAX_MARKER_LINE_LENGTH then
            local count = getCountValue(line)
            if count then
                counts[#counts + 1] = {
                    pos = entry.pos,
                    endPos = entry.endPos,
                    count = clampCount(count),
                    inBlock = currentBlock ~= nil,
                }
            end
        end
    end

    return blocks, counts, currentBlock
end

local function latestLegacyBlock(blocks, openBlock)
    local latestComplete = blocks[#blocks]
    if openBlock and (not latestComplete or openBlock.startPos > latestComplete.startPos) then
        return openBlock
    end
    return latestComplete
end

local function selectLatestCompleteBlocks(blocks, wanted)
    local latestComplete = blocks[#blocks]
    local selected = {}

    if not latestComplete then
        return selected
    end

    for i = #blocks, 1, -1 do
        local block = blocks[i]
        if latestComplete.endPos - block.startPos > GROUP_WINDOW_BYTES then
            break
        end

        table.insert(selected, 1, block)
        if #selected == wanted then
            break
        end
    end

    return selected
end

local function anchorIsInSelectedScope(anchor, selected)
    if #selected == 0 then
        return false
    end

    local firstBlock = selected[1]
    local latestBlock = selected[#selected]

    if anchor.pos < firstBlock.startPos then
        return false
    end

    if anchor.pos > latestBlock.endPos and anchor.pos - latestBlock.endPos > GROUP_WINDOW_BYTES then
        return false
    end

    return true
end

local function selectBlocks(blocks, counts, openBlock)
    local latestBlock = latestLegacyBlock(blocks, openBlock)
    local anchor = counts[#counts]

    if anchor and anchor.inBlock then
        if latestBlock then
            return { latestBlock }, "legacy_count_inside_block", 1
        end
        return {}, "count_inside_block_no_blocks", 0
    end

    if anchor and openBlock and openBlock.endPos > anchor.endPos then
        return { latestBlock }, "legacy_open_block_after_count", 1
    end

    if anchor then
        local wanted = anchor.count
        local selected = selectLatestCompleteBlocks(blocks, wanted)

        if anchorIsInSelectedScope(anchor, selected) then
            return selected, "count_scope", wanted
        elseif latestBlock then
            return { latestBlock }, "legacy_count_out_of_scope", 1
        end
    end

    if latestBlock then
        if latestBlock.complete then
            return { latestBlock }, "legacy_latest_complete_block", 1
        end
        return { latestBlock }, "legacy_latest_open_block", 1
    end

    return {}, "no_blocks", 0
end

local function parseInstructionsFromBlocks(blocks)
    local pattern = "^/%(([^/]+)/%-([^/]+)/%-(.-)/%)$"
    local parsed = {}

    for _, block in ipairs(blocks) do
        for _, line in ipairs(block.lines) do
            local payload = getInfologPayload(line)
            local w1, w2, w3 = string.match(payload or "", pattern)
            if w2 == "rename" or w2 == "prefix" or w2 == "desc_prefix" or w2 == "desc_change" then
                parsed[#parsed + 1] = { w1, w2, w3 }
            end
        end
    end

    return parsed
end

local function extract_instructions()
    local lines = readLogTail()
    local blocks, counts, openBlock = collectBlocksAndCounts(lines)
    local selectedBlocks, mode, wanted = selectBlocks(blocks, counts, openBlock)

    instructions = parseInstructionsFromBlocks(selectedBlocks)

    echo("Selected " .. #selectedBlocks .. " block(s) via " .. mode .. " (wanted " .. wanted .. "); found " .. #instructions .. " instruction(s)")
end

local function buildUnitLookup()
    local vanillaByName = {}
    local clonesBySource = {}

    for _, ud in pairs(UnitDefs) do
        if ud.name then
            vanillaByName[ud.name] = ud
        end

        local cp = ud.customParams or {}
        local source = cp.rg_team_tweak_source
        if source then
            source = string.lower(source)
            clonesBySource[source] = clonesBySource[source] or {}
            clonesBySource[source][#clonesBySource[source] + 1] = ud
        end
    end

    return vanillaByName, clonesBySource
end

local function getTargetsForInstruction(unitName, vanillaByName, clonesBySource)
    local key = string.lower(unitName)
    local clones = clonesBySource[key]

    -- Team-scoped tweak copies receive the rename instead of the shared
    -- vanilla UnitDef. This prevents Team 1's randomized name/description
    -- from leaking onto teams that still use the original unit.
    if clones and #clones > 0 then
        return clones
    end

    local vanilla = vanillaByName[unitName] or vanillaByName[key]
    if vanilla then
        return { vanilla }
    end

    return {}
end

local function addToGroup(groups, unitName)
    local group = groups[unitName]
    if not group then
        group = {
            namePrefixes = {},
            descPrefixes = {},
            renameCount = 0,
            descChangeCount = 0,
        }
        groups[unitName] = group
    end
    return group
end

local function buildInstructionGroups()
    local groups = {}

    for _, entry in ipairs(instructions) do
        local unitName = entry[1]
        local action = entry[2]
        local value = entry[3]
        local group = addToGroup(groups, unitName)

        if action == "rename" then
            group.rename = value
            group.renameCount = group.renameCount + 1
        elseif action == "prefix" then
            group.namePrefixes[#group.namePrefixes + 1] = value
        elseif action == "desc_change" then
            group.descChange = value
            group.descChangeCount = group.descChangeCount + 1
        elseif action == "desc_prefix" then
            group.descPrefixes[#group.descPrefixes + 1] = value
        end
    end

    return groups
end

local function prefixedValue(prefixes, baseValue)
    baseValue = baseValue or ""
    if #prefixes == 0 then
        return baseValue
    end
    return table.concat(prefixes, " ") .. " " .. baseValue
end

local function restoreOriginals(ud)
    if ud._originalHumanName then
        ud.translatedHumanName = ud._originalHumanName
    end
    if ud._originalTranslatedTooltip then
        ud.translatedTooltip = ud._originalTranslatedTooltip
    end
end

local function patchNames()
    if not instructions or #instructions == 0 then
        echo("No rename instructions found")
        return
    end

    local vanillaByName, clonesBySource = buildUnitLookup()
    local groups = buildInstructionGroups()

    for unitName, group in pairs(groups) do
        local targets = getTargetsForInstruction(unitName, vanillaByName, clonesBySource)

        if #targets > 0 then
            if group.renameCount > 1 then
                echo("Multiple rename instructions for " .. unitName .. "; latest selected rename wins")
            end
            if group.descChangeCount > 1 then
                echo("Multiple desc_change instructions for " .. unitName .. "; latest selected description wins")
            end

            for _, ud in ipairs(targets) do
                if renamesActive then
                    if group.rename or #group.namePrefixes > 0 then
                        if not ud._originalHumanName then
                            ud._originalHumanName = ud.translatedHumanName
                        end
                        local baseName = group.rename or ud._originalHumanName
                        ud.translatedHumanName = prefixedValue(group.namePrefixes, baseName)
                    end

                    if group.descChange or #group.descPrefixes > 0 then
                        if not ud._originalTranslatedTooltip then
                            ud._originalTranslatedTooltip = ud.translatedTooltip
                        end
                        local baseDesc = group.descChange or ud._originalTranslatedTooltip
                        ud.translatedTooltip = prefixedValue(group.descPrefixes, baseDesc)
                    end
                else
                    restoreOriginals(ud)
                end
            end
        end
    end
end

local function clearOriginalCaches()
    for _, ud in pairs(UnitDefs) do
        ud._originalHumanName = nil
        ud._originalTranslatedTooltip = nil
    end
end

local function toggle()
    renamesActive = not renamesActive
    -- The reload forces every widget to re-initialize and see the new names.
    Spring.SendCommands("luaui reload")
end

function widget:Initialize()
    extract_instructions()
    patchNames()
end

function widget:LanguageChanged()
    clearOriginalCaches()
    patchNames()
end

function widget:KeyPress(key, mods, isRepeat)
    if not isRepeat and key == 109 and mods.alt then
        toggle()
        return true
    end
    return false
end

function widget:GetConfigData()
    return { renamesActive = renamesActive }
end

function widget:SetConfigData(data)
    if data and data.renamesActive ~= nil then
        renamesActive = data.renamesActive
    end
end
