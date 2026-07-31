--- Server-side debug log buffer + sync/async fetch of server, client, or merged debug logs.
---@class Agent
Agent = Agent or {}

Agent.DEBUG_LOG_FETCH_TIMEOUT_MS = 15000
Agent.debugLogRequests = Agent.debugLogRequests or {}
Agent.debugLogNextId = Agent.debugLogNextId or 0
Agent.serverDebugBuffer = Agent.serverDebugBuffer or Agent.DebugLog.createBuffer(Agent.DebugLog.MAX_SIZE)

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return player|nil, string|nil error
local function resolvePlayer(playerName, options)
    return Agent.resolvePlayerElement(playerName, options)
end

---@param options AgentDebugLogOptions|table|nil
---@return AgentDebugLogOptions|table
local function sanitizeDebugLogOptions(options)
    options = type(options) == "table" and options or {}

    local side = options.side or "server"
    if side ~= "server" and side ~= "client" and side ~= "all" then
        side = "server"
    end

    return {
        side = side,
        minLevel = options.minLevel,
        limit = options.limit,
        sinceSeq = options.sinceSeq,
        sinceTick = options.sinceTick,
        dedupe = options.dedupe,
        serial = options.serial,
    }
end

---@param options AgentDebugLogOptions|table
---@return AgentDebugLogSnapshot|table
local function buildServerSnapshot(options)
    local entries = Agent.DebugLog.filterEntries(Agent.serverDebugBuffer:all(), options)
    return {
        entries = entries,
        count = #entries,
        bufferCount = Agent.serverDebugBuffer:count(),
        side = "server",
    }
end

---@param options AgentDebugLogOptions|table|nil
---@return AgentDebugLogSnapshot|table
function Agent.listServerDebugLogs(options)
    return buildServerSnapshot(sanitizeDebugLogOptions(options))
end

---@param playerName string|nil
---@param options AgentDebugLogOptions|table|nil
---@return string|nil id, string|nil error
function Agent.startDebugLogFetch(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return nil, err
    end

    options = sanitizeDebugLogOptions(options)
    local side = options.side

    if side == "server" then
        return nil, "Use sync fetch for server-side debug logs"
    end

    Agent.debugLogNextId = Agent.debugLogNextId + 1
    local id = "dl-" .. getTickCount() .. "-" .. Agent.debugLogNextId
    local request = {
        id = id,
        status = "pending",
        player = getPlayerName(player),
        side = side,
        options = options,
        createdAt = getTickCount(),
        result = nil,
        error = nil,
    }
    Agent.debugLogRequests[id] = request

    local timeoutTimer
    timeoutTimer = setTimer(function()
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        if request.status == "pending" then
            request.status = "complete"
            request.error = "Debug log fetch timeout (is client loaded? reconnect after restart agent)"
        end
    end, Agent.DEBUG_LOG_FETCH_TIMEOUT_MS, 1)

    local sent = Agent.callClient(player, "debugLogSnapshot", options, function(clientReturn)
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

        if not clientReturn.ok then
            request.status = "complete"
            request.error = clientReturn.error or "Debug log fetch failed"
            return
        end

        request.status = "complete"

        if side == "client" then
            request.result = clientReturn.result
            return
        end

        local clientEntries = type(clientReturn.result) == "table" and clientReturn.result.entries or {}
        local serverEntries = Agent.serverDebugBuffer:all()
        local merged = Agent.DebugLog.mergeEntries(serverEntries, clientEntries, options)
        request.result = {
            entries = merged,
            count = #merged,
            side = "all",
            serverCount = Agent.serverDebugBuffer:count(),
            clientCount = type(clientReturn.result) == "table" and (clientReturn.result.count or #clientEntries) or
                #clientEntries,
        }
    end)

    if not sent then
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        Agent.debugLogRequests[id] = nil
        return nil, "Client not loaded (player may not have agent on client — reconnect after restart agent)"
    end

    return id
end

---@param id string
---@return AgentHttpPayload|table
function Agent.getDebugLogFetchResult(id)
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end

    local request = Agent.debugLogRequests[id]
    if not request then
        return { ok = false, error = "Request not found" }
    end

    if request.status == "pending" then
        return {
            ok = true,
            id = id,
            status = "pending",
            player = request.player,
            side = request.side,
        }
    end

    if request.error then
        return {
            ok = false,
            id = id,
            status = "complete",
            error = request.error,
            player = request.player,
            side = request.side,
        }
    end

    return {
        ok = true,
        id = id,
        status = "complete",
        player = request.player,
        side = request.side,
        result = request.result,
    }
end

addEventHandler("onDebugMessage", root, Agent.DebugLog.makeCaptureHandler(Agent.serverDebugBuffer, "server"))

setTimer(function()
    local now = getTickCount()
    local ttl = 10 * 60 * 1000
    for requestId, request in pairs(Agent.debugLogRequests) do
        if now - request.createdAt > ttl then
            Agent.debugLogRequests[requestId] = nil
        end
    end
end, 60000, 0)
