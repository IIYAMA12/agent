--- Client-side event/debug-hook tracker dispatch (start/stop/status/list/clear).

---@class Agent
Agent = Agent or {}

Agent.clientEventTracker = Agent.clientEventTracker or Agent.EventHook.createTracker("client", function()
    if localPlayer and isElement(localPlayer) then
        return getPlayerName(localPlayer)
    end
    return nil
end)

---@param payload AgentEventHookControlOptions|AgentEventHookListOptions|table|nil
---@return AgentHttpPayload response `{ ok = true, result }` or `{ ok = false, error }`
function Agent.handleClientEventHook(payload)
    payload = type(payload) == "table" and payload or {}
    local action = payload.action or "status"

    if action == "start" then
        return { ok = true, result = Agent.clientEventTracker:start(payload) }
    end
    if action == "stop" then
        return { ok = true, result = Agent.clientEventTracker:stop() }
    end
    if action == "clear" then
        return { ok = true, result = Agent.clientEventTracker:clear() }
    end
    if action == "status" then
        return { ok = true, result = Agent.clientEventTracker:status() }
    end
    if action == "list" then
        return { ok = true, result = Agent.clientEventTracker:snapshot(payload) }
    end

    return { ok = false, error = "Unknown event hook action: " .. tostring(action) }
end
