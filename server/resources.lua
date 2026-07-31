--- Resource start/stop/restart controls and fuzzy resource-name search.
---@class Agent
Agent = Agent or {}

---@type table<string, boolean>
local protectedFromStop = {
    [Agent.RESOURCE_NAME] = true,
}

---@param resourceName string
---@return resource|nil, string|nil error
local function resolveResource(resourceName)
    if type(resourceName) ~= "string" or resourceName == "" then
        return nil, "Resource name required"
    end

    local resourceElement = getResourceFromName(resourceName)
    if not resourceElement then
        return nil, "Resource not found: " .. resourceName
    end

    return resourceElement
end

---@param resourceElement resource
---@return AgentResourceSnapshot|table
local function resourceSnapshot(resourceElement)
    return {
        name = getResourceName(resourceElement),
        state = getResourceState(resourceElement),
    }
end

---@param resourceName string
---@return boolean ok
---@return AgentResourceSnapshot|table|string|nil result
function Agent.resourceStart(resourceName)
    local resourceElement, err = resolveResource(resourceName)
    if not resourceElement then
        return false, err or "Resource not found"
    end

    local state = getResourceState(resourceElement)
    if state == "running" then
        return true, resourceSnapshot(resourceElement)
    end

    if not startResource(resourceElement) then
        return false, "Failed to start resource: " .. resourceName
    end

    return true, resourceSnapshot(resourceElement)
end

---@param resourceName string
---@return boolean ok
---@return AgentResourceSnapshot|table|string|nil result
function Agent.resourceStop(resourceName)
    local resourceElement, err = resolveResource(resourceName)
    if not resourceElement then
        return false, err or "Resource not found"
    end

    if protectedFromStop[resourceName] then
        return false, "Cannot stop the agent resource"
    end

    -- MTA reports a not-running resource as "loaded" (or "failed to load"),
    -- never "stopped"; treat those as already-stopped and no-op.
    local state = getResourceState(resourceElement)
    if state == "loaded" or state == "failed to load" then
        return true, resourceSnapshot(resourceElement)
    end

    if not stopResource(resourceElement) then
        return false, "Failed to stop resource: " .. resourceName
    end

    return true, resourceSnapshot(resourceElement)
end

---@param resourceName string
---@return boolean ok
---@return AgentResourceSnapshot|table|string|nil result
function Agent.resourceRestart(resourceName)
    local resourceElement, err = resolveResource(resourceName)
    if not resourceElement then
        return false, err or "Resource not found"
    end

    if not restartResource(resourceElement) then
        return false, "Failed to restart resource: " .. resourceName
    end

    return true, resourceSnapshot(resourceElement)
end

---@param options AgentResourceSearchOptions|table|nil
---@return string
local function normalizeSearchQuery(options)
    options = type(options) == "table" and options or {}
    local query = options.query or options.q or options.name or ""
    return tostring(query):lower()
end

---@param nameLower string
---@param query string
---@param exact boolean
---@return integer|nil score
local function resourceMatchScore(nameLower, query, exact)
    if query == "" then
        return 0
    end
    if exact then
        return nameLower == query and 0 or nil
    end
    if nameLower == query then
        return 0
    end
    if nameLower:sub(1, #query) == query then
        return 1
    end
    local index = nameLower:find(query, 1, true)
    if index then
        return 10 + index
    end
    return nil
end

---@param options AgentResourceSearchOptions|table|nil
---@return AgentResourceSearchResult|table
function Agent.searchResources(options)
    options = type(options) == "table" and options or {}
    local query = normalizeSearchQuery(options)
    local stateFilter = options.state
    -- "stopped" is a common ask but MTA calls that state "loaded".
    if stateFilter == "stopped" then
        stateFilter = "loaded"
    end
    local limit = tonumber(options.limit) or 25
    local exact = options.exact == true

    if limit < 1 then
        limit = 25
    end

    local matches = {}
    local exactMatch = nil
    local total = 0
    local matchedTotal = 0

    for _, resourceElement in ipairs(getResources()) do
        total = total + 1
        local name = getResourceName(resourceElement)
        local state = getResourceState(resourceElement)
        local nameLower = string.lower(name)

        if stateFilter and state ~= stateFilter then
        else
            local score = resourceMatchScore(nameLower, query, exact)
            if score ~= nil then
                matchedTotal = matchedTotal + 1
                local entry = {
                    name = name,
                    state = state,
                    score = score,
                }
                matches[#matches + 1] = entry
                if nameLower == query then
                    exactMatch = { name = name, state = state }
                end
            end
        end
    end

    table.sort(matches, function(a, b)
        if a.score ~= b.score then
            return a.score < b.score
        end
        return a.name < b.name
    end)

    local trimmed = {}
    for i = 1, math.min(#matches, limit) do
        local entry = matches[i]
        trimmed[i] = {
            name = entry.name,
            state = entry.state,
        }
    end

    return {
        ok = true,
        query = options.query or options.q or options.name or "",
        state = stateFilter,
        count = #trimmed,
        matchedTotal = matchedTotal,
        total = total,
        limit = limit,
        resources = trimmed,
        exactMatch = exactMatch,
    }
end
