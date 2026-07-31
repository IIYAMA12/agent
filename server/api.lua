--- HTTP-exported API functions (server-side "call"/"api" targets for the agent resource).
---@class Agent
Agent = Agent or {}

---@return { ok: boolean, resource: string, time: integer }
function ping()
    return {
        ok = true,
        resource = Agent.RESOURCE_NAME,
        time = getRealTime().timestamp,
    }
end

---@param code any code to execute via loadstring (expected string)
---@return table
function eval(code)
    Agent.logHttp("eval", code)

    local success, result = Agent.runEval(code)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, result = result }
end

---@param code any code to execute on the client (expected string)
---@param playerName string|nil
---@param options table|nil
---@return table
function evalClient(code, playerName, options)
    Agent.logHttp("evalClient", (playerName or "*") .. " " .. tostring(code))

    if type(options) ~= "table" then
        options = {}
    end

    local id, err = Agent.startClientEval(code, playerName, options)
    if not id then
        return { ok = false, error = err }
    end

    return { ok = true, id = id, status = "pending" }
end

---@param id any request id (expected string)
---@return table
function evalClientResult(id)
    Agent.logHttp("evalClientResult", tostring(id))
    return Agent.getClientEvalResult(id)
end

---@param playerName string|nil
---@param options AgentNearbyOptions|nil
---@return table
function findNearby(playerName, options)
    Agent.logHttp("findNearby", (playerName or "*") .. " " .. tostring(options and options.type or options and options.types or "*"))

    if type(options) ~= "table" then
        options = {}
    end

    local success, result = Agent.findClosestFromPlayer(playerName, options)
    if not success then
        return { ok = false, error = result }
    end
    if type(result) ~= "table" then
        return { ok = false, error = "Unexpected findNearby result" }
    end

    return {
        ok = true,
        player = result.player,
        origin = result.origin,
        results = result.results,
    }
end

---@param playerName string|nil
---@param options AgentVisibleOptions|nil
---@return table
function findVisible(playerName, options)
    Agent.logHttp("findVisible", (playerName or "*"))

    if type(options) ~= "table" then
        options = {}
    end

    local id, err = Agent.startVisibleQuery(playerName, options)
    if not id then
        return { ok = false, error = err }
    end

    return { ok = true, id = id, status = "pending" }
end

---@param id any request id (expected string)
---@return table
function findVisibleResult(id)
    Agent.logHttp("findVisibleResult", tostring(id))
    return Agent.getVisibleQueryResult(id)
end

---@param playerName string|nil
---@param options AgentLookOptions|nil
---@return table
function findLookTarget(playerName, options)
    Agent.logHttp("findLookTarget", (playerName or "*"))

    if type(options) ~= "table" then
        options = {}
    end

    local id, err = Agent.startLookTargetQuery(playerName, options)
    if not id then
        return { ok = false, error = err }
    end

    return { ok = true, id = id, status = "pending" }
end

---@param id any request id (expected string)
---@return table
function findLookTargetResult(id)
    Agent.logHttp("findLookTargetResult", tostring(id))
    return Agent.getLookTargetQueryResult(id)
end

---@param playerName string|nil
---@param options AgentTeleportAreaOptions|nil
---@return table
function teleportToClosestAirport(playerName, options)
    Agent.logHttp("teleportToClosestAirport", (playerName or "*"))

    if type(options) ~= "table" then
        options = {}
    end

    local success, result = Agent.teleportToClosestAirport(playerName, options)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, result = result }
end

---@return { ok: boolean, map: AgentAreaMap }
function getAreaMap()
    return { ok = true, map = Agent.getAreaMap() }
end

---@param options AgentAreaFilters|nil
---@return { ok: boolean, areas: AgentArea[] }
function listAreas(options)
    if type(options) ~= "table" then
        options = {}
    end

    return { ok = true, areas = Agent.listAreas(options) }
end

---@param playerName string|nil
---@param options AgentAreaFilters|nil
---@return table
function findClosestArea(playerName, options)
    Agent.logHttp("findClosestArea", (playerName or "*"))

    if type(options) ~= "table" then
        options = {}
    end

    local success, result = Agent.findClosestAreaFromPlayer(playerName, options)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, result = result }
end

---@param playerName string|nil
---@param options AgentTeleportAreaOptions|nil
---@return table
function teleportToArea(playerName, options)
    Agent.logHttp("teleportToArea", (playerName or "*"))

    if type(options) ~= "table" then
        options = {}
    end

    local success, result = Agent.teleportToArea(playerName, options)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, result = result }
end

