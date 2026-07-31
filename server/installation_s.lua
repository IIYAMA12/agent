--- Auto-installs the agent ACL group, ACL, and HTTP user grant on first resource start.
--- After success: denies install-only aclrequests, scrubs dangerous ACL APIs from `_G`, restarts.
--- On later starts: scrubs the same dangerous globals again (MTA rebinds them on resource start).
--- HTTP username comes from node/.env (MTA_USER). Password (MTA_PASS) is for Node/middleware only.

local groupName = "agent"
local aclName = "Agent"
local thisResource = getThisResource()
local resourceName = getResourceName(thisResource)
local lockInstallPath = ":" .. resourceName .. "/data/lock-install"
local envPath = ":" .. resourceName .. "/node/.env"
local envExamplePath = ":" .. resourceName .. "/node/.env.example"

local PLACEHOLDER_USER = "your_http_user"
local PLACEHOLDER_PASS = "your_http_password"

--- Rights required only for first-run ACL bootstrap (revoked after success).
local installRights = {
    "function.aclCreateGroup",
    "function.aclCreate",
    "function.aclGroupAddACL",
    "function.aclSave",
    "function.aclGroupAddObject",
    "function.aclSetRight",
    "function.updateResourceACLRequest",
    "function.restartResource",
    "general.ModifyOtherObjects",
}

--- Install-only rights to deny via updateResourceACLRequest (updateResourceACLRequest last).
local installOnlyRightsToRevoke = {
    "function.aclCreateGroup",
    "function.aclCreate",
    "function.aclSetRight",
    "function.aclGroupAddACL",
    "function.aclGroupAddObject",
    "function.aclSave",
    "general.ModifyOtherObjects",
    "function.updateResourceACLRequest",
}

--- ACL mutation APIs cleared from `_G` after install / on every later start.
--- Keep loadstring + start/stop/restartResource (needed at runtime).
local dangerousGlobals = {
    "aclCreate",
    "aclCreateGroup",
    "aclDestroy",
    "aclDestroyGroup",
    "aclSetRight",
    "aclRemoveRight",
    "aclSave",
    "aclReload",
    "aclGroupAddACL",
    "aclGroupRemoveACL",
    "aclGroupAddObject",
    "aclGroupRemoveObject",
    "updateResourceACLRequest",
}

---@return nil
local function scrubDangerousGlobals()
    for i = 1, #dangerousGlobals do
        local name = dangerousGlobals[i]
        if _G[name] ~= nil then
            _G[name] = nil
        end
    end
end

---@param destPath string
---@param content string
---@return boolean
local function writeTextFile(destPath, content)
    if fileExists(destPath) then
        fileDelete(destPath)
    end
    local handle = fileCreate(destPath)
    if not handle then
        return false
    end
    fileWrite(handle, content)
    fileClose(handle)
    return true
end

--- Create missing node/.env from .env.example.
---@return nil
local function ensureEnvPlaceholder()
    if fileExists(envPath) then
        return
    end

    local content = nil
    if fileExists(envExamplePath) then
        local handle = fileOpen(envExamplePath, true)
        if handle then
            local size = fileGetSize(handle)
            content = size > 0 and fileRead(handle, size) or ""
            fileClose(handle)
        end
    end
    if not content or content == "" then
        content = "MTA_USER=your_http_user\nMTA_PASS=your_http_password\n"
    end
    if writeTextFile(envPath, content) then
        outputDebugString("[agent] Created node/.env placeholder — set MTA_USER / MTA_PASS (addaccount first)", 0)
    else
        outputDebugString("[agent] Failed to create node/.env placeholder", 2)
    end
end

---@param content string
---@param into table<string, string>
---@return nil
local function mergeEnvContent(content, into)
    for line in string.gmatch(content, "[^\r\n]+") do
        local trimmed = string.match(line, "^%s*(.-)%s*$") or ""
        if trimmed ~= "" and not string.find(trimmed, "^#") then
            local key, value = string.match(trimmed, "^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.*)$")
            if key then
                value = value or ""
                value = string.match(value, "^%s*(.-)%s*$") or value
                local q = string.sub(value, 1, 1)
                if (q == '"' or q == "'") and string.sub(value, -1) == q and #value >= 2 then
                    value = string.sub(value, 2, -2)
                    if q == '"' then
                        value = string.gsub(value, '\\"', '"')
                        value = string.gsub(value, "\\\\", "\\")
                    end
                end
                into[key] = value
            end
        end
    end
end

