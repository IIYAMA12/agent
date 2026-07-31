--- Client-side request/response bridge: dispatches server-triggered actions to client handlers.

local REQUEST_EVENT = "agent:clientRequest"
local RESPONSE_EVENT = "agent:clientResponse"
local READY_EVENT = "agent:clientReady"

---@param action string one of the `element*`/`guiScan`/`debugLogSnapshot`/`debugEventHook`/`healthSnapshot` actions
---@param payload table|nil action-specific payload (e.g. AgentTrackElementOpts, AgentGetElementOptions, AgentElementFilters, AgentElementModifyOps, AgentWalkOptions, AgentGuiScanOptions, AgentDebugLogOptions, AgentEventHookControlOptions, AgentHealthOptions)
---@return AgentHttpPayload|nil response `nil` when `action` is not an element-related action
local function dispatchElementAction(action, payload)
    payload = type(payload) == "table" and payload or {}

    if action == "elementTrack" then
        local mtaHandle = payload.mtaHandle or payload.id
        if not mtaHandle then
            return { ok = false, error = "mtaHandle required" }
        end

        local agentId, err = Agent.trackElementByHandle(mtaHandle, {
            label = payload.label,
            meta = payload.meta,
            source = payload.source or "bridge",
            elementType = payload.elementType,
        })
        if not agentId then
            return { ok = false, error = err }
        end

        local entry = Agent.getElement(agentId, { refresh = payload.refresh ~= false })
        return { ok = true, result = { id = agentId, entry = entry } }
    end

    if action == "elementGet" or action == "elementRefresh" then
        local id = payload.id or payload.agentId
        if not id then
            return { ok = false, error = "id required" }
        end

        local entry, errInfo = Agent.getElement(id, { refresh = payload.refresh ~= false or action == "elementRefresh" })
        if not entry then
            return { ok = false, error = errInfo and errInfo.error or "notFound", details = errInfo }
        end

        return { ok = true, result = entry, entry = entry }
    end

    if action == "elementList" then
        return { ok = true, result = Agent.listElements(payload) }
    end

    if action == "elementRelease" then
        local id = payload.id or payload.agentId
        if not id then
            return { ok = false, error = "id required" }
        end

        local success, err = Agent.releaseElement(id)
        if not success then
            return { ok = false, error = err }
        end

        return { ok = true, result = { id = id, released = true } }
    end

    if action == "elementModify" then
        local id = payload.id or payload.agentId
        if not id then
            return { ok = false, error = "id required" }
        end

        local success, result = Agent.modifyElement(id, payload.ops or payload)
        if not success then
            return { ok = false, error = result }
        end

        return { ok = true, result = result, entry = result }
    end

    if action == "elementRegistrySync" then
        return { ok = true, entries = Agent.exportRegistrySnapshot() }
    end

    if action == "elementWalk" then
        local success, result = Agent.walkElementTree(payload)
        if not success then
            return { ok = false, error = result }
        end
        return { ok = true, result = result }
    end

    if action == "guiScan" then
        if type(Agent.scanGui) ~= "function" then
            return { ok = false, error = "GUI scanner unavailable on client" }
        end
        return { ok = true, result = Agent.scanGui(payload) }
    end

    if action == "debugLogSnapshot" then
        if type(Agent.getClientDebugLogSnapshot) ~= "function" then
            return { ok = false, error = "Debug log buffer unavailable on client" }
        end
        return { ok = true, result = Agent.getClientDebugLogSnapshot(payload) }
    end

    if action == "debugEventHook" then
        if type(Agent.handleClientEventHook) ~= "function" then
            return { ok = false, error = "Event hook tracker unavailable on client" }
        end
        return Agent.handleClientEventHook(payload)
    end

    if action == "healthSnapshot" then
        if type(Agent.getClientHealthSnapshot) ~= "function" then
            return { ok = false, error = "Health snapshot unavailable on client" }
        end
        return { ok = true, result = Agent.getClientHealthSnapshot(payload) }
    end

    return nil
end

---@param action string action name (`runEval`, `getVisibleElements`, `getLookTarget`, or any `dispatchElementAction` action)
---@param payload table action-specific payload
---@return AgentHttpPayload response `{ ok = true, ... }` or `{ ok = false, error }`
local function dispatchClientAction(action, payload)
    if action == "runEval" then
        local code = payload.code or payload.value
        return runEval(code)
    end

    if action == "getVisibleElements" then
        return getVisibleElements(payload)
    end

    if action == "getLookTarget" then
        return getLookTarget(payload)
    end

    local elementResponse = dispatchElementAction(action, payload)
    if elementResponse then
        return elementResponse
    end

    return { ok = false, error = "Unknown client action: " .. tostring(action) }
end

addEvent(REQUEST_EVENT, true)
addEventHandler(REQUEST_EVENT, resourceRoot, function(requestId, action, payload)
    if source ~= resourceRoot then
        return
    end

    if type(requestId) ~= "string" or type(action) ~= "string" then
        return
    end

    payload = type(payload) == "table" and payload or {}
    local response = dispatchClientAction(action, payload)
    triggerServerEvent(RESPONSE_EVENT, resourceRoot, requestId, response)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    Agent.initRegistry(getRealTime().timestamp, Agent.ELEMENT_SIDE_CLIENT)
    triggerServerEvent(READY_EVENT, resourceRoot)
end)
