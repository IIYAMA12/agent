--- Server-side event tracing: start/stop/list hooked events, merged with client-side traces on demand.
---@class Agent
Agent = Agent or {}

Agent.EVENT_HOOK_TIMEOUT_MS = 15000
Agent.eventHookRequests = Agent.eventHookRequests or {}
Agent.eventHookNextId = Agent.eventHookNextId or 0
Agent.serverEventTracker = Agent.serverEventTracker or Agent.EventHook.createTracker("server")

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

---@param side string|nil
---@return boolean
local function needsClient(side)
    return side == "client" or side == "all"
end

---@param options AgentEventHookListOptions|table|nil
---@return AgentEventHookListOptions|table
local function sanitizeListOptions(options)
    options = type(options) == "table" and options or {}
    return {
        side = normalizeSide(options.side),
        eventName = options.eventName or options.event,
        hookType = options.hookType,
        resource = options.resource,
        limit = options.limit,
        sinceSeq = options.sinceSeq,
        sinceTick = options.sinceTick,
        dedupe = options.dedupe,
        serial = options.serial,
    }
end

---@param options AgentEventHookControlOptions|table|nil
---@return AgentEventHookControlOptions|table
local function sanitizeControlOptions(options)
    options = type(options) == "table" and options or {}
    return {
        side = normalizeSide(options.side),
        hookTypes = options.hookTypes,
        nameList = options.nameList,
        events = options.events,
        event = options.event,
        serial = options.serial,
    }
end

---@param options AgentEventHookListOptions|table
---@return AgentEventHookSnapshot|table
local function buildServerListSnapshot(options)
    return Agent.serverEventTracker:snapshot(options)
end

---@return AgentEventHookStatus|table
function Agent.getServerEventHookStatus()
    return Agent.serverEventTracker:status()
end

---@param action string
---@param options AgentEventHookControlOptions|table
---@return AgentHttpPayload|table
local function applyServerControl(action, options)
    if action == "start" then
        return { ok = true, result = Agent.serverEventTracker:start(options) }
    end
    if action == "stop" then
        return { ok = true, result = Agent.serverEventTracker:stop() }
    end
    if action == "clear" then
        return { ok = true, result = Agent.serverEventTracker:clear() }
    end
    if action == "status" then
        return { ok = true, result = Agent.serverEventTracker:status() }
    end
    return { ok = false, error = "Unknown action: " .. tostring(action) }
end

---@param playerName string|nil
---@param action string
---@param options AgentEventHookControlOptions|table|nil
---@return string|nil id, string|nil error
function Agent.startEventHookRequest(playerName, action, options)
    options = sanitizeControlOptions(options)
    local side = options.side

    if not needsClient(side) then
        return nil, "Use sync control for server-side event hooks"
    end

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return nil, err
    end

    Agent.eventHookNextId = Agent.eventHookNextId + 1
    local id = "ev-" .. getTickCount() .. "-" .. Agent.eventHookNextId
    local request = {
        id = id,
        status = "pending",
        action = action,
        player = getPlayerName(player),
        side = side,
        options = options,
        createdAt = getTickCount(),
        result = nil,
        error = nil,
    }
    Agent.eventHookRequests[id] = request

    local timeoutTimer
    timeoutTimer = setTimer(function()
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        if request.status == "pending" then
            request.status = "complete"
            request.error = "Event hook request timeout (is client loaded? reconnect after restart agent)"
        end
    end, Agent.EVENT_HOOK_TIMEOUT_MS, 1)

    local payload = {
        action = action,
        hookTypes = options.hookTypes,
        nameList = options.nameList,
        events = options.events,
        event = options.event,
    }

    local sent = Agent.callClient(player, "debugEventHook", payload, function(clientReturn)
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
            request.error = clientReturn.error or "Event hook request failed"
            return
        end

        request.status = "complete"

        if action == "status" then
            if side == "client" then
                request.result = clientReturn.result
            else
                request.result = {
                    server = Agent.serverEventTracker:status(),
                    client = clientReturn.result,
                    side = "all",
                }
            end
            return
        end

        if side == "client" then
            request.result = clientReturn.result
            return
        end

        request.result = {
            server = Agent.serverEventTracker:status(),
            client = clientReturn.result,
            side = "all",
        }
    end)

    if not sent then
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        Agent.eventHookRequests[id] = nil
        return nil, "Client not loaded (player may not have agent on client — reconnect after restart agent)"
    end

    return id
end

