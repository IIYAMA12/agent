--- Shared debug log ring buffer: normalizes onDebugMessage/onClientDebugMessage entries, dedupes adjacent repeats, and filters/merges snapshots.

---@class Agent
Agent = Agent or {}
---@class AgentDebugLogNS
Agent.DebugLog = Agent.DebugLog or {}

Agent.DebugLog.MAX_SIZE = 500
Agent.DebugLog.LEVEL_NAMES = {
    [0] = "custom",
    [1] = "error",
    [2] = "warning",
    [3] = "info",
}

local DebugLog = Agent.DebugLog

--- Builds a normalized AgentDebugLogEntry from raw onDebugMessage/onClientDebugMessage fields.
---@param message string|any
---@param level integer|nil
---@param file string|nil
---@param line integer|nil
---@param r integer|nil
---@param g integer|nil
---@param b integer|nil
---@param side string|nil
---@param player string|nil
---@return AgentDebugLogEntry
function DebugLog.normalizeEntry(message, level, file, line, r, g, b, side, player)
    level = tonumber(level) or 0
    local now = getTickCount()

    return {
        at = now,
        lastAt = now,
        repeatCount = 1,
        side = side,
        player = player,
        message = type(message) == "string" and message or tostring(message),
        level = level,
        levelName = DebugLog.LEVEL_NAMES[level] or "custom",
        file = type(file) == "string" and file or nil,
        line = tonumber(line),
        color = {
            r = tonumber(r) or 255,
            g = tonumber(g) or 255,
            b = tonumber(b) or 255,
        },
    }
end

--- Builds a fingerprint string used to detect consecutive duplicate entries.
---@param entry AgentDebugLogEntry|table
---@return string
function DebugLog.entryFingerprint(entry)
    if type(entry) ~= "table" then
        return ""
    end

    return table.concat({
        tostring(entry.side or ""),
        tostring(entry.player or ""),
        tostring(entry.level or ""),
        tostring(entry.message or ""),
        tostring(entry.file or ""),
        tostring(entry.line or ""),
    }, "\31")
end