---@param playerName string|nil
---@param options AgentTeleportElementOptions|nil
---@return table
function teleportToElement(playerName, options)
    Agent.logHttp("teleportToElement", (playerName or "*"))

    if type(options) ~= "table" then
        options = {}
    end

    local success, result = Agent.teleportToElement(playerName, options)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, result = result }
end

---@param playerName string|nil
---@param targetPlayerName string|nil
---@param options AgentTeleportElementOptions|nil
---@return table
function teleportToPlayer(playerName, targetPlayerName, options)
    Agent.logHttp("teleportToPlayer", (playerName or "*") .. " -> " .. tostring(targetPlayerName))

    if type(options) ~= "table" then
        options = {}
    end

    local success, result = Agent.teleportToPlayer(playerName, targetPlayerName, options)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, result = result }
end

---@param playerName string|nil
---@param x number|nil
---@param y number|nil
---@param z number|nil
---@param options AgentTeleportPositionOptions|nil
---@return table
function teleportToPosition(playerName, x, y, z, options)
    Agent.logHttp("teleportToPosition", (playerName or "*"))

    if type(options) ~= "table" then
        options = {}
    end

    local success, result = Agent.teleportToPosition(playerName, x, y, z, options)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, result = result }
end

---@param key any memory key (expected non-empty string)
---@return table
function memoryGet(key)
    local success, value = Agent.memoryGet(key)
    if not success then
        return { ok = false, error = value }
    end

    return { ok = true, key = key, value = value }
end

---@param key any memory key (expected non-empty string)
---@param value any
---@return table
function memorySet(key, value)
    local success, result = Agent.memorySet(key, value)
    if not success then
        return { ok = false, error = result }
    end

    Agent.logHttp("memorySet", key)
    return { ok = true, key = key, value = result }
end

---@param key any memory key (expected non-empty string)
---@return table
function memoryDelete(key)
    local success, result = Agent.memoryDelete(key)
    if not success then
        return { ok = false, error = result }
    end

    Agent.logHttp("memoryDelete", key)
    return { ok = true, key = key }
end

---@param prefix string|nil
---@return { ok: boolean, keys?: string[], error?: string }
function memoryList(prefix)
    return { ok = true, keys = Agent.memoryList(prefix) }
end

---@param resourceName any resource name (expected non-empty string)
---@param functionName any exported function name (expected non-empty string)
---@param args table|nil
---@return table
function callExport(resourceName, functionName, args)
    if type(resourceName) ~= "string" or resourceName == "" then
        return { ok = false, error = "Resource name required" }
    end
    if type(functionName) ~= "string" or functionName == "" then
        return { ok = false, error = "Function name required" }
    end

    local resourceElement = getResourceFromName(resourceName)
    if not resourceElement then
        return { ok = false, error = "Resource not found: " .. resourceName }
    end

    args = type(args) == "table" and args or {}

    Agent.logHttp("callExport", resourceName .. "." .. functionName)

    local results = { call(resourceElement, functionName, unpack(args)) }

    -- MTA's call() returns a single `false` when the call itself failed
    -- (function not exported, resource not running, runtime error). A
    -- function that genuinely returns false alongside other values is a real
    -- result, so only flag the lone-false case as a failure.
    if #results == 1 and results[1] == false then
        return {
            ok = false,
            resource = resourceName,
            functionName = functionName,
            error = "Export call failed (function not exported, resource not running, or errored): "
                .. resourceName .. "." .. functionName,
        }
    end

    return {
        ok = true,
        resource = resourceName,
        functionName = functionName,
        result = Agent.serializeResults({ true, unpack(results) }),
    }
end

---@return table
function getServerState()
    local playerDetails = Agent.listOnlinePlayers()
    local playerNames = {}
    for i = 1, #playerDetails do
        playerNames[i] = playerDetails[i].name
    end

    local resources = {}
    for _, resourceElement in ipairs(getResources()) do
        resources[#resources + 1] = {
            name = getResourceName(resourceElement),
            state = getResourceState(resourceElement),
        }
    end

    return {
        ok = true,
        mapName = getMapName(),
        maxPlayers = getMaxPlayers(),
        playerCount = #playerDetails,
        players = playerNames,
        playerDetails = playerDetails,
        resources = resources,
        gameType = getGameType(),
        time = getRealTime().timestamp,
    }
end

---@param resourceName any resource name (expected non-empty string)
---@return table
function resourceStart(resourceName)
    Agent.logHttp("resourceStart", resourceName)

    local success, result = Agent.resourceStart(resourceName)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, resource = result }
end

