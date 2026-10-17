--- HTTP router (REST-style `/api/...` paths) dispatching to server/api.lua handlers.
---@class Agent
Agent = Agent or {}

---@param body any raw request body (expected JSON string)
---@return table|nil
---@return string|nil err
local function parseJsonBody(body)
    if type(body) ~= "string" or body == "" then
        return {}
    end
    local decoded = Agent.fromJson(body)
    if type(decoded) ~= "table" then
        return nil, "Invalid JSON body"
    end
    return decoded
end

---@param request AgentHttpRequest
---@param name string
---@param defaultValue any
---@return any
local function getQueryParam(request, name, defaultValue)
    if request.query and request.query[name] ~= nil then
        return request.query[name]
    end
    return defaultValue
end

---@return AgentJsonResponse
local function routePing()
    return Agent.okResponse(ping())
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeEval(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end

    local result = eval(body.code)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeEvalClient(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end

    local result = evalClient(body.code, body.player)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeEvalClientResult(request)
    local id = request.path:match("^/api/eval/client/(.+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end

    local result = evalClientResult(id)
    if not result.ok then
        return Agent.errorResponse(result.error, 404)
    end
    return Agent.okResponse(result)
end

---@param body table
---@param request AgentHttpRequest|nil
---@return AgentNearbyOptions
local function buildNearbyOptions(body, request)
    local options = {}

    if type(body) == "table" then
        options.type = body.type
        options.types = body.types
        options.limit = body.limit
        options.maxDistance = body.maxDistance
        options.perType = body.perType
        options.perTypeLimit = body.perTypeLimit
        options.excludeSelf = body.excludeSelf
        options.autoTrack = body.autoTrack
        options.trackSource = body.trackSource
    end

    if request and request.query then
        if request.query.type then
            options.type = request.query.type
        end
        if request.query.limit then
            options.limit = tonumber(request.query.limit)
        end
        if request.query.maxDistance then
            options.maxDistance = tonumber(request.query.maxDistance)
        end
        if request.query.perType then
            options.perType = request.query.perType == "true"
        end
        if request.query.perTypeLimit then
            options.perTypeLimit = tonumber(request.query.perTypeLimit)
        end
        if request.query.autoTrack then
            options.autoTrack = request.query.autoTrack == "true"
        end
    end

    return options
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeNearby(request)
    local body = {}
    if request.method == "POST" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    local playerName = body.player or getQueryParam(request, "player", nil)
    local options = buildNearbyOptions(body, request)
    local result = findNearby(playerName, options)

    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param body table
---@param request AgentHttpRequest|nil
---@return AgentVisibleOptions
local function buildVisibleOptions(body, request)
    local options = {}

    if type(body) == "table" then
        options.type = body.type
        options.types = body.types
        options.limit = body.limit
        options.maxDistance = body.maxDistance
        options.lineOfSight = body.lineOfSight
        options.includeOffScreen = body.includeOffScreen
        options.onlyVisible = body.onlyVisible
        options.debugLog = body.debugLog
        options.autoTrack = body.autoTrack
        options.trackSource = body.trackSource
    end

    if request and request.query then
        if request.query.type then
            options.type = request.query.type
        end
        if request.query.limit then
            options.limit = tonumber(request.query.limit)
        end
        if request.query.maxDistance then
            options.maxDistance = tonumber(request.query.maxDistance)
        end
        if request.query.lineOfSight then
            options.lineOfSight = request.query.lineOfSight == "true"
        end
        if request.query.includeOffScreen then
            options.includeOffScreen = request.query.includeOffScreen == "true"
        end
        if request.query.onlyVisible then
            options.onlyVisible = request.query.onlyVisible ~= "false"
        end
        if request.query.debugLog then
            options.debugLog = request.query.debugLog == "true"
        end
        if request.query.autoTrack then
            options.autoTrack = request.query.autoTrack == "true"
        end
    end

    return options
end

---@param body table
---@param request AgentHttpRequest|nil
---@return AgentLookOptions
local function buildLookTargetOptions(body, request)
    local options = {}

    if type(body) == "table" then
        options.type = body.type
        options.types = body.types
        options.maxDistance = body.maxDistance
        options.lineOfSight = body.lineOfSight
        options.debugLog = body.debugLog
        options.screenCenterMax = body.screenCenterMax
        options.maxCameraAngle = body.maxCameraAngle
        options.autoTrack = body.autoTrack
        options.trackSource = body.trackSource
    end

    if request and request.query then
        if request.query.type then
            options.type = request.query.type
        end
        if request.query.maxDistance then
            options.maxDistance = tonumber(request.query.maxDistance)
        end
        if request.query.lineOfSight then
            options.lineOfSight = request.query.lineOfSight == "true"
        end
        if request.query.debugLog then
            options.debugLog = request.query.debugLog == "true"
        end
        if request.query.screenCenterMax then
            options.screenCenterMax = tonumber(request.query.screenCenterMax)
        end
        if request.query.maxCameraAngle then
            options.maxCameraAngle = tonumber(request.query.maxCameraAngle)
        end
        if request.query.autoTrack then
            options.autoTrack = request.query.autoTrack == "true"
        end
    end

    return options
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeElementTrack(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end

    local result = elementTrack(body.player, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeElementGet(request)
    local id = request.path:match("^/api/elements/([^/]+)$")
    if not id or id == "" then
        return Agent.errorResponse("Element id required", 400)
    end

    local options = {}
    if request.query then
        options.player = request.query.player
        options.refresh = request.query.refresh ~= "false"
        options.sync = request.query.sync ~= "false"
    end

    local result = elementGet(id, options)
    if not result.ok then
        local status = result.error == "notFound" and 404 or 400
        return Agent.errorResponse(result.error, status)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeElementList(request)
    local options = {}
    if request.method == "POST" then
        local body, err = parseJsonBody(request.body)
        if not body then
            return Agent.errorResponse(err, 400)
        end
        options = body
    end

    if request.query then
        options.side = options.side or request.query.side
        options.owner = options.owner or request.query.player or request.query.owner
        options.elementType = options.elementType or request.query.elementType
        options.localOnly = options.localOnly
        if request.query.localOnly ~= nil then
            options.localOnly = request.query.localOnly == "true"
        end
        if request.query.syncClient ~= nil then
            options.syncClient = request.query.syncClient == "true"
        end
        options.player = options.player or request.query.player
    end

    local result = elementList(options)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeElementRelease(request)
    local id = request.path:match("^/api/elements/([^/]+)$")
    if not id or id == "" then
        return Agent.errorResponse("Element id required", 400)
    end

    local options = {}
    if request.method == "POST" or request.method == "DELETE" then
        local body = {}
        if request.body and request.body ~= "" then
            local parsed, err = parseJsonBody(request.body)
            if not parsed then
                return Agent.errorResponse(err, 400)
            end
            body = parsed
        end
        options.player = body.player
    end
    if request.query and request.query.player then
        options.player = request.query.player
    end

    local result = elementRelease(id, options)
    if not result.ok then
        return Agent.errorResponse(result.error, 404)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeElementModify(request)
    local id = request.path:match("^/api/elements/([^/]+)/modify$")
    if not id or id == "" then
        return Agent.errorResponse("Element id required", 400)
    end

    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end

    local result = elementModify(id, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeElementResolve(request)
    local id = request.path:match("^/api/elements/([^/]+)/resolve$")
    if not id or id == "" then
        return Agent.errorResponse("Element id required", 400)
    end

    local options = {}
    if request.query and request.query.player then
        options.player = request.query.player
    end

    local result = elementResolve(id, options)
    if not result.ok then
        local status = result.error == "notFound" and 404 or 400
        return Agent.errorResponse(result.error, status)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeElementWalk(request)
    local body = {}
    if request.method == "POST" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    if request.query then
        if request.query.mode then body.mode = request.query.mode end
        if request.query.rootsOnly then body.rootsOnly = request.query.rootsOnly == "true" end
        if request.query.resourceName then body.resourceName = request.query.resourceName end
        if request.query.maxDepth then body.maxDepth = tonumber(request.query.maxDepth) end
        if request.query.maxNodes then body.maxNodes = tonumber(request.query.maxNodes) end
        if request.query.flat then body.flat = request.query.flat == "true" end
        if request.query.track then body.track = request.query.track == "true" end
        if request.query.autoTrack then body.autoTrack = request.query.autoTrack == "true" end
        if request.query.resourcesOnly then body.resourcesOnly = request.query.resourcesOnly == "true" end
        if request.query.resourceState then body.resourceState = request.query.resourceState == "true" end
        if request.query.side then body.side = request.query.side end
        if request.query.player then body.player = request.query.player end
        if request.query.childType then body.childType = request.query.childType end
    end

    local result = elementWalk(body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeGuiScan(request)
    local body = {}
    if request.method == "POST" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    if request.query then
        if request.query.player then body.player = request.query.player end
        if request.query.windowTitle then body.windowTitle = request.query.windowTitle end
        if request.query.title then body.windowTitle = request.query.title end
        if request.query.search then body.windowTitle = request.query.search end
        if request.query.openOnly then body.openOnly = request.query.openOnly == "true" end
        if request.query.visibleOnly then body.visibleOnly = request.query.visibleOnly == "true" end
        if request.query.maxDepth then body.maxDepth = tonumber(request.query.maxDepth) end
        if request.query.maxNodes then body.maxNodes = tonumber(request.query.maxNodes) end
        if request.query.flat then body.flat = request.query.flat == "true" end
        if request.query.trees then body.trees = request.query.trees == "true" end
        if request.query.autoTrack then body.autoTrack = request.query.autoTrack == "true" end
        if request.query.includeAllElements then body.includeAllElements = request.query.includeAllElements == "true" end
    end

    local result = guiScan(body.player, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeGuiScanResult(request)
    local id = request.path:match("^/api/gui/(.+)$")
    if not id or id == "" or id == "scan" then
        return Agent.errorResponse("Request id required", 400)
    end

    local result = guiScanResult(id)
    if not result.ok and result.error == "Request not found" then
        return Agent.errorResponse(result.error, 404)
    end
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeScreenCapture(request)
    local body = {}
    if request.method == "POST" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    if request.query then
        if request.query.player then body.player = request.query.player end
        if request.query.serial then body.serial = request.query.serial end
        if request.query.width then body.width = tonumber(request.query.width) end
        if request.query.height then body.height = tonumber(request.query.height) end
        if request.query.quality then body.quality = tonumber(request.query.quality) end
        if request.query.maxBandwidth then body.maxBandwidth = tonumber(request.query.maxBandwidth) end
    end

    local result = screenCapture(body.player, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeScreenCaptureResult(request)
    local id = request.path:match("^/api/screen/(.+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end

    local result = screenCaptureResult(id)
    if not result.ok and result.error == "Request not found" then
        return Agent.errorResponse(result.error, 404)
    end
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeDebugLogList(request)
    local body = {}
    if request.method == "POST" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    if request.query then
        if request.query.player then body.player = request.query.player end
        if request.query.side then body.side = request.query.side end
        if request.query.minLevel then body.minLevel = tonumber(request.query.minLevel) end
        if request.query.limit then body.limit = tonumber(request.query.limit) end
        if request.query.sinceSeq then body.sinceSeq = tonumber(request.query.sinceSeq) end
        if request.query.sinceTick then body.sinceTick = tonumber(request.query.sinceTick) end
        if request.query.dedupe then body.dedupe = request.query.dedupe == "true" end
    end

    local result = debugLogList(body.player, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeDebugLogResult(request)
    local id = request.path:match("^/api/debug/(.+)$")
    if not id or id == "" or id == "logs" or id == "events" then
        return Agent.errorResponse("Request id required", 400)
    end

    local result
    if id:match("^ev%-") then
        result = debugEventsResult(id)
    elseif id:match("^hp%-") then
        result = healthResult(id)
    else
        result = debugLogResult(id)
    end
    if not result.ok and result.error == "Request not found" then
        return Agent.errorResponse(result.error, 404)
    end
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeDebugEvents(request)
    local body = {}
    if request.body and request.body ~= "" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    if request.query then
        if request.query.player then body.player = request.query.player end
        if request.query.action then body.action = request.query.action end
        if request.query.side then body.side = request.query.side end
        if request.query.event then body.event = request.query.event end
        if request.query.eventName then body.eventName = request.query.eventName end
        if request.query.hookType then body.hookType = request.query.hookType end
        if request.query.resource then body.resource = request.query.resource end
        if request.query.limit then body.limit = tonumber(request.query.limit) end
        if request.query.sinceSeq then body.sinceSeq = tonumber(request.query.sinceSeq) end
        if request.query.sinceTick then body.sinceTick = tonumber(request.query.sinceTick) end
        if request.query.dedupe then body.dedupe = request.query.dedupe == "true" end
    end

    local result = debugEvents(body.player, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeHealthGet(request)
    local body = {}
    if request.body and request.body ~= "" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    if request.query then
        if request.query.player then body.player = request.query.player end
        if request.query.side then body.side = request.query.side end
        if request.query.networkUsage then body.networkUsage = request.query.networkUsage == "true" end
        if request.query.networkUsageLimit then body.networkUsageLimit = tonumber(request.query.networkUsageLimit) end
        if request.query.performanceCategory then body.performanceCategory = request.query.performanceCategory end
        if request.query.performanceOptions then body.performanceOptions = request.query.performanceOptions end
        if request.query.performanceFilter then body.performanceFilter = request.query.performanceFilter end
        if request.query.listPerformanceCategories then
            body.listPerformanceCategories = request.query.listPerformanceCategories == "true"
        end
    end

    local result = healthGet(body.player, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeHealthResult(request)
    local id = request.path:match("^/api/health/(.+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end

    local result = healthResult(id)
    if not result.ok and result.error == "Request not found" then
        return Agent.errorResponse(result.error, 404)
    end
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeFindVisible(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end

    local playerName = body.player
    local options = buildVisibleOptions(body, request)
    local result = findVisible(playerName, options)

    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeFindVisibleResult(request)
    local id = request.path:match("^/api/visible/(.+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end

    local result = findVisibleResult(id)
    if not result.ok and result.error == "Request not found" then
        return Agent.errorResponse(result.error, 404)
    end
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeFindLookTarget(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end

    local playerName = body.player
    local options = buildLookTargetOptions(body, request)
    local result = findLookTarget(playerName, options)

    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeFindLookTargetResult(request)
    local id = request.path:match("^/api/look/(.+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end

    local result = findLookTargetResult(id)
    if not result.ok and result.error == "Request not found" then
        return Agent.errorResponse(result.error, 404)
    end
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeMemoryGet(request)
    local key = request.path:match("^/api/memory/(.+)$")
    if not key or key == "" then
        return Agent.errorResponse("Key required", 400)
    end

    local result = memoryGet(key)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeMemorySet(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end
    if type(body.key) ~= "string" or body.key == "" then
        return Agent.errorResponse("Key required", 400)
    end

    local result = memorySet(body.key, body.value)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeMemoryDelete(request)
    local key = request.path:match("^/api/memory/(.+)$")
    if not key or key == "" then
        return Agent.errorResponse("Key required", 400)
    end

    local result = memoryDelete(key)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeMemoryList(request)
    local prefix = getQueryParam(request, "prefix", "")
    local result = memoryList(prefix)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeCall(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end

    local result = callExport(body.resource, body["function"], body.args)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param action "start"|"stop"|"restart"
---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeResourceAction(action, request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end

    if type(body.resource) ~= "string" or body.resource == "" then
        return Agent.errorResponse("Resource name required", 400)
    end

    local result
    if action == "start" then
        result = resourceStart(body.resource)
    elseif action == "stop" then
        result = resourceStop(body.resource)
    elseif action == "restart" then
        result = resourceRestart(body.resource)
    else
        return Agent.errorResponse("Unknown action", 400)
    end

    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeResourceRefresh(request)
    local body = {}
    if request.body and request.body ~= "" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    local result = resourceRefresh(body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end

    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeResourceSearch(request)
    local body = {}
    if request.body and request.body ~= "" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return Agent.errorResponse(err, 400)
        end
        body = parsed
    end

    if request.query then
        if request.query.query then body.query = request.query.query end
        if request.query.q then body.q = request.query.q end
        if request.query.name then body.name = request.query.name end
        if request.query.state then body.state = request.query.state end
        if request.query.limit then body.limit = tonumber(request.query.limit) end
        if request.query.exact then body.exact = request.query.exact == "true" end
    end

    return Agent.okResponse(resourceSearch(body))
end

---@return AgentJsonResponse
local function routeState()
    return Agent.okResponse(getServerState())
end

---@param path any request path (expected string)
---@return string|nil
local function normalizeResourcePath(path)
    if type(path) ~= "string" or path == "" or path == "/" then
        return nil
    end

    local relative = path:gsub("^/", "")
    if relative == "" or relative:find("..", 1, true) then
        return nil
    end

    return relative
end

---@param path any request path (expected string)
---@return AgentJsonResponse|nil
local function serveResourceFile(path)
    local relative = normalizeResourcePath(path)
    if not relative then
        return nil
    end

    local resourcePath = ":" .. Agent.RESOURCE_NAME .. "/" .. relative
    if not fileExists(resourcePath) then
        return nil
    end

    local handle = fileOpen(resourcePath, true)
    if not handle then
        return nil
    end

    local size = fileGetSize(handle)
    if not size or size <= 0 then
        fileClose(handle)
        return nil
    end

    local content = fileRead(handle, size)
    fileClose(handle)
    if not content then
        return nil
    end

    local contentType = "application/octet-stream"
    if relative:match("%.lua$") then
        contentType = "text/plain; charset=utf-8"
    end

    return {
        status = 200,
        headers = {
            ["content-type"] = contentType,
        },
        body = content,
    }
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeModelReplaceTest(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end
    local result = modelReplaceTest(body.player, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeModelReplaceTestResult(request)
    local id = request.path:match("^/api/models/test/(.+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end
    local result = modelReplaceTestResult(id)
    if not result.ok and result.error == "Request not found" then
        return Agent.errorResponse(result.error, 404)
    end
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeModelRestore(request)
    local body, err = parseJsonBody(request.body)
    if not body then
        return Agent.errorResponse(err, 400)
    end
    local result = modelRestore(body.player, body)
    if not result.ok then
        return Agent.errorResponse(result.error, 400)
    end
    return Agent.okResponse(result)
end

---@param result table
---@return AgentJsonResponse
local function routeBoundingPayload(result)
    if result.ok then
        return Agent.okResponse(result)
    end
    if result.error == "Request not found" then
        return Agent.errorResponse(result.error, 404)
    end
    if result.error == "notStreamedIn" or result.default or result.custom then
        return Agent.jsonResponse(result, 409)
    end
    return Agent.errorResponse(result.error or "Bounding request failed", 400)
end

---@param request AgentHttpRequest
---@return table
local function boundingBody(request)
    local body = {}
    if request.body and request.body ~= "" then
        local parsed, err = parseJsonBody(request.body)
        if not parsed then
            return nil, err
        end
        body = parsed
    end
    if request.query then
        if request.query.player then body.player = request.query.player end
        if request.query.serial then body.serial = request.query.serial end
        if request.query.action then body.action = request.query.action end
        if request.query.id then body.id = request.query.id end
        if request.query.model then body.model = tonumber(request.query.model) or request.query.model end
        if request.query.elementType then body.elementType = request.query.elementType end
        if request.query.agentId then body.agentId = request.query.agentId end
        if request.query.mtaHandle then body.mtaHandle = request.query.mtaHandle end
        if request.query.force then body.force = request.query.force end
        if request.query.nearby then body.nearby = request.query.nearby end
        if request.query.batch then body.batch = tonumber(request.query.batch) end
        if request.query.maxDistance then body.maxDistance = tonumber(request.query.maxDistance) end
        if request.query.limit then body.limit = tonumber(request.query.limit) end
    end
    return body
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeBoundingScan(request)
    local body, err = boundingBody(request)
    if not body then
        return Agent.errorResponse(err, 400)
    end
    return routeBoundingPayload(boundingScan(body.player, body))
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeBoundingScanResult(request)
    local id = request.path:match("^/api/bounding/scan/([^/]+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end
    return routeBoundingPayload(boundingScanResult(id))
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeBoundingFetch(request)
    local body, err = boundingBody(request)
    if not body then
        return Agent.errorResponse(err, 400)
    end
    return routeBoundingPayload(boundingFetch(body.player, body))
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeBoundingFetchResult(request)
    local id = request.path:match("^/api/bounding/fetch/([^/]+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end
    return routeBoundingPayload(boundingFetchResult(id))
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeBoundingDraw(request)
    local body, err = boundingBody(request)
    if not body then
        return Agent.errorResponse(err, 400)
    end
    return routeBoundingPayload(boundingDraw(body.player, body))
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeBoundingDrawResult(request)
    local id = request.path:match("^/api/bounding/draw/([^/]+)$")
    if not id or id == "" then
        return Agent.errorResponse("Request id required", 400)
    end
    return routeBoundingPayload(boundingDrawResult(id))
end

---@param request AgentHttpRequest
---@return AgentJsonResponse
local function routeBoundingGet(request)
    local body, err = boundingBody(request)
    if not body then
        return Agent.errorResponse(err, 400)
    end
    return routeBoundingPayload(boundingGet(body.player, body))
end

---@param request AgentHttpRequest
---@return AgentJsonResponse|nil
function httpRouter(request)
    local method = request.method or "GET"
    local path = request.path or "/"

    if path == "/api/ping" and (method == "GET" or method == "POST") then
        return routePing()
    end

    if method == "POST" and path == "/api/eval" then
        return routeEval(request)
    end

    if method == "POST" and path == "/api/eval/client" then
        return routeEvalClient(request)
    end

    if method == "GET" and path:match("^/api/eval/client/.+$") then
        return routeEvalClientResult(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/nearby" then
        return routeNearby(request)
    end

    if method == "POST" and path == "/api/visible" then
        return routeFindVisible(request)
    end

    if method == "GET" and path:match("^/api/visible/.+$") then
        return routeFindVisibleResult(request)
    end

    if method == "POST" and path == "/api/look" then
        return routeFindLookTarget(request)
    end

    if method == "GET" and path:match("^/api/look/.+$") then
        return routeFindLookTargetResult(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/screen" then
        return routeScreenCapture(request)
    end

    if method == "GET" and path:match("^/api/screen/[^/]+$") then
        return routeScreenCaptureResult(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/gui/scan" then
        return routeGuiScan(request)
    end

    if method == "GET" and path:match("^/api/gui/[^/]+$") and path ~= "/api/gui/scan" then
        return routeGuiScanResult(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/debug/logs" then
        return routeDebugLogList(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/debug/events" then
        return routeDebugEvents(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/health" then
        return routeHealthGet(request)
    end

    if method == "GET" and path:match("^/api/health/[^/]+$") and path ~= "/api/health" then
        return routeHealthResult(request)
    end

    if method == "GET" and path:match("^/api/debug/[^/]+$") and path ~= "/api/debug/logs" and path ~= "/api/debug/events" then
        return routeDebugLogResult(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/elements/walk" then
        return routeElementWalk(request)
    end

    if method == "POST" and path == "/api/elements/track" then
        return routeElementTrack(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/elements" then
        return routeElementList(request)
    end

    if method == "GET" and path:match("^/api/elements/[^/]+/resolve$") then
        return routeElementResolve(request)
    end

    if method == "POST" and path:match("^/api/elements/[^/]+/modify$") then
        return routeElementModify(request)
    end

    if method == "DELETE" and path:match("^/api/elements/[^/]+$") then
        return routeElementRelease(request)
    end

    if method == "GET" and path:match("^/api/elements/[^/]+$") then
        return routeElementGet(request)
    end

    if method == "GET" and path == "/api/memory" then
        return routeMemoryList(request)
    end

    if method == "POST" and path == "/api/memory" then
        return routeMemorySet(request)
    end

    if method == "GET" and path:match("^/api/memory/.+$") then
        return routeMemoryGet(request)
    end

    if method == "DELETE" and path:match("^/api/memory/.+$") then
        return routeMemoryDelete(request)
    end

    if method == "POST" and path == "/api/call" then
        return routeCall(request)
    end

    if method == "GET" and path == "/api/state" then
        return routeState()
    end

    if (method == "GET" or method == "POST") and path == "/api/resources/search" then
        return routeResourceSearch(request)
    end

    if method == "POST" and path == "/api/resources/start" then
        return routeResourceAction("start", request)
    end

    if method == "POST" and path == "/api/resources/stop" then
        return routeResourceAction("stop", request)
    end

    if method == "POST" and path == "/api/resources/restart" then
        return routeResourceAction("restart", request)
    end

    if method == "POST" and path == "/api/resources/refresh" then
        return routeResourceRefresh(request)
    end

    if method == "POST" and path == "/api/models/test" then
        return routeModelReplaceTest(request)
    end

    if method == "GET" and path:match("^/api/models/test/.+$") then
        return routeModelReplaceTestResult(request)
    end

    if method == "POST" and path == "/api/models/restore" then
        return routeModelRestore(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/bounding/scan" then
        return routeBoundingScan(request)
    end

    if method == "GET" and path:match("^/api/bounding/scan/[^/]+$") then
        return routeBoundingScanResult(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/bounding/fetch" then
        return routeBoundingFetch(request)
    end

    if method == "GET" and path:match("^/api/bounding/fetch/[^/]+$") then
        return routeBoundingFetchResult(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/bounding/draw" then
        return routeBoundingDraw(request)
    end

    if method == "GET" and path:match("^/api/bounding/draw/[^/]+$") then
        return routeBoundingDrawResult(request)
    end

    if (method == "GET" or method == "POST") and path == "/api/bounding" then
        return routeBoundingGet(request)
    end

    if path:match("^/api/") then
        return Agent.errorResponse("Not found", 404)
    end

    if method == "GET" then
        return serveResourceFile(path)
    end

    return nil
end
