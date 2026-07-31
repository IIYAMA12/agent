--- Async client CEGUI scan (open windows + widget trees) requests.
---@class Agent
Agent = Agent or {}

Agent.GUI_SCAN_TIMEOUT_MS = 15000
Agent.guiScanRequests = Agent.guiScanRequests or {}
Agent.guiScanNextId = Agent.guiScanNextId or 0

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return player|nil, string|nil error
local function resolvePlayer(playerName, options)
    return Agent.resolvePlayerElement(playerName, options)
end

---@param options AgentGuiScanOptions|table|nil
---@return AgentGuiScanOptions|table
local function sanitizeGuiScanOptions(options)
    options = type(options) == "table" and options or {}
    return {
        windowTitle = options.windowTitle or options.title or options.search,
        openOnly = options.openOnly,
        visibleOnly = options.visibleOnly,
        maxDepth = options.maxDepth,
        maxNodes = options.maxNodes,
        flat = options.flat,
        trees = options.trees,
        autoTrack = options.autoTrack or options.track,
        trackSource = options.trackSource,
        includeAllElements = options.includeAllElements,
    }
end

---@param playerName string|nil
---@param options AgentGuiScanOptions|table|nil
---@return string|nil id, string|nil error
function Agent.startGuiScan(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return nil, err
    end

    local scanOptions = sanitizeGuiScanOptions(options)

    Agent.guiScanNextId = Agent.guiScanNextId + 1
    local id = "gs-" .. getTickCount() .. "-" .. Agent.guiScanNextId
    local request = {
        id = id,
        status = "pending",
        player = getPlayerName(player),
        createdAt = getTickCount(),
        result = nil,
        error = nil,
    }
    Agent.guiScanRequests[id] = request

    local timeoutTimer
    timeoutTimer = setTimer(function()
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        if request.status == "pending" then
            request.status = "complete"
            request.error = "GUI scan timeout (is client loaded? reconnect after restart agent)"
        end
    end, Agent.GUI_SCAN_TIMEOUT_MS, 1)

    local sent = Agent.callClient(player, "guiScan", scanOptions, function(clientReturn)
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
            if scanOptions.autoTrack then
                Agent.syncClientRegistry(getPlayerName(player))
            end
        else
            request.status = "complete"
            request.error = clientReturn.error or "GUI scan failed"
        end
    end)

    if not sent then
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        Agent.guiScanRequests[id] = nil
        return nil, "Client not loaded (player may not have agent on client — reconnect after restart agent)"
    end

    return id
end

---@param id string
---@return AgentHttpPayload|table
function Agent.getGuiScanResult(id)
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end

    local request = Agent.guiScanRequests[id]
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
        side = "client",
        player = request.player,
        result = request.result,
    }
end

setTimer(function()
    local now = getTickCount()
    local ttl = 10 * 60 * 1000
    for requestId, request in pairs(Agent.guiScanRequests) do
        if now - request.createdAt > ttl then
            Agent.guiScanRequests[requestId] = nil
        end
    end
end, 60000, 0)
