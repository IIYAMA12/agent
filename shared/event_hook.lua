--- Shared event hook tracer: wraps addDebugHook/removeDebugHook ("preEvent") to record recent event dispatches into a filterable ring buffer.

---@class Agent
Agent = Agent or {}
---@class AgentEventHookNS
Agent.EventHook = Agent.EventHook or {}

Agent.EventHook.MAX_SIZE = 500
Agent.EventHook.VALID_HOOK_TYPES = {
    preEvent = true,
}
Agent.EventHook.DEFAULT_HOOK_TYPES = { "preEvent" }

local EventHook = Agent.EventHook

--- Truncates a value's string representation to at most `maxLen` characters, appending "..." if trimmed.
---@param value any
---@param maxLen integer|nil Defaults to 120.
---@return string
local function trimText(value, maxLen)
    value = type(value) == "string" and value or tostring(value or "")
    maxLen = tonumber(maxLen) or 120
    if #value > maxLen then
        return value:sub(1, maxLen - 3) .. "..."
    end
    return value
end

--- Safely resolves a resource element's name.
---@param sourceResource resource|nil
---@return string|nil
local function resourceNameFrom(sourceResource)
    if sourceResource and getResourceName then
        local ok, name = pcall(getResourceName, sourceResource)
        if ok and type(name) == "string" then
            return name
        end
    end
    return nil
end

--- Builds a short summary (type, and name for players) of an element for logging.
---@param element element|nil
---@return AgentEventElementSummary|nil
local function elementSummary(element)
    if not element or not isElement(element) then
        return nil
    end

    local elementType = getElementType(element)
    local summary = { type = elementType }

    if elementType == "player" then
        summary.name = getPlayerName(element)
    end

    return summary
end