---@param playerName string|nil
---@param options AgentEventHookListOptions|table|nil
---@return string|nil id, string|nil error
function Agent.startEventHookList(playerName, options)
    options = sanitizeListOptions(options)
    local side = options.side

    if side == "server" then
        return nil, "Use sync list for server-side event hooks"
    end

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return nil, err
    end

    Agent.eventHookNextId = Agent.eventHookNextId + 1
    local id = "ev-" .. getTickCount() .. "-" .. Agent.eventHookNextId
    local request = {
        id = id,
        status = "pending",
        action = "list",
        player = getPlayerName(player),
        side = side,
        options = options,
        createdAt = getTickCount(),
        result = nil,
        error = nil,
    }
    Agent.eventHookRequests[id] = request

    local timeoutTimer
    timeoutTimer = setTimer(function()
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        if request.status == "pending" then
            request.status = "complete"
            request.error = "Event hook list timeout (is client loaded? reconnect after restart agent)"
        end
    end, Agent.EVENT_HOOK_TIMEOUT_MS, 1)

    local sent = Agent.callClient(player, "debugEventHook", {
        action = "list",
        limit = options.limit,
        sinceSeq = options.sinceSeq,
        sinceTick = options.sinceTick,
        dedupe = options.dedupe,
        eventName = options.eventName,
        hookType = options.hookType,
        resource = options.resource,
    }, function(clientReturn)
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
            request.error = clientReturn.error or "Event hook list failed"
            return
        end

        request.status = "complete"

        if side == "client" then
            request.result = clientReturn.result
            return
        end

        local clientEntries = type(clientReturn.result) == "table" and clientReturn.result.entries or {}
        local serverEntries = Agent.serverEventTracker.buffer:all()
        local merged = Agent.EventHook.mergeEntries(serverEntries, clientEntries, options)
        request.result = {
            entries = merged,
            count = #merged,
            side = "all",
            serverCount = Agent.serverEventTracker.buffer:count(),
            clientCount = type(clientReturn.result) == "table" and (clientReturn.result.count or #clientEntries) or
            #clientEntries,
            status = {
                server = Agent.serverEventTracker:status(),
                client = type(clientReturn.result) == "table" and clientReturn.result.status or nil,
            },
        }
    end)

    if not sent then
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        Agent.eventHookRequests[id] = nil
        return nil, "Client not loaded (player may not have agent on client — reconnect after restart agent)"
    end

    return id
end

---@param id string
---@return AgentHttpPayload|table
function Agent.getEventHookRequestResult(id)
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end

    local request = Agent.eventHookRequests[id]
    if not request then
        return { ok = false, error = "Request not found" }
    end

    if request.status == "pending" then
        return {
            ok = true,
            id = id,
            status = "pending",
            action = request.action,
            player = request.player,
            side = request.side,
        }
    end

    if request.error then
        return {
            ok = false,
            id = id,
            status = "complete",
            action = request.action,
            error = request.error,
            player = request.player,
            side = request.side,
        }
    end

    return {
        ok = true,
        id = id,
        status = "complete",
        action = request.action,
        player = request.player,
        side = request.side,
        result = request.result,
    }
end

---@param playerName string|nil
---@param options AgentEventHookControlOptions|AgentEventHookListOptions|table|nil
---@return AgentHttpPayload|table
function Agent.handleDebugEvents(playerName, options)
    options = type(options) == "table" and options or {}
    local action = options.action or "list"

    if action == "status" then
        local side = normalizeSide(options.side)
        if side == "server" then
            return { ok = true, result = { server = Agent.serverEventTracker:status() } }
        end
        if side == "client" then
            local id, err = Agent.startEventHookRequest(playerName, "status", options)
            if not id then
                return { ok = false, error = err }
            end
            return { ok = true, id = id, status = "pending", action = action, side = side }
        end
        local id, err = Agent.startEventHookRequest(playerName, "status", { side = "all", serial = options.serial })
        if not id then
            return { ok = false, error = err }
        end
        return { ok = true, id = id, status = "pending", action = action, side = side }
    end

    if action == "list" then
        local listOptions = sanitizeListOptions(options)
        if listOptions.side == "server" then
            return { ok = true, status = "complete", action = action, result = buildServerListSnapshot(listOptions) }
        end
        local id, err = Agent.startEventHookList(playerName, listOptions)
        if not id then
            return { ok = false, error = err }
        end
        return { ok = true, id = id, status = "pending", action = action, side = listOptions.side }
    end

    if action == "start" or action == "stop" or action == "clear" then
        local controlOptions = sanitizeControlOptions(options)
        local side = controlOptions.side

        if not needsClient(side) then
            return applyServerControl(action, controlOptions)
        end

        if side == "all" and (action == "start" or action == "stop" or action == "clear") then
            applyServerControl(action, controlOptions)
        end

        local id, err = Agent.startEventHookRequest(playerName, action, controlOptions)
        if not id then
            return { ok = false, error = err }
        end
        return { ok = true, id = id, status = "pending", action = action, side = side }
    end

    return { ok = false, error = "Unknown action: " .. tostring(action) }
end

setTimer(function()
    local now = getTickCount()
    local ttl = 10 * 60 * 1000
    for requestId, request in pairs(Agent.eventHookRequests) do
        if now - request.createdAt > ttl then
            Agent.eventHookRequests[requestId] = nil
        end
    end
end, 60000, 0)
