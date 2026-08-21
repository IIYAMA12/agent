--- Server: start async client model replace / restore jobs.

---@class Agent
Agent = Agent or {}

Agent.MODEL_REPLACE_TIMEOUT_MS = 30000

---@param playerName string|nil
---@param options table|nil
---@return player|nil, string|nil
local function resolvePlayer(playerName, options)
    return Agent.resolvePlayerElement(playerName, options)
end

---@param playerName string|nil
---@param options table|nil
---@return string|nil id, string|nil error
function Agent.startModelReplaceTest(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return nil, err
    end

    if type(options.dff) ~= "string" or type(options.txd) ~= "string" or type(options.col) ~= "string" then
        return nil, "dff, txd, and col (base64) are required"
    end

    return Agent.startClientRequest(player, "modelReplace", {
        id = options.id,
        modelId = tonumber(options.modelId) or 1851,
        dff = options.dff,
        txd = options.txd,
        col = options.col,
        encoding = options.encoding or "base64",
        compressed = options.compressed or "gzip",
        offsetDistance = options.offsetDistance,
        offsetZ = options.offsetZ,
    }, {
        timeoutMs = Agent.MODEL_REPLACE_TIMEOUT_MS,
        serial = options.serial,
    })
end

---@param playerName string|nil
---@param options table|nil
---@return string|nil id, string|nil error
function Agent.startModelRestore(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return nil, err
    end

    return Agent.startClientRequest(player, "modelRestore", {
        modelId = options.modelId and tonumber(options.modelId) or nil,
    }, {
        timeoutMs = 15000,
        serial = options.serial,
    })
end

---@param id string
---@return table
function Agent.getModelReplaceResult(id)
    return Agent.getClientRequestResult(id)
end