--- Collapses consecutive fingerprint-identical entries into single entries with an incremented repeatCount.
---@param entries AgentDebugLogEntry[]
---@return AgentDebugLogEntry[]
local function collapseAdjacent(entries)
    if type(entries) ~= "table" or #entries == 0 then
        return {}
    end

    local merged = {}
    for i = 1, #entries do
        local entry = entries[i]
        local tail = merged[#merged]
        if tail and DebugLog.entryFingerprint(tail) == DebugLog.entryFingerprint(entry) then
            tail.repeatCount = (tail.repeatCount or 1) + (entry.repeatCount or 1)
            tail.lastAt = entry.lastAt or entry.at or tail.lastAt
        else
            merged[#merged + 1] = entry
        end
    end

    return merged
end

--- Filters entries by minLevel/sinceSeq/sinceTick, optionally dedupes adjacent repeats, and applies a limit.
---@param entries AgentDebugLogEntry[]
---@param options AgentDebugLogOptions|table|nil
---@return AgentDebugLogEntry[]
function DebugLog.filterEntries(entries, options)
    options = type(options) == "table" and options or {}
    entries = type(entries) == "table" and entries or {}

    local minLevel = options.minLevel
    if minLevel ~= nil then
        minLevel = tonumber(minLevel) or 0
    end

    local sinceSeq = tonumber(options.sinceSeq)
    local sinceTick = tonumber(options.sinceTick)
    local filtered = {}

    for i = 1, #entries do
        local entry = entries[i]
        if minLevel ~= nil and (entry.level or 0) < minLevel then
        elseif sinceSeq and (entry.seq or 0) <= sinceSeq then
        elseif sinceTick and (entry.at or 0) <= sinceTick then
        else
            filtered[#filtered + 1] = entry
        end
    end

    if options.dedupe ~= false then
        filtered = collapseAdjacent(filtered)
    end

    local limit = tonumber(options.limit)
    if limit and limit > 0 and #filtered > limit then
        local startIndex = #filtered - limit + 1
        local trimmed = {}
        for i = startIndex, #filtered do
            trimmed[#trimmed + 1] = filtered[i]
        end
        filtered = trimmed
    end

    return filtered
end

--- Merges two entry lists in chronological (at, then seq) order, then dedupes/filters the result.
---@param listA AgentDebugLogEntry[]
---@param listB AgentDebugLogEntry[]
---@param options AgentDebugLogOptions|table|nil
---@return AgentDebugLogEntry[]
function DebugLog.mergeEntries(listA, listB, options)
    options = type(options) == "table" and options or {}
    listA = type(listA) == "table" and listA or {}
    listB = type(listB) == "table" and listB or {}

    local merged = {}
    for i = 1, #listA do
        merged[#merged + 1] = listA[i]
    end
    for i = 1, #listB do
        merged[#merged + 1] = listB[i]
    end

    table.sort(merged, function(a, b)
        local atA = a.at or 0
        local atB = b.at or 0
        if atA ~= atB then
            return atA < atB
        end
        return (a.seq or 0) < (b.seq or 0)
    end)

    if options.dedupe ~= false then
        merged = collapseAdjacent(merged)
    end

    return DebugLog.filterEntries(merged, options)
end

--- Creates a fixed-size ring buffer with append/all/count/clear methods and anti-dupe collapsing on append.
---@param maxSize integer|nil Defaults to DebugLog.MAX_SIZE.
---@return table buffer
function DebugLog.createBuffer(maxSize)
    maxSize = tonumber(maxSize) or DebugLog.MAX_SIZE
    if maxSize < 1 then
        maxSize = DebugLog.MAX_SIZE
    end

    local buffer = {
        maxSize = maxSize,
        seq = 0,
        items = {},
    }

    --- Appends an entry to the buffer, collapsing into the previous entry if it is a fingerprint-identical repeat.
    ---@param entry AgentDebugLogEntry|table
    ---@return boolean ok
    function buffer:append(entry)
        if type(entry) ~= "table" then
            return false
        end

        local now = getTickCount()
        entry.at = entry.at or now
        entry.lastAt = entry.lastAt or now
        entry.repeatCount = entry.repeatCount or 1

        local tail = self.items[#self.items]
        if tail and DebugLog.entryFingerprint(tail) == DebugLog.entryFingerprint(entry) then
            tail.repeatCount = (tail.repeatCount or 1) + 1
            tail.lastAt = now
            return true
        end

        self.seq = self.seq + 1
        entry.seq = self.seq

        table.insert(self.items, entry)
        if #self.items > self.maxSize then
            table.remove(self.items, 1)
        end

        return true
    end

    --- Returns all entries currently in the buffer.
    ---@return AgentDebugLogEntry[]
    function buffer:all()
        return self.items
    end

    --- Returns the current number of entries in the buffer.
    ---@return integer
    function buffer:count()
        return #self.items
    end

    --- Clears all entries and resets the sequence counter.
    ---@return nil
    function buffer:clear()
        self.items = {}
        self.seq = 0
    end

    return buffer
end

--- Builds an onDebugMessage/onClientDebugMessage-compatible handler that normalizes and appends entries to `buffer`.
---@param buffer table Buffer created by DebugLog.createBuffer.
---@param side string|nil
---@param enrichFn fun(entry: AgentDebugLogEntry)|nil Optional callback to mutate the entry before appending.
---@return fun(message: string, level: integer|nil, file: string|nil, line: integer|nil, r: integer|nil, g: integer|nil, b: integer|nil) handler
function DebugLog.makeCaptureHandler(buffer, side, enrichFn)
    return function(message, level, file, line, r, g, b)
        local entry = DebugLog.normalizeEntry(message, level, file, line, r, g, b, side, nil)
        if type(enrichFn) == "function" then
            enrichFn(entry)
        end
        buffer:append(entry)
    end
end