---@param resourceName any resource name (expected non-empty string)
---@return table
function resourceStop(resourceName)
    Agent.logHttp("resourceStop", resourceName)

    local success, result = Agent.resourceStop(resourceName)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, resource = result }
end

---@param resourceName any resource name (expected non-empty string)
---@return table
function resourceRestart(resourceName)
    Agent.logHttp("resourceRestart", resourceName)

    local success, result = Agent.resourceRestart(resourceName)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, resource = result }
end

---@param options AgentResourceSearchOptions|string|nil resource search options table, or bare query string
---@return AgentResourceSearchResult
function resourceSearch(options)
    if type(options) ~= "table" then
        options = { query = options --[[@as string]] }
    end

    Agent.logHttp("resourceSearch", tostring(options.query or options.q or options.name or "*"))
    return Agent.searchResources(options)
end

---@param playerName string|nil
---@param options table|nil any options table carrying an optional `serial` field
---@return player|nil
---@return string|nil err
local function resolveElementPlayer(playerName, options)
    return Agent.resolvePlayerElement(playerName, options)
end

---@param playerName string|nil
---@param options AgentTrackElementOpts|nil
---@return table
function elementTrack(playerName, options)
    Agent.logHttp("elementTrack", (playerName or "*"))

    options = type(options) == "table" and options or {}

    if options.mtaHandle or options.id then
        local handle = options.mtaHandle or options.id
        if type(handle) ~= "string" or handle == "" then
            return { ok = false, error = "mtaHandle or id required" }
        end
        local agentId, err = Agent.trackElementByHandle(handle, options)
        if not agentId then
            return { ok = false, error = err }
        end

        local entry = Agent.getElement(agentId, { refresh = options.refresh ~= false })
        return { ok = true, id = agentId, entry = entry }
    end

    local player, err = resolveElementPlayer(playerName, options)
    if not player then
        return { ok = false, error = err }
    end

    if options.side == Agent.ELEMENT_SIDE_CLIENT then
        local playerName = getPlayerName(player)
        local onComplete = nil
        if options.sync ~= false then
            onComplete = function() Agent.syncClientRegistry(playerName) end
        end

        local id, err = Agent.startClientRequest(player, "elementTrack", options, { onComplete = onComplete })
        if not id then
            return { ok = false, error = err }
        end

        return { ok = true, id = id, status = "pending", side = "client", player = playerName }
    end

    local findOptions = {
        type = options.type,
        types = options.types,
        limit = options.limit or 1,
        maxDistance = options.maxDistance,
        model = options.model,
        search = options.search,
        autoTrack = true,
        trackSource = options.source or "elementTrack",
    }

    local success, result = Agent.findClosestFromPlayer(getPlayerName(player), findOptions)
    if not success or type(result) ~= "table" then
        return { ok = false, error = type(result) == "string" and result or "findNearby failed" }
    end

    ---@cast result AgentNearbyResult
    local results = result.results
    if type(results) ~= "table" then
        return { ok = false, error = "Unexpected findNearby result" }
    end

    local first = results[1]
    if not first then
        return { ok = false, error = "No matching element found" }
    end

    local agentId = first.agentId
    if not agentId then
        agentId, trackErr = Agent.trackElementByHandle(first.id, {
            label = options.label,
            meta = options.meta,
            source = options.source or "elementTrack",
            elementType = first.elementType,
        })
        if not agentId then
            return { ok = false, error = trackErr }
        end
    end

    local entry = Agent.getElement(agentId, { refresh = options.refresh ~= false })
    return { ok = true, id = agentId, entry = entry, match = first }
end

---@param id any element id (expected non-empty string)
---@param options AgentGetElementOptions|nil
---@return table
function elementGet(id, options)
    Agent.logHttp("elementGet", tostring(id))

    options = type(options) == "table" and options or {}
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Element id required" }
    end

    local parsed = Agent.parseElementId(id)
    if parsed and parsed.side == Agent.ELEMENT_SIDE_CLIENT then
        local player, err = resolveElementPlayer(options.player, options)
        if not player then
            return { ok = false, error = err }
        end

        local playerName = getPlayerName(player)
        local onComplete = nil
        if options.sync ~= false then
            onComplete = function() Agent.syncClientRegistry(playerName) end
        end

        local requestId, err = Agent.startClientRequest(player, "elementGet", {
            id = id,
            refresh = options.refresh,
        }, { onComplete = onComplete })
        if not requestId then
            return { ok = false, error = err }
        end

        return { ok = true, id = requestId, status = "pending", side = "client", player = playerName }
    end

    local entry, errInfo = Agent.getElement(id, options)
    if not entry then
        return {
            ok = false,
            error = errInfo and errInfo.error or "notFound",
            currentStartupAt = errInfo and errInfo.currentStartupAt,
            entry = errInfo and errInfo.entry,
        }
    end

    return { ok = true, entry = entry }
