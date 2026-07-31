--- Async client queries for on-screen visible elements and camera look target.
---@class Agent
Agent = Agent or {}

Agent.VISIBLE_QUERY_TIMEOUT_MS = 5000
Agent.visibleRequests = Agent.visibleRequests or {}
Agent.lookTargetRequests = Agent.lookTargetRequests or {}
Agent.visibleNextId = Agent.visibleNextId or 0
Agent.lookTargetNextId = Agent.lookTargetNextId or 0

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return player|nil, string|nil error
local function resolvePlayer(playerName, options)
    return Agent.resolvePlayerElement(playerName, options)
end

---@param options AgentVisibleOptions|table|nil
---@return AgentVisibleOptions|table
local function sanitizeVisibleOptions(options)
    options = type(options) == "table" and options or {}

    return {
        type = options.type,
        types = options.types,
        limit = options.limit,
        maxDistance = options.maxDistance,
        lineOfSight = options.lineOfSight,
        includeOffScreen = options.includeOffScreen,
        onlyVisible = options.onlyVisible,
        debugLog = options.debugLog,
        autoTrack = options.autoTrack,
        trackSource = options.trackSource,
        serial = options.serial,
    }
end

---@param options AgentLookOptions|table|nil
---@return AgentLookOptions|table
local function sanitizeLookTargetOptions(options)
    options = type(options) == "table" and options or {}

    return {
        type = options.type,
        types = options.types,
        maxDistance = options.maxDistance,
        lineOfSight = options.lineOfSight,
        debugLog = options.debugLog,
        screenCenterMax = options.screenCenterMax,
        maxCameraAngle = options.maxCameraAngle,
        autoTrack = options.autoTrack,
        trackSource = options.trackSource,
        serial = options.serial,
    }
end

---@param store table<string, AgentAsyncRequest|table>
---@param idPrefix string
---@param nextIdField string
---@param playerName string|nil
---@param clientFunction string
---@param clientOptions table
---@return string|nil id, string|nil error
local function startClientCallbackQuery(store, idPrefix, nextIdField, playerName, clientFunction, clientOptions)
    local player, err = resolvePlayer(playerName, clientOptions)
    if not player then
        return nil, err
    end

    clientOptions = type(clientOptions) == "table" and clientOptions or {}
    local queryOptions = clientOptions

    Agent[nextIdField] = Agent[nextIdField] + 1
    local id = idPrefix .. getTickCount() .. "-" .. Agent[nextIdField]
    local request = {
        id = id,
        status = "pending",
        player = getPlayerName(player),
        createdAt = getTickCount(),
        result = nil,
        error = nil,
    }
    store[id] = request

    local timeoutTimer
    timeoutTimer = setTimer(function()
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        if request.status == "pending" then
            request.status = "complete"
            request.error = "Client query timeout"
        end
    end, Agent.VISIBLE_QUERY_TIMEOUT_MS, 1)

    local sent = Agent.callClient(player, clientFunction, clientOptions, function(clientReturn)
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        if request.status ~= "pending" then
            return
        end

        if type(clientReturn) ~= "table" then
            request.status = "complete"
            request.error = "No client response"
            return
        end

        if clientReturn.ok then
            request.status = "complete"
            request.result = clientReturn.result
            if type(Agent.processClientDiscoveryResult) == "function" then
                Agent.processClientDiscoveryResult(request.result, queryOptions)
            end
        else
            request.status = "complete"
            request.error = clientReturn.error or "Client query failed"
        end
    end)

    if not sent then
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        store[id] = nil
        return nil, "Client not loaded (player may not have agent on client)"
    end

    return id
end

---@param store table<string, AgentAsyncRequest|table>
---@param id string
---@return AgentHttpPayload|table
local function getClientQueryResult(store, id)
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end

    local request = store[id]
    if not request then
        return { ok = false, error = "Request not found" }
    end

    if request.status == "pending" then
        return {
            ok = true,
            id = id,
            status = "pending",
            player = request.player,
        }
    end

    if request.error then
        return {
            ok = false,
            id = id,
            status = "complete",
            error = request.error,
            player = request.player,
        }
    end

    return {
        ok = true,
        id = id,
        status = "complete",
        player = request.player,
        result = request.result,
    }
end

---@param playerName string|nil
---@param options AgentVisibleOptions|table|nil
---@return string|nil id, string|nil error
function Agent.startVisibleQuery(playerName, options)
    return startClientCallbackQuery(
        Agent.visibleRequests,
        "fv-",
        "visibleNextId",
        playerName,
        "getVisibleElements",
        sanitizeVisibleOptions(options)
    )
end

---@param id string
---@return AgentHttpPayload|table
function Agent.getVisibleQueryResult(id)
    return getClientQueryResult(Agent.visibleRequests, id)
end

---@param playerName string|nil
---@param options AgentLookOptions|table|nil
---@return string|nil id, string|nil error
function Agent.startLookTargetQuery(playerName, options)
    return startClientCallbackQuery(
        Agent.lookTargetRequests,
        "lk-",
        "lookTargetNextId",
        playerName,
        "getLookTarget",
        sanitizeLookTargetOptions(options)
    )
end

---@param id string
---@return AgentHttpPayload|table
function Agent.getLookTargetQueryResult(id)
    return getClientQueryResult(Agent.lookTargetRequests, id)
end

setTimer(function()
    local now = getTickCount()
    local ttl = 10 * 60 * 1000
    for requestId, request in pairs(Agent.visibleRequests) do
        if now - request.createdAt > ttl then
            Agent.visibleRequests[requestId] = nil
        end
    end
    for requestId, request in pairs(Agent.lookTargetRequests) do
        if now - request.createdAt > ttl then
            Agent.lookTargetRequests[requestId] = nil
        end
    end
end, 60000, 0)
