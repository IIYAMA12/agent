--- Async server-side eval of client Lua code across one or more players.
---@class Agent
Agent = Agent or {}

Agent.CLIENT_EVAL_TIMEOUT_MS = 5000
---@type table<string, AgentClientEvalRequest>
Agent.clientEvalRequests = Agent.clientEvalRequests or {}
Agent.clientEvalNextId = Agent.clientEvalNextId or 0

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return player[]|nil targets
---@return string|nil error
local function resolveTargets(playerName, options)
    if playerName == "*" then
        local players = getElementsByType("player")
        if #players == 0 then
            return nil, "No players online"
        end
        return players
    end

    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return nil, err
    end

    return { player }
end

---@param clientReturn table|any
---@return table
local function parseClientReturn(clientReturn)
    if type(clientReturn) ~= "table" then
        return { ok = false, error = "No client response" }
    end
    return clientReturn
end

---@return string
local function createClientEvalId()
    Agent.clientEvalNextId = Agent.clientEvalNextId + 1
    return "ce-" .. getTickCount() .. "-" .. Agent.clientEvalNextId
end

---@param request AgentClientEvalRequest
---@return nil
local function finalizeClientEvalResults(request)
    local ordered = {}
    for i = 1, #(request.resultSlots or {}) do
        ordered[i] = request.resultSlots[i]
    end
    request.results = ordered
    request.resultSlots = nil
    request.status = "complete"
end

---@param id string
---@param resultIndex integer
---@param playerName string
---@param response { ok: boolean, result?: any, error?: string }|table
---@return nil
function Agent.onClientEvalPlayerDone(id, resultIndex, playerName, response)
    ---@type AgentClientEvalRequest|nil
    local request = Agent.clientEvalRequests[id]
    if not request or request.status ~= "pending" then
        return
    end

    if not request.resultSlots or request.resultSlots[resultIndex] then
        return
    end

    request.resultSlots[resultIndex] = {
        player = playerName,
        ok = response.ok,
        result = response.result,
        error = response.error,
    }

    request.pending = request.pending - 1
    if request.pending <= 0 then
        finalizeClientEvalResults(request)
    end
end

---@param code string
---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return string|nil id
---@return string|nil error
function Agent.startClientEval(code, playerName, options)
    if type(code) ~= "string" or code == "" then
        return nil, "Code must be a non-empty string"
    end

    options = type(options) == "table" and options or {}

    local targets, err = resolveTargets(playerName, options)
    if not targets then
        return nil, err
    end

    local id = createClientEvalId()
    ---@type AgentClientEvalRequest
    local request = {
        id = id,
        status = "pending",
        pending = #targets,
        resultSlots = {},
        results = nil,
        createdAt = getTickCount(),
    }
    Agent.clientEvalRequests[id] = request

    for index, player in ipairs(targets) do
        local name = getPlayerName(player)
        local timeoutTimer

        timeoutTimer = setTimer(function()
            if isTimer(timeoutTimer) then
                killTimer(timeoutTimer)
            end
            Agent.onClientEvalPlayerDone(id, index, name, {
                ok = false,
                error = "Client eval timeout",
            })
        end, Agent.CLIENT_EVAL_TIMEOUT_MS, 1)

        local sent = Agent.callClient(player, "runEval", { code = code }, function(clientReturn)
            if isTimer(timeoutTimer) then
                killTimer(timeoutTimer)
            end
            Agent.onClientEvalPlayerDone(id, index, name, parseClientReturn(clientReturn))
        end)

        if not sent then
            if isTimer(timeoutTimer) then
                killTimer(timeoutTimer)
            end
            Agent.onClientEvalPlayerDone(id, index, name, {
                ok = false,
                error = "Client not loaded (player may not have agent on client)",
            })
        end
    end

    return id
end

---@param id string
---@return AgentHttpPayload|table
function Agent.getClientEvalResult(id)
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end

    ---@type AgentClientEvalRequest|nil
    local request = Agent.clientEvalRequests[id]
    if not request then
        return { ok = false, error = "Request not found" }
    end

    return {
        ok = true,
        id = id,
        status = request.status,
        results = request.results,
    }
end

setTimer(function()
    local now = getTickCount()
    local ttl = 10 * 60 * 1000
    for requestId, request in pairs(Agent.clientEvalRequests) do
        if now - request.createdAt > ttl then
            Agent.clientEvalRequests[requestId] = nil
        end
    end
end, 60000, 0)
