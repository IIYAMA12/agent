--- Forwards virtual indication commands to the client. Drawing stays on the client.
---@class Agent
Agent = Agent or {}

---@param playerName string|nil
---@param options table|nil
---@return table
function Agent.handleIndicate(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return { ok = false, error = err }
    end

    local id, startErr = Agent.startClientRequest(player, "indicate", options, {
        timeoutMs = tonumber(options.timeoutMs) or 15000,
        serial = options.serial,
    })
    if not id then
        return { ok = false, error = startErr }
    end

    return { ok = true, id = id, status = "pending" }
end
