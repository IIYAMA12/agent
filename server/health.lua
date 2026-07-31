--- Server/client/merged health snapshot fetches (FPS, memory, CPU, network, performance stats).
---@class Agent
Agent = Agent or {}

Agent.HEALTH_FETCH_TIMEOUT_MS = 15000
Agent.healthRequests = Agent.healthRequests or {}
Agent.healthNextId = Agent.healthNextId or 0

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return player|nil, string|nil error
local function resolvePlayer(playerName, options)
    return Agent.resolvePlayerElement(playerName, options)
end

---@param side string|nil
---@return "server"|"client"|"all"
local function normalizeSide(side)
    side = type(side) == "string" and side or "server"
    if side ~= "server" and side ~= "client" and side ~= "all" then
        return "server"
    end
    return side
end

---@param options AgentHealthOptions|table|nil
---@return AgentHealthOptions|table
function Agent.sanitizeHealthOptions(options)
    options = type(options) == "table" and options or {}

    return {
        side = normalizeSide(options.side),
        serial = options.serial,
        networkUsage = options.networkUsage,
        networkUsageLimit = options.networkUsageLimit,
        performanceCategory = options.performanceCategory,
        performanceCategories = options.performanceCategories,
        performanceOptions = options.performanceOptions,
        performanceFilter = options.performanceFilter,
        listPerformanceCategories = options.listPerformanceCategories,
        includeCpu = options.includeCpu,
        includeLuaCpu = options.includeLuaCpu,
        luaCpuLimit = options.luaCpuLimit,
    }
end

---@param options AgentHealthOptions|table|nil
---@param playerElement player|nil
---@return AgentHealthSnapshot|table
function Agent.collectServerHealth(options, playerElement)
    options = Agent.sanitizeHealthOptions(options)

    local playerName = nil
    if playerElement and isElement(playerElement) then
        playerName = getPlayerName(playerElement)
    end

    return Agent.Health.collectSnapshot(options, {
        side = "server",
        player = playerName,
        playerElement = playerElement,
    })
end

---@param playerName string|nil
---@param options AgentHealthOptions|table|nil
---@return string|nil id
---@return string|nil error
function Agent.startHealthFetch(playerName, options)
    options = Agent.sanitizeHealthOptions(options)
    local side = options.side

    if side == "server" then
        return nil, "Use sync fetch for server-side health"
    end

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return nil, err
    end

    Agent.healthNextId = Agent.healthNextId + 1
    local id = "hp-" .. getTickCount() .. "-" .. Agent.healthNextId
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
    Agent.healthRequests[id] = request

    local timeoutTimer
    timeoutTimer = setTimer(function()
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        if request.status == "pending" then
            request.status = "complete"
            request.error = "Health fetch timeout (is client loaded? reconnect after restart agent)"
        end
    end, Agent.HEALTH_FETCH_TIMEOUT_MS, 1)

    local sent = Agent.callClient(player, "healthSnapshot", options, function(clientReturn)
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
            request.error = clientReturn.error or "Health fetch failed"
            return
        end

        request.status = "complete"

        if side == "client" then
            request.result = clientReturn.result
            return
        end

        request.result = {
            server = Agent.collectServerHealth(options, player),
            client = clientReturn.result,
            side = "all",
            player = request.player,
        }
    end)

    if not sent then
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        Agent.healthRequests[id] = nil
        return nil, "Client not loaded (player may not have agent on client — reconnect after restart agent)"
    end

    return id
end

---@param id string
---@return AgentHttpPayload|table
function Agent.getHealthFetchResult(id)
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end

    local request = Agent.healthRequests[id]
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

---@param playerName string|nil
---@param options AgentHealthOptions|table|nil
---@return AgentHttpPayload|table
function Agent.handleHealthGet(playerName, options)
    options = Agent.sanitizeHealthOptions(options)
    local side = options.side

    if side == "server" then
        local player = nil
        if playerName or options.serial then
            local resolved, err = resolvePlayer(playerName, options)
            if not resolved then
                return { ok = false, error = err }
            end
            player = resolved
        end
        return {
            ok = true,
            status = "complete",
            side = "server",
            result = Agent.collectServerHealth(options, player),
        }
    end

    local id, err = Agent.startHealthFetch(playerName, options)
    if not id then
        return { ok = false, error = err }
    end

    return { ok = true, id = id, status = "pending", side = side }
end

setTimer(function()
    local now = getTickCount()
    local ttl = 10 * 60 * 1000
    for requestId, request in pairs(Agent.healthRequests) do
        if now - request.createdAt > ttl then
            Agent.healthRequests[requestId] = nil
        end
    end
end, 60000, 0)
