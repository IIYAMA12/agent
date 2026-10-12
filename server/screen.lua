--- Async player screen capture via takePlayerScreenShot / onPlayerScreenShot.
---@class Agent
Agent = Agent or {}

Agent.SCREEN_CAPTURE_TIMEOUT_MS = 20000
Agent.SCREEN_CAPTURE_MAX_FILES = 30
Agent.screenCaptureRequests = Agent.screenCaptureRequests or {}
Agent.screenCaptureNextId = Agent.screenCaptureNextId or 0

local CAPTURE_HISTORY = "captures/.history"

---@return string[]
local function loadCaptureHistory()
    if not fileExists(CAPTURE_HISTORY) then
        return {}
    end

    local handle = fileOpen(CAPTURE_HISTORY, true)
    if not handle then
        return {}
    end

    local size = fileGetSize(handle) or 0
    local raw = ""
    if size > 0 then
        raw = fileRead(handle, size) or ""
    end
    fileClose(handle)

    local list = {}
    for line in string.gmatch(raw, "[^\r\n]+") do
        if line:match("^captures/[%w_%-]+%.jpg$") then
            list[#list + 1] = line
        end
    end
    return list
end

---@param list string[]
local function saveCaptureHistory(list)
    if fileExists(CAPTURE_HISTORY) then
        fileDelete(CAPTURE_HISTORY)
    end

    local handle = fileCreate(CAPTURE_HISTORY)
    if not handle then
        return
    end

    if #list > 0 then
        fileWrite(handle, table.concat(list, "\n") .. "\n")
    end
    fileClose(handle)
end

---@param relative string
local function rememberCapture(relative)
    local list = loadCaptureHistory()
    local nextList = {}
    for i = 1, #list do
        if list[i] ~= relative then
            nextList[#nextList + 1] = list[i]
        end
    end
    nextList[#nextList + 1] = relative

    while #nextList > Agent.SCREEN_CAPTURE_MAX_FILES do
        local oldest = table.remove(nextList, 1)
        if oldest and fileExists(oldest) then
            fileDelete(oldest)
        end
    end

    saveCaptureHistory(nextList)
end

---@param playerName string
---@param imageData string
---@return string|nil relativePath
local function writeCaptureFile(playerName, imageData)
    local time = getRealTime()
    local safeName = tostring(playerName or "player"):gsub("[^%w_%-]", "_"):sub(1, 32)
    if safeName == "" then
        safeName = "player"
    end
    local filename = string.format(
        "%04d-%02d-%02d_%02d%02d%02d_%s.jpg",
        time.year + 1900,
        time.month + 1,
        time.monthday,
        time.hour,
        time.minute,
        time.second,
        safeName
    )
    local relative = "captures/" .. filename
    if fileExists(relative) then
        fileDelete(relative)
    end
    local handle = fileCreate(relative)
    if not handle then
        return nil
    end
    fileWrite(handle, imageData)
    fileClose(handle)
    rememberCapture(relative)
    return relative
end

local STATUS_ERRORS = {
    disabled = "Player has disabled screen uploads",
    minimized = "Player has the game minimized",
    error = "Screen capture failed",
}

---@param value any
---@param fallback integer
---@param minValue integer
---@param maxValue integer
---@return integer
local function clampInt(value, fallback, minValue, maxValue)
    local number = tonumber(value)
    if not number then
        return fallback
    end
    number = math.floor(number)
    if number < minValue then
        return minValue
    end
    if number > maxValue then
        return maxValue
    end
    return number
end

---@param request table
---@param message string
local function failRequest(request, message)
    if request.timer and isTimer(request.timer) then
        killTimer(request.timer)
        request.timer = nil
    end
    if request.status ~= "pending" then
        return
    end
    request.status = "complete"
    request.error = message
end

---@param playerName string|nil
---@param options table|nil
---@return string|nil id, string|nil error
function Agent.startScreenCapture(playerName, options)
    options = type(options) == "table" and options or {}

    if hasObjectPermissionTo and not hasObjectPermissionTo(getThisResource(), "function.takePlayerScreenShot", true) then
        return nil, "Missing right function.takePlayerScreenShot — run: aclrequest allow agent function.takePlayerScreenShot"
    end

    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return nil, err
    end

    local width = clampInt(options.width, 1920, 16, 1920)
    local height = clampInt(options.height, 1080, 16, 1920)
    local quality = clampInt(options.quality, 90, 1, 100)
    local maxBandwidth = clampInt(options.maxBandwidth, 1000000, 1000, 2000000)

    Agent.screenCaptureNextId = Agent.screenCaptureNextId + 1
    local id = "sc-" .. getTickCount() .. "-" .. Agent.screenCaptureNextId
    local request = {
        id = id,
        status = "pending",
        player = getPlayerName(player),
        width = width,
        height = height,
        quality = quality,
        createdAt = getTickCount(),
        result = nil,
        error = nil,
        timer = nil,
    }
    Agent.screenCaptureRequests[id] = request

    request.timer = setTimer(function()
        failRequest(request, "Screen capture timed out")
    end, Agent.SCREEN_CAPTURE_TIMEOUT_MS, 1)

    local started = takePlayerScreenShot(player, width, height, id, quality, maxBandwidth)
    if not started then
        Agent.screenCaptureRequests[id] = nil
        if request.timer and isTimer(request.timer) then
            killTimer(request.timer)
        end
        return nil, "takePlayerScreenShot failed (check function.takePlayerScreenShot ACL right and player arguments)"
    end

    return id
end

---@param id string
---@return table
function Agent.getScreenCaptureResult(id)
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end

    local request = Agent.screenCaptureRequests[id]
    if not request then
        return { ok = false, error = "Request not found" }
    end

    if request.status == "pending" then
        return {
            ok = true,
            id = id,
            status = "pending",
            player = request.player,
        }
    end

    if request.error then
        return {
            ok = false,
            id = id,
            status = "complete",
            error = request.error,
            player = request.player,
        }
    end

    return {
        ok = true,
        id = id,
        status = "complete",
        player = request.player,
        result = request.result,
    }
end

addEventHandler("onPlayerScreenShot", root, function(theResource, status, imageData, _timestamp, tag)
    if theResource ~= getThisResource() then
        return
    end
    if type(tag) ~= "string" or tag == "" then
        return
    end

    local request = Agent.screenCaptureRequests[tag]
    if not request or request.status ~= "pending" then
        return
    end

    if status ~= "ok" then
        failRequest(request, STATUS_ERRORS[status] or ("Screen capture failed (" .. tostring(status) .. ")"))
        return
    end

    if type(imageData) ~= "string" or imageData == "" then
        failRequest(request, "Screen capture returned no image")
        return
    end

    local relative = writeCaptureFile(request.player, imageData)
    if not relative then
        failRequest(request, "Failed to save screen capture")
        return
    end

    if request.timer and isTimer(request.timer) then
        killTimer(request.timer)
        request.timer = nil
    end

    request.status = "complete"
    request.result = {
        player = request.player,
        width = request.width,
        height = request.height,
        quality = request.quality,
        bytes = #imageData,
        file = relative,
    }
end)

setTimer(function()
    local now = getTickCount()
    local ttl = 10 * 60 * 1000
    for requestId, request in pairs(Agent.screenCaptureRequests) do
        if now - request.createdAt > ttl then
            if request.timer and isTimer(request.timer) then
                killTimer(request.timer)
            end
            Agent.screenCaptureRequests[requestId] = nil
        end
    end
end, 60000, 0)