---@return table<string, string>
local function loadDotEnv()
    local env = {}
    if fileExists(envPath) then
        local handle = fileOpen(envPath, true)
        if handle then
            local size = fileGetSize(handle)
            local content = size > 0 and fileRead(handle, size) or ""
            fileClose(handle)
            if content and content ~= "" then
                mergeEnvContent(content, env)
            end
        end
    end
    return env
end

--- ACL install only needs the username; password must still be set for middleware.
---@return string|nil httpUser
---@return string|nil errorMessage
local function getHttpUser()
    local env = loadDotEnv()
    local user = env.MTA_USER
    local pass = env.MTA_PASS
    if type(user) == "string" then
        user = string.match(user, "^%s*(.-)%s*$") or user
    end
    if type(pass) == "string" then
        pass = string.match(pass, "^%s*(.-)%s*$") or pass
    end
    if not user or user == "" or user == PLACEHOLDER_USER then
        return nil,
            "Set MTA_USER in node/.env (auto-created from .env.example if missing). Create the account with addaccount first."
    end
    if not pass or pass == "" or pass == PLACEHOLDER_PASS then
        return nil,
            "Set MTA_PASS in node/.env to the account password (addaccount). Quote values that contain #."
    end
    return user
end

---@return boolean allDenied
local function revokeInstallOnlyRights()
    local allDenied = true
    local updateFn = updateResourceACLRequest

    if type(updateFn) ~= "function" then
        outputDebugString("[agent] updateResourceACLRequest unavailable; cannot auto-deny install rights", 2)
        return false
    end

    for i = 1, #installOnlyRightsToRevoke do
        local rightName = installOnlyRightsToRevoke[i]
        local ok = updateFn(thisResource, rightName, false, "agent-install")
        if not ok then
            allDenied = false
            outputDebugString("[agent] Failed to deny aclrequest: " .. rightName, 2)
        end
    end

    return allDenied
end

---@return nil
local function writeLockInstall()
    local lockFile = fileCreate(lockInstallPath)
    if lockFile then
        fileWrite(lockFile, "installed")
        fileClose(lockFile)
    else
        outputDebugString("[agent] Failed to write data/lock-install", 2)
    end
end

---@return nil
local function finishInstallAndRestart()
    local deniedOk = revokeInstallOnlyRights()
    writeLockInstall()
    scrubDangerousGlobals()

    if deniedOk then
        outputDebugString("[agent] ACL installation completed; install-only rights denied. Restarting resource...", 0)
    else
        outputDebugString(
            "[agent] ACL installation completed, but some install-only rights could not be denied. "
                .. "Review with: aclrequest list "
                .. resourceName
                .. " — then restarting resource...",
            2
        )
    end

    local restartFn = restartResource
    if type(restartFn) ~= "function" then
        outputDebugString("[agent] restartResource unavailable after scrub; restart agent manually", 2)
        return
    end

    restartFn(thisResource)
end

ensureEnvPlaceholder()

if fileExists(lockInstallPath) then
    outputDebugString("[" .. resourceName .. "] ACL installation already completed.", 0)
    scrubDangerousGlobals()
else
    if not hasAccessToRights(installRights) then
        outputDebugString(
            "Missing rights for ACL installation. Run: /aclrequest allow " .. resourceName .. " all",
            2
        )
    else
        setTimer(function()
            local httpUser, userErr = getHttpUser()
            if not httpUser then
                outputDebugString("[agent] ACL install aborted: " .. tostring(userErr), 2)
                return
            end

            local agentGroup = aclGetGroup(groupName)
            if not agentGroup then
                agentGroup = aclCreateGroup(groupName)
            end

            if not agentGroup then
                outputDebugString("[agent] Failed to create ACL group", 2)
                return
            end

            local aclChanged = false
            local theAcl = aclGet(aclName)
            if not theAcl then
                theAcl = aclCreate(aclName)
                aclSetRight(theAcl, "resource." .. resourceName .. ".http", true)
                aclGroupAddACL(agentGroup, theAcl)
                aclChanged = true
            else
                if not isObjectInACLGroup("resource." .. resourceName, agentGroup) then
                    aclGroupAddACL(agentGroup, theAcl)
                    aclChanged = true
                end
            end

            local userObject = "user." .. httpUser
            if not isObjectInACLGroup(userObject, agentGroup) then
                if aclGroupAddObject(agentGroup, userObject) then
                    aclChanged = true
                    outputDebugString("[agent] Added " .. httpUser .. " to agent ACL group", 0)
                else
                    outputDebugString("[agent] Failed to add " .. httpUser .. " to agent ACL group", 2)
                end
            end

            if aclChanged then
                aclSave()
            end

            finishInstallAndRestart()
        end, 2000, 1)
    end
end
