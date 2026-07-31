--- Eval helpers shared by server and client.
---@class Agent
Agent = Agent or {}

local MAX_SERIALIZE_DEPTH = 8
local EVAL_DENIED_MESSAGE = "mpc denied access"

--- Names replaced with a deny wrapper inside `Agent.runEval` (Lua 5.1 setfenv sandbox).
--- Covers ACL + file APIs, server password, and other high-risk server APIs / escape hatches.
local EVAL_BLOCKED_NAMES = {
    -- ACL (https://wiki.multitheftauto.com/wiki/Server_Scripting_Functions#ACL_functions)
    "aclCreate",
    "aclCreateGroup",
    "aclDestroy",
    "aclDestroyGroup",
    "aclGet",
    "aclGetGroup",
    "aclGetName",
    "aclGetRight",
    "aclGroupAddACL",
    "aclGroupAddObject",
    "aclGroupGetName",
    "aclGroupList",
    "aclGroupListACL",
    "aclGroupListObjects",
    "aclGroupRemoveACL",
    "aclObjectGetGroups",
    "aclGroupRemoveObject",
    "aclList",
    "aclListRights",
    "aclReload",
    "aclRemoveRight",
    "aclSave",
    "aclSetRight",
    "hasObjectPermissionTo",
    "isObjectInACLGroup",
    "updateResourceACLRequest",
    "getResourceACLRequests",

    -- File (https://wiki.multitheftauto.com/wiki/Server_Scripting_Functions#File_functions)
    "fileClose",
    "fileCopy",
    "fileCreate",
    "fileDelete",
    "fileExists",
    "fileFlush",
    "fileGetContents",
    "fileGetHash",
    "fileGetPath",
    "fileGetPos",
    "fileGetSize",
    "fileIsEOF",
    "fileOpen",
    "fileRead",
    "fileRename",
    "fileSetPos",
    "fileWrite",

    -- Server password / config / process
    "getServerPassword",
    "setServerPassword",
    "setServerConfigSetting",
    "getServerConfigSetting",
    "shutdown",

    -- Admin
    "addBan",
    "banPlayer",
    "kickPlayer",
    "removeBan",
    "reloadBans",
    "setBanAdmin",
    "setBanNick",
    "setBanReason",
    "setUnbanTime",

    -- Account mutation / auth
    "addAccount",
    "removeAccount",
    "setAccountPassword",
    "setAccountName",
    "setAccountData",
    "copyAccountData",
    "logIn",
    "logOut",

    -- XML (can rewrite acl.xml / configs)
    "xmlCopyFile",
    "xmlCreateChild",
    "xmlCreateFile",
    "xmlDestroyNode",
    "xmlLoadFile",
    "xmlLoadString",
    "xmlNodeSetAttribute",
    "xmlNodeSetName",
    "xmlNodeSetValue",
    "xmlSaveFile",
    "xmlUnloadFile",

    -- Resource / remote / SQL control
    "startResource",
    "stopResource",
    "restartResource",
    "refreshResources",
    "fetchRemote",
    "call",
    "executeCommandHandler",
    "executeSQLQuery",
    "dbConnect",
    "dbExec",
    "dbQuery",
    "dbFree",
    "dbPoll",
    "dbPrepareString",

    -- Sandbox escape hatches (Lua 5.1)
    "loadstring",
    "load",
    "loadfile",
    "dofile",
    "getfenv",
    "setfenv",
    "debug",
}

---@type table<string, boolean>
local EVAL_BLOCKED = {}
for i = 1, #EVAL_BLOCKED_NAMES do
    EVAL_BLOCKED[EVAL_BLOCKED_NAMES[i]] = true
end

---@return nil
local function evalDeniedAccess()
    error(EVAL_DENIED_MESSAGE, 2)
end

---@return table sandboxEnv
local function createEvalSandboxEnv()
    local env = {}

    for i = 1, #EVAL_BLOCKED_NAMES do
        env[EVAL_BLOCKED_NAMES[i]] = evalDeniedAccess
    end

    env._G = env

    setmetatable(env, {
        __index = function(_, key)
            if EVAL_BLOCKED[key] then
                return evalDeniedAccess
            end
            return _G[key]
        end,
        __newindex = function(t, key, value)
            if EVAL_BLOCKED[key] then
                rawset(t, key, evalDeniedAccess)
                return
            end
            rawset(t, key, value)
        end,
    })

    return env
end

---@param fn function
---@return function
local function applyEvalSandbox(fn)
    local env = createEvalSandboxEnv()
    if type(setfenv) == "function" then
        setfenv(fn, env)
    end
    return fn
end

---@param value any
---@param depth integer|nil
---@param seen table|nil
---@return any
local function serializeValue(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local valueType = type(value)

    if valueType == "nil" or valueType == "boolean" or valueType == "number" then
        return value
    end

    if valueType == "string" then
        return value
    end

    if valueType == "function" or valueType == "userdata" or valueType == "thread" then
        return "[unsupported type:" .. valueType .. "]"
    end

    if valueType == "table" then
        if depth >= MAX_SERIALIZE_DEPTH then
            return "[max depth]"
        end
        if seen[value] then
            return "[circular]"
        end
        seen[value] = true

        local result = {}
        local index = 1
        for i, item in ipairs(value) do
            result[i] = serializeValue(item, depth + 1, seen)
            index = i + 1
        end
        for key, item in pairs(value) do
            if type(key) ~= "number" or key < 1 or key >= index or math.floor(key) ~= key then
                local serializedKey = tostring(key)
                result[serializedKey] = serializeValue(item, depth + 1, seen)
            end
        end
        return result
    end

    if isElement(value) then
        local tracked = type(Agent.getRegistryEntryForElement) == "function" and Agent.getRegistryEntryForElement(value)
        if tracked and tracked.id then
            return {
                _type = "element",
                agentId = tracked.id,
                elementType = getElementType(value),
                side = tracked.side,
                localOnly = tracked.localOnly == true,
                id = tostring(value),
            }
        end

        return {
            _type = "element",
            elementType = getElementType(value),
            id = tostring(value),
        }
    end

    return tostring(value)
end

---@param results table
---@return any|nil
function Agent.serializeResults(results)
    if #results <= 1 then
        return nil
    end

    if #results == 2 then
        return serializeValue(results[2])
    end

    local serialized = {}
    for i = 2, #results do
        serialized[i - 1] = serializeValue(results[i])
    end
    return serialized
end

---@param code string
---@return boolean ok
---@return any|string|nil resultOrError
function Agent.runEval(code)
    if type(code) ~= "string" or code == "" then
        return false, "Code must be a non-empty string"
    end

    local notReturned
    local commandFunction, errorMsg = loadstring("return " .. code)
    if errorMsg then
        notReturned = true
        commandFunction, errorMsg = loadstring(code)
    end

    if errorMsg then
        return false, errorMsg
    end

    if not commandFunction then
        return false, "Failed to load code"
    end

    applyEvalSandbox(commandFunction)

    local results = { pcall(commandFunction) }
    if not results[1] then
        return false, tostring(results[2])
    end

    if notReturned then
        return true, nil
    end

    return true, Agent.serializeResults(results)
end
