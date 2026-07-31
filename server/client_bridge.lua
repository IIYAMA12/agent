--- Server<->client request/response bridge used to run async actions on a player's client.
---@class Agent
Agent = Agent or {}

Agent.CLIENT_EVENT_REQUEST = "agent:clientRequest"
Agent.CLIENT_EVENT_RESPONSE = "agent:clientResponse"
Agent.CLIENT_EVENT_READY = "agent:clientReady"
Agent.CLIENT_RESPONSE_TIMEOUT_MS = 5000

Agent.clientCallbacks = Agent.clientCallbacks or {}
Agent.loadedClients = Agent.loadedClients or {}
Agent.clientNextId = Agent.clientNextId or 0

addEvent(Agent.CLIENT_EVENT_RESPONSE, true)
addEvent(Agent.CLIENT_EVENT_READY, true)

addEventHandler(Agent.CLIENT_EVENT_RESPONSE, resourceRoot, function(requestId, response)
    if not client or source ~= resourceRoot then
        return
    end

    local callback = Agent.clientCallbacks[requestId]
    if not callback then
        return
    end

    Agent.clientCallbacks[requestId] = nil
    callback(response)
end)

addEventHandler(Agent.CLIENT_EVENT_READY, resourceRoot, function()
    if not client or source ~= resourceRoot then
        return
    end

    Agent.loadedClients[client] = true
end)

local thisResource = getThisResource()
addEventHandler("onPlayerResourceStart", root, function(startedResource)
    if startedResource ~= thisResource then
        return
    end
    Agent.loadedClients[source] = true
end, false, "low")

addEventHandler("onPlayerQuit", root, function()
    Agent.loadedClients[source] = nil
end)

---@param player player
---@return boolean
function Agent.isClientLoaded(player)
    return Agent.loadedClients[player] == true
end

---@param player player
---@param action string
---@param payload any
---@param callback fun(clientReturn: table)|nil
---@return boolean
function Agent.callClient(player, action, payload, callback)
    if not isElement(player) or getElementType(player) ~= "player" then
        return false
    end

    if not Agent.isClientLoaded(player) then
        return false
    end

    if type(action) ~= "string" or action == "" then
        return false
    end

    Agent.clientNextId = Agent.clientNextId + 1
    local requestId = "cr-" .. getTickCount() .. "-" .. Agent.clientNextId

    if type(callback) == "function" then
        Agent.clientCallbacks[requestId] = callback
    end

    local payloadTable = type(payload) == "table" and payload or { value = payload }
    return triggerClientEvent(
        player,
        Agent.CLIENT_EVENT_REQUEST,
        resourceRoot,
        requestId,
        action,
        payloadTable
    )
end

Agent.CLIENT_REQUEST_TIMEOUT_MS = 15000
---@type table<string, AgentAsyncRequest>
Agent.clientRequests = Agent.clientRequests or {}
Agent.clientRequestNextId = Agent.clientRequestNextId or 0

---@param player player|string
---@param options AgentResolvePlayerOptions|table|nil
---@return player|nil
---@return string|nil err
local function resolveClientRequestPlayer(player, options)
    if type(player) ~= "string" and isElement(player) and getElementType(player) == "player" then
        ---@cast player player
        return player
    end
    if type(player) == "string" and type(Agent.resolvePlayerElement) == "function" then
        return Agent.resolvePlayerElement(player, options)
    end
    return nil, "Invalid player"
end

-- Start an async client request. Because MTA HTTP export calls cannot block
-- for a client round-trip (the response event only fires after the export
-- returns), callers must poll Agent.getClientRequestResult(id) instead of
-- waiting inline. opts: { timeoutMs, onComplete(request, clientReturn) }.
---@param player player|string
---@param action string
---@param payload any
---@param opts AgentClientRequestOpts|table|nil
---@return string|nil id, string|nil error
function Agent.startClientRequest(player, action, payload, opts)
    opts = type(opts) == "table" and opts or {}
    local timeoutMs = opts.timeoutMs or Agent.CLIENT_REQUEST_TIMEOUT_MS

    local playerElement, err = resolveClientRequestPlayer(player, opts)
    if not playerElement then
        return nil, err or "Invalid player"
    end

    Agent.clientRequestNextId = Agent.clientRequestNextId + 1
    local id = "clr-" .. getTickCount() .. "-" .. Agent.clientRequestNextId
    ---@type AgentAsyncRequest
    local request = {
        id = id,
        status = "pending",
        action = action,
        player = getPlayerName(playerElement),
        createdAt = getTickCount(),
        result = nil,
        error = nil,
    }
    Agent.clientRequests[id] = request

    local timeoutTimer
    timeoutTimer = setTimer(function()
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        if request.status == "pending" then
            request.status = "complete"
            request.error = "Client response timeout (is client loaded? reconnect after restart agent)"
        end
    end, timeoutMs, 1)

    local sent = Agent.callClient(playerElement, action, payload, function(clientReturn)
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
            request.entry = clientReturn.entry
            request.entries = clientReturn.entries
            if type(opts.onComplete) == "function" then
                opts.onComplete(request, clientReturn)
            end
        else
            request.status = "complete"
            request.error = clientReturn.error or "Client action failed"
            request.details = clientReturn.details
        end
    end)

    if not sent then
        if isTimer(timeoutTimer) then
            killTimer(timeoutTimer)
        end
        Agent.clientRequests[id] = nil
        return nil, "Client not loaded (player may not have agent on client — reconnect after restart agent)"
    end

    return id
end

---@param id string
---@return AgentHttpPayload|table
function Agent.getClientRequestResult(id)
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end

    ---@type AgentAsyncRequest|nil
    local request = Agent.clientRequests[id]
    if not request then
        return { ok = false, error = "Request not found" }
    end

    if request.status == "pending" then
        return {
            ok = true,
            id = id,
            status = "pending",
            side = "client",
            player = request.player,
        }
    end

    if request.error then
        return {
            ok = false,
            id = id,
            status = "complete",
            side = "client",
            error = request.error,
            details = request.details,
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
        entry = request.entry,
        entries = request.entries,
    }
end

setTimer(function()
    local now = getTickCount()
    local ttl = 60 * 1000
    for requestId, callback in pairs(Agent.clientCallbacks) do
        if type(requestId) == "string" then
            local createdAt = tonumber(requestId:match("^cr%-(%d+)%-"))
            if createdAt and now - createdAt > ttl then
                Agent.clientCallbacks[requestId] = nil
            end
        else
            Agent.clientCallbacks[requestId] = nil
        end
    end

    local requestTtl = 10 * 60 * 1000
    for requestId, request in pairs(Agent.clientRequests) do
        if now - (request.createdAt or 0) > requestTtl then
            Agent.clientRequests[requestId] = nil
        end
    end
end, 30000, 0)