end

---@param options AgentElementFilters|table|nil
---@return table
function elementList(options)
    Agent.logHttp("elementList", "")

    options = type(options) == "table" and options or {}

    if options.syncClient and options.player then
        local player, err = resolveElementPlayer(options.player, options)
        if not player then
            return { ok = false, error = err }
        end
        Agent.syncClientRegistry(getPlayerName(player))
    end

    return {
        ok = true,
        startupAt = Agent.registry and Agent.registry.startupAt or nil,
        elements = Agent.listElements(options),
    }
end

---@param id any element id (expected non-empty string)
---@param options AgentGetElementOptions|nil
---@return table
function elementRelease(id, options)
    Agent.logHttp("elementRelease", tostring(id))

    options = type(options) == "table" and options or {}
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Element id required" }
    end

    local parsed = Agent.parseElementId(id)
    if parsed and parsed.side == Agent.ELEMENT_SIDE_CLIENT then
        local player, err = resolveElementPlayer(options.player, options)
        if not player then
            return { ok = false, error = err }
        end

        local requestId, err = Agent.startClientRequest(player, "elementRelease", { id = id }, {
            onComplete = function() Agent.releaseElement(id) end,
        })
        if not requestId then
            return { ok = false, error = err }
        end

        return { ok = true, id = requestId, status = "pending", side = "client", player = getPlayerName(player) }
    end

    local success, err = Agent.releaseElement(id)
    if not success then
        return { ok = false, error = err }
    end

    return { ok = true, id = id, released = true }
end

---@param id any element id (expected non-empty string)
---@param options (AgentElementModifyOps|table)|nil
---@return table
function elementModify(id, options)
    Agent.logHttp("elementModify", tostring(id))

    options = type(options) == "table" and options or {}
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Element id required" }
    end

    local parsed = Agent.parseElementId(id)
    if parsed and parsed.side == Agent.ELEMENT_SIDE_CLIENT then
        local player, err = resolveElementPlayer(options.player, options)
        if not player then
            return { ok = false, error = err }
        end

        local playerName = getPlayerName(player)
        local onComplete = nil
        if options.sync ~= false then
            onComplete = function() Agent.syncClientRegistry(playerName) end
        end

        local requestId, err = Agent.startClientRequest(player, "elementModify", {
            id = id,
            ops = options.set and { set = options.set } or options,
        }, { onComplete = onComplete })
        if not requestId then
            return { ok = false, error = err }
        end

        return { ok = true, id = requestId, status = "pending", side = "client", player = playerName }
    end

    local success, result = Agent.modifyElement(id, options.set and { set = options.set } or options)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, entry = result }
end

---@param id any request id (expected string)
---@return table
function elementResult(id)
    Agent.logHttp("elementResult", tostring(id))
    return Agent.getClientRequestResult(id)
end

---@param id any element id (expected non-empty string)
---@param options AgentGetElementOptions|nil
---@return table
function elementResolve(id, options)
    Agent.logHttp("elementResolve", tostring(id))

    options = type(options) == "table" and options or {}
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Element id required" }
    end

    local getResult = elementGet(id, { refresh = false, player = options.player, sync = false })
    if not getResult.ok then
        return getResult
    end

    -- Client-side gets are async now; hand back the pending id to poll via elementResult.
    if getResult.status == "pending" then
        return getResult
    end

    local entry = getResult.entry or {}
    return {
        ok = true,
        id = entry.id,
        side = entry.side,
        localOnly = entry.localOnly,
        owner = entry.owner,
        elementType = entry.elementType,
        mtaHandle = entry.mtaHandle,
        startupAt = entry.startupAt,
        props = entry.props,
        label = entry.label,
        meta = entry.meta,
        alive = entry.alive,
    }
end

