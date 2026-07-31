--- HTTP helpers and resource bootstrap (server).
---@class Agent
Agent = Agent or {}

Agent.PERSIST_MEMORY = true
Agent.RESOURCE_NAME = getResourceName(getThisResource())

-- HTTP /call/ exports run in the server script VM; the `user` global is only
-- available in parsed <html> pages. Access is enforced by protected exports + ACL.

---@param account account|nil
---@return string
function Agent.getHttpAccountName(account)
    if account then
        return getAccountName(account)
    end
    return "http"
end

---@param action string
---@param detail string|nil
---@param account account|nil
---@return nil
function Agent.logHttp(action, detail, account)
    local accountName = Agent.getHttpAccountName(account)
    local host = hostname or "unknown"
    outputServerLog("[agent] " .. accountName .. "@" .. host .. " " .. action .. (detail and (": " .. tostring(detail)) or ""))
end

---@param value any
---@return string
function Agent.toJson(value)
    return toJSON(value, true)
end

---@param text string|nil
---@return any|nil
function Agent.fromJson(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    return fromJSON(text)
end

---@param payload table
---@param statusCode integer|nil
---@return AgentJsonResponse
function Agent.jsonResponse(payload, statusCode)
    return {
        status = statusCode or 200,
        headers = {
            ["content-type"] = "application/json",
        },
        body = Agent.toJson(payload),
    }
end

---@param message string|nil
---@param statusCode integer|nil
---@return AgentJsonResponse
function Agent.errorResponse(message, statusCode)
    return Agent.jsonResponse({ ok = false, error = message }, statusCode or 400)
end

---@param data any
---@param statusCode integer|nil
---@return AgentJsonResponse
function Agent.okResponse(data, statusCode)
    local payload = { ok = true }
    if type(data) == "table" then
        for key, val in pairs(data) do
            payload[key] = val
        end
    else
        payload.result = data
    end
    return Agent.jsonResponse(payload, statusCode or 200)
end

addEventHandler("onResourceStart", resourceRoot, function()
    Agent.initRegistry(getRealTime().timestamp, Agent.ELEMENT_SIDE_SERVER)
    outputServerLog("[agent] Resource started (registry epoch " .. tostring(Agent.registry.startupAt) .. ")")
end)
