--- Client-side health/performance snapshot (memory, network, dx status, CPU).

---@class Agent
Agent = Agent or {}

---@param options AgentHealthOptions|table|nil
---@return AgentHealthSnapshot snapshot
function Agent.getClientHealthSnapshot(options)
    options = type(options) == "table" and options or {}

    local playerName = nil
    if localPlayer and isElement(localPlayer) then
        playerName = getPlayerName(localPlayer)
    end

    return Agent.Health.collectSnapshot(options, {
        side = "client",
        player = playerName,
    })
end
