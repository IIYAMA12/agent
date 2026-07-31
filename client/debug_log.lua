--- Client-side debug message capture buffer, fed from `onClientDebugMessage`.

---@class Agent
Agent = Agent or {}

Agent.clientDebugBuffer = Agent.clientDebugBuffer or Agent.DebugLog.createBuffer(Agent.DebugLog.MAX_SIZE)

---@param entry AgentDebugLogEntry
---@return nil
local function enrichClientEntry(entry)
    if localPlayer and isElement(localPlayer) then
        entry.player = getPlayerName(localPlayer)
    end
end

addEventHandler(
    "onClientDebugMessage",
    root,
    Agent.DebugLog.makeCaptureHandler(Agent.clientDebugBuffer, "client", enrichClientEntry)
)

---@param options AgentDebugLogOptions|table|nil
---@return AgentDebugLogSnapshot snapshot
function Agent.getClientDebugLogSnapshot(options)
    options = type(options) == "table" and options or {}
    local entries = Agent.DebugLog.filterEntries(Agent.clientDebugBuffer:all(), options)
    return {
        entries = entries,
        count = #entries,
        bufferCount = Agent.clientDebugBuffer:count(),
        side = "client",
    }
end
