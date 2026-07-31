--- Server-side key/value memory store, with optional SQLite persistence.
---@class Agent
Agent = Agent or {}

Agent.memoryStore = Agent.memoryStore or {}
Agent.dbConnection = Agent.dbConnection or nil
Agent.dbReady = Agent.dbReady or false

---@return string
local function getDbPath()
    return ":" .. Agent.RESOURCE_NAME .. "/data/memory.db"
end

---@return boolean
local function ensureDb()
    if not Agent.PERSIST_MEMORY then
        return false
    end
    if Agent.dbReady and Agent.dbConnection then
        return true
    end

    local dbPath = getDbPath()
    Agent.dbConnection = dbConnect("sqlite", dbPath)
    if not Agent.dbConnection then
        outputDebugString("[agent] Failed to connect SQLite at " .. dbPath, 2)
        return false
    end

    dbExec(Agent.dbConnection, [[
        CREATE TABLE IF NOT EXISTS memory (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        )
    ]])

    Agent.dbReady = true
    return true
end

---@param key string
---@param value any
---@return boolean, any value|error
function Agent.memorySet(key, value)
    if type(key) ~= "string" or key == "" then
        return false, "Key must be a non-empty string"
    end

    Agent.memoryStore[key] = value

    if Agent.PERSIST_MEMORY and ensureDb() then
        local encoded = Agent.toJson(value)
        local now = getRealTime().timestamp
        dbExec(
            Agent.dbConnection,
            "INSERT OR REPLACE INTO memory (key, value, updated_at) VALUES (?, ?, ?)",
            key,
            encoded,
            now
        )
    end

    return true, value
end

---@param key string
---@return boolean, any value|error
function Agent.memoryGet(key)
    if type(key) ~= "string" or key == "" then
        return false, "Key must be a non-empty string"
    end

    if Agent.memoryStore[key] ~= nil then
        return true, Agent.memoryStore[key]
    end

    if Agent.PERSIST_MEMORY and ensureDb() then
        local query = dbQuery(Agent.dbConnection, "SELECT value FROM memory WHERE key = ? LIMIT 1", key)
        if query then
            local result = dbPoll(query, -1)
            dbFree(query)
            if result and result[1] then
                local decoded = Agent.fromJson(result[1].value)
                Agent.memoryStore[key] = decoded
                return true, decoded
            end
        end
    end

    return true, nil
end

---@param key string
---@return boolean, string|nil error
function Agent.memoryDelete(key)
    if type(key) ~= "string" or key == "" then
        return false, "Key must be a non-empty string"
    end

    Agent.memoryStore[key] = nil

    if Agent.PERSIST_MEMORY and ensureDb() then
        dbExec(Agent.dbConnection, "DELETE FROM memory WHERE key = ?", key)
    end

    return true
end

---@param prefix string|nil
---@return string[] keys
function Agent.memoryList(prefix)
    prefix = prefix or ""
    local keys = {}
    local seen = {}

    for key in pairs(Agent.memoryStore) do
        if prefix == "" or string.sub(key, 1, #prefix) == prefix then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end

    if Agent.PERSIST_MEMORY and ensureDb() then
        local query
        if prefix == "" then
            query = dbQuery(Agent.dbConnection, "SELECT key FROM memory ORDER BY key ASC")
        else
            query = dbQuery(Agent.dbConnection, "SELECT key FROM memory WHERE key LIKE ? ORDER BY key ASC", prefix .. "%")
        end

        if query then
            local result = dbPoll(query, -1)
            dbFree(query)
            if result then
                for i = 1, #result do
                    local key = result[i].key
                    if not seen[key] then
                        keys[#keys + 1] = key
                    end
                end
            end
        end
    end

    table.sort(keys)
    return keys
end