---@param options AgentWalkOptions|nil
---@return AgentWalkOptions
local function sanitizeWalkOptions(options)
    options = type(options) == "table" and options or {}
    return {
        mode = options.mode,
        rootsOnly = options.rootsOnly,
        resourceName = options.resourceName,
        rootId = options.rootId,
        childType = options.childType,
        elementType = options.elementType,
        maxDepth = options.maxDepth,
        maxNodes = options.maxNodes,
        flat = options.flat,
        track = options.track,
        autoTrack = options.autoTrack,
        trackSource = options.trackSource,
        resourceState = options.resourceState,
        resourcesOnly = options.resourcesOnly,
        side = options.side,
        player = options.player,
        query = options.query,
        q = options.q,
        state = options.state,
        limit = options.limit,
        runningOnly = options.runningOnly,
        listMapChildren = options.listMapChildren,
        mapChildLimit = options.mapChildLimit,
        autoTrackChildren = options.autoTrackChildren,
        autoTrackChildLimit = options.autoTrackChildLimit,
        parentMtaHandle = options.parentMtaHandle,
        parentElementType = options.parentElementType,
    }
end

---@param options AgentWalkOptions|nil
---@return table
function elementWalk(options)
    Agent.logHttp("elementWalk", tostring(options and options.resourceName or options and options.mode or "root"))

    options = sanitizeWalkOptions(options)

    if options.side == Agent.ELEMENT_SIDE_CLIENT then
        local player, err = resolveElementPlayer(options.player, options)
        if not player then
            return { ok = false, error = err }
        end

        local requestId, err = Agent.startClientRequest(player, "elementWalk", options)
        if not requestId then
            return { ok = false, error = err }
        end

        return { ok = true, id = requestId, status = "pending", side = "client", player = getPlayerName(player) }
    end

    local success, result = Agent.walkElementTree(options)
    if not success then
        return { ok = false, error = result }
    end

    return { ok = true, side = "server", result = result }
end

---@param playerName string|nil
---@param options AgentGuiScanOptions|nil
---@return table
function guiScan(playerName, options)
    Agent.logHttp("guiScan", (playerName or "*") .. " " .. tostring(options and options.windowTitle or "*"))

    local id, err = Agent.startGuiScan(playerName, options)
    if not id then
        return { ok = false, error = err }
    end

    return { ok = true, id = id, status = "pending" }
end

---@param id any request id (expected string)
---@return table
function guiScanResult(id)
    Agent.logHttp("guiScanResult", tostring(id))
    return Agent.getGuiScanResult(id)
end

---@param playerName string|nil
---@param options AgentDebugLogOptions|nil
---@return table
function debugLogList(playerName, options)
    if type(options) ~= "table" then
        options = {}
    end

    local side = options.side or "server"
    Agent.logHttp("debugLogList", (playerName or "*") .. " side=" .. tostring(side))

    if side == "server" then
        return {
            ok = true,
            status = "complete",
            side = "server",
            result = Agent.listServerDebugLogs(options),
        }
    end

    local id, err = Agent.startDebugLogFetch(playerName, options)
    if not id then
        return { ok = false, error = err }
    end

    return { ok = true, id = id, status = "pending", side = side }
end

---@param id any request id (expected string)
---@return table
function debugLogResult(id)
    Agent.logHttp("debugLogResult", tostring(id))
    return Agent.getDebugLogFetchResult(id)
end

---@param playerName string|nil
---@param options AgentEventHookControlOptions|nil
---@return table
function debugEvents(playerName, options)
    if type(options) ~= "table" then
        options = {}
    end

    local action = options.action or "list"
    Agent.logHttp("debugEvents", (playerName or "*") .. " action=" .. tostring(action) .. " side=" .. tostring(options.side or "server"))
    return Agent.handleDebugEvents(playerName, options)
end

---@param id any request id (expected string)
---@return table
function debugEventsResult(id)
    Agent.logHttp("debugEventsResult", tostring(id))
    return Agent.getEventHookRequestResult(id)
end

---@param playerName string|nil
---@param options AgentHealthOptions|nil
---@return table
function healthGet(playerName, options)
    if type(options) ~= "table" then
        options = {}
    end

    local side = options.side or "server"
    Agent.logHttp("healthGet", (playerName or "*") .. " side=" .. tostring(side))
    return Agent.handleHealthGet(playerName, options)
end

---@param id any request id (expected string)
---@return table
function healthResult(id)
    Agent.logHttp("healthResult", tostring(id))
    return Agent.getHealthFetchResult(id)
end

---@param identifier string|nil player name or serial
---@param options AgentResolvePlayerOptions|nil
---@return table
function resolvePlayer(identifier, options)
    if type(options) ~= "table" then
        options = {}
    end

    if type(identifier) == "string" and identifier ~= "" and options.serial == nil then
        if Agent.isPlayerSerial(identifier) then
            options.serial = identifier
            identifier = nil
        end
    end

    local info, err = Agent.resolvePlayerInfo(identifier, options)
    if not info then
        return { ok = false, error = err }
    end

    return { ok = true, player = info }
end