--- Builds a truncated, comma-joined preview string of up to `maxArgs` event arguments.
---@param args any[]|nil
---@param maxArgs integer|nil Defaults to 3.
---@return string
function EventHook.argPreview(args, maxArgs)
    args = type(args) == "table" and args or {}
    maxArgs = tonumber(maxArgs) or 3
    local parts = {}

    for i = 1, math.min(#args, maxArgs) do
        parts[#parts + 1] = trimText(args[i], 80)
    end

    if #args > maxArgs then
        parts[#parts + 1] = "..."
    end

    return table.concat(parts, ", ")
end

--- Normalizes a requested hook type list, filtering to known valid types and falling back to the defaults.
---@param hookTypes string[]|nil
---@return string[]
function EventHook.normalizeHookTypes(hookTypes)
    if type(hookTypes) ~= "table" or #hookTypes == 0 then
        local copy = {}
        for i = 1, #EventHook.DEFAULT_HOOK_TYPES do
            copy[i] = EventHook.DEFAULT_HOOK_TYPES[i]
        end
        return copy
    end

    local normalized = {}
    for i = 1, #hookTypes do
        local hookType = hookTypes[i]
        if type(hookType) == "string" and EventHook.VALID_HOOK_TYPES[hookType] then
            normalized[#normalized + 1] = hookType
        end
    end

    if #normalized == 0 then
        for i = 1, #EventHook.DEFAULT_HOOK_TYPES do
            normalized[i] = EventHook.DEFAULT_HOOK_TYPES[i]
        end
    end

    return normalized
end

--- Extracts an event name filter list (`nameList`, `events`, or single `event`) from control/list options.
---@param options AgentEventHookControlOptions|AgentEventHookListOptions|table
---@return string[]|nil
function EventHook.normalizeNameList(options)
    if type(options.nameList) == "table" and #options.nameList > 0 then
        return options.nameList
    end
    if type(options.events) == "table" and #options.events > 0 then
        return options.events
    end
    if type(options.event) == "string" and options.event ~= "" then
        return { options.event }
    end
    return nil
end

--- Builds a normalized AgentEventHookEntry from captured hook fields.
---@param hookType string
---@param side string
---@param player string|nil
---@param fields table|nil Fields: eventName, resource, source, client, file, line, argCount, argPreview.
---@return AgentEventHookEntry
function EventHook.buildEntry(hookType, side, player, fields)
    fields = type(fields) == "table" and fields or {}
    local now = getTickCount()

    return {
        at = now,
        lastAt = now,
        repeatCount = 1,
        side = side,
        player = player,
        hookType = hookType,
        eventName = fields.eventName,
        resource = fields.resource,
        source = fields.source,
        client = fields.client,
        file = fields.file,
        line = fields.line,
        argCount = fields.argCount or 0,
        argPreview = fields.argPreview,
    }
end

--- Builds a fingerprint string used to detect consecutive duplicate entries.
---@param entry AgentEventHookEntry|table
---@return string
function EventHook.entryFingerprint(entry)
    if type(entry) ~= "table" then
        return ""
    end

    return table.concat({
        tostring(entry.side or ""),
        tostring(entry.player or ""),
        tostring(entry.hookType or ""),
        tostring(entry.eventName or ""),
        tostring(entry.resource or ""),
        tostring(entry.source and entry.source.type or ""),
        tostring(entry.source and entry.source.name or ""),
        tostring(entry.file or ""),
        tostring(entry.line or ""),
        tostring(entry.argPreview or ""),
    }, "\31")
end

--- Filters entries by eventName/hookType/resource/sinceSeq/sinceTick, optionally dedupes adjacent repeats, and applies a limit.
---@param entries AgentEventHookEntry[]
---@param options AgentEventHookListOptions|table|nil
---@return AgentEventHookEntry[]
function EventHook.filterEntries(entries, options)
    options = type(options) == "table" and options or {}
    entries = type(entries) == "table" and entries or {}

    local filtered = {}
    local eventName = options.eventName or options.event
    local hookType = options.hookType
    local resource = options.resource
    local sinceSeq = tonumber(options.sinceSeq)
    local sinceTick = tonumber(options.sinceTick)

    for i = 1, #entries do
        local entry = entries[i]
        if eventName and entry.eventName ~= eventName then
        elseif hookType and entry.hookType ~= hookType then
        elseif resource and entry.resource ~= resource then
        elseif sinceSeq and (entry.seq or 0) <= sinceSeq then
        elseif sinceTick and (entry.at or 0) <= sinceTick then
        else
            filtered[#filtered + 1] = entry
        end
    end

    if options.dedupe ~= false then
        local merged = {}
        for i = 1, #filtered do
            local entry = filtered[i]
            local tail = merged[#merged]
            if tail and EventHook.entryFingerprint(tail) == EventHook.entryFingerprint(entry) then
                tail.repeatCount = (tail.repeatCount or 1) + (entry.repeatCount or 1)
                tail.lastAt = entry.lastAt or entry.at or tail.lastAt
            else
                merged[#merged + 1] = entry
            end
        end
        filtered = merged
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

--- Merges two entry lists in chronological (at, then seq) order, then filters the result.
---@param listA AgentEventHookEntry[]
---@param listB AgentEventHookEntry[]
---@param options AgentEventHookListOptions|table|nil
---@return AgentEventHookEntry[]
function EventHook.mergeEntries(listA, listB, options)
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

    return EventHook.filterEntries(merged, options)
end

--- Creates a preEvent hook tracker for the given side, backed by a debug-log-style ring buffer.
---@param side string
---@param playerGetter fun(): string|nil|nil Optional callback returning the current player name for captured entries.
---@return table tracker
function EventHook.createTracker(side, playerGetter)
    local tracker = {
        side = side,
        buffer = Agent.DebugLog.createBuffer(EventHook.MAX_SIZE),
        active = false,
        callbacks = {},
        hookTypes = {},
        nameList = nil,
        startedAt = nil,
        playerGetter = playerGetter,
    }

    --- Appends a built entry for `hookType` to the tracker's buffer.
    ---@param hookType string
    ---@param fields table|nil
    local function appendEntry(hookType, fields)
        local player = type(playerGetter) == "function" and playerGetter() or nil
        tracker.buffer:append(EventHook.buildEntry(hookType, side, player, fields))
    end

    --- Builds an addDebugHook-compatible callback for `hookType` that records dispatch info to the buffer.
    ---@param hookType string
    ---@return fun(sourceResource: resource, eventName: string, eventSource: element, eventClient: element, luaFilename: string, luaLineNumber: integer, ...: any) callback
    function tracker:makeCallback(hookType)
        return function(sourceResource, eventName, eventSource, eventClient, luaFilename, luaLineNumber, ...)
            local args = { ... }
            appendEntry(hookType, {
                eventName = eventName,
                resource = resourceNameFrom(sourceResource),
                source = elementSummary(eventSource),
                client = elementSummary(eventClient),
                file = luaFilename,
                line = luaLineNumber,
                argCount = #args,
                argPreview = EventHook.argPreview(args),
            })
        end
    end

    --- Starts tracing: stops any existing hooks, then registers debug hooks for the requested hook types/name list.
    ---@param options AgentEventHookControlOptions|table|nil
    ---@return AgentEventHookStatus status
    function tracker:start(options)
        options = type(options) == "table" and options or {}
        self:stop()

        local hookTypes = EventHook.normalizeHookTypes(options.hookTypes)
        local nameList = EventHook.normalizeNameList(options)

        for i = 1, #hookTypes do
            local hookType = hookTypes[i]
            local callback = self:makeCallback(hookType)
            if addDebugHook(hookType, callback, nameList) then
                self.callbacks[hookType] = callback
            end
        end

        self.active = next(self.callbacks) ~= nil
        self.hookTypes = hookTypes
        self.nameList = nameList
        self.startedAt = self.active and getTickCount() or nil

        return self:status()
    end

    --- Stops tracing: removes all registered debug hooks.
    ---@return AgentEventHookStatus status
    function tracker:stop()
        for hookType, callback in pairs(self.callbacks) do
            removeDebugHook(hookType, callback)
        end

        self.callbacks = {}
        self.active = false
        self.startedAt = nil
        return self:status()
    end

    --- Clears all buffered entries.
    ---@return AgentEventHookStatus status
    function tracker:clear()
        self.buffer:clear()
        return self:status()
    end

    --- Returns the tracker's current status.
    ---@return AgentEventHookStatus
    function tracker:status()
        return {
            active = self.active,
            side = self.side,
            hookTypes = self.hookTypes,
            nameList = self.nameList,
            startedAt = self.startedAt,
            count = self.buffer:count(),
        }
    end

    --- Returns a filtered snapshot of buffered entries plus the tracker's status.
    ---@param options AgentEventHookListOptions|table|nil
    ---@return AgentEventHookSnapshot
    function tracker:snapshot(options)
        options = type(options) == "table" and options or {}
        local entries = EventHook.filterEntries(self.buffer:all(), options)
        return {
            entries = entries,
            -- Reflect the returned (filtered) set; bufferCount keeps the raw total.
            count = #entries,
            bufferCount = self.buffer:count(),
            side = self.side,
            status = self:status(),
        }
    end

    return tracker
end
