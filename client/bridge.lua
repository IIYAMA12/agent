--- Client-side request/response bridge: dispatches server-triggered actions to client handlers.

local REQUEST_EVENT = "agent:clientRequest"
local RESPONSE_EVENT = "agent:clientResponse"
local READY_EVENT = "agent:clientReady"

---@param action string one of the `element*`/`guiScan`/`debugLogSnapshot`/`debugEventHook`/`healthSnapshot`/`indicate` actions
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

    if action == "indicate" then
        if type(Agent.handleClientIndicate) ~= "function" then
            return { ok = false, error = "Indications unavailable on client" }
        end
        return Agent.handleClientIndicate(payload)
    end

    if action == "cameraMatrix" then
        if type(Agent.getClientCameraMatrix) ~= "function" then
            return { ok = false, error = "Camera matrix unavailable on client" }
        end
        local matrix, err = Agent.getClientCameraMatrix()
        if not matrix then
            return { ok = false, error = err or "getCameraMatrix failed" }
        end
        return { ok = true, result = matrix }
    end

    if action == "modelReplace" then
        if type(Agent.applyModelReplace) ~= "function" then
            return { ok = false, error = "Model replace unavailable on client" }
        end
        return Agent.applyModelReplace(payload)
    end

    if action == "modelRestore" then
        if type(Agent.restoreModelReplace) ~= "function" then
            return { ok = false, error = "Model restore unavailable on client" }
        end
        local result = Agent.restoreModelReplace(payload)
        local hooks = Agent.clientActions
        if hooks and type(hooks.afterModelRestore) == "function" then
            hooks.afterModelRestore(payload)
        end
        return result
    end

    if action == "loadLocalScript" then
        return Agent.loadLocalScript(payload)
    end

    if action == "boundingScanStart" then
        if type(Agent.startBoundingScanClient) ~= "function" then
            return { ok = false, error = "Bounding scan unavailable on client" }
        end
        return Agent.startBoundingScanClient(payload)
    end

    if action == "boundingScanStop" then
        if type(Agent.stopBoundingScanClient) ~= "function" then
            return { ok = false, error = "Bounding scan unavailable on client" }
        end
        return Agent.stopBoundingScanClient(payload)
    end

    if action == "boundingFetch" then
        if type(Agent.fetchBoundingClient) ~= "function" then
            return { ok = false, error = "Bounding fetch unavailable on client" }
        end
        return Agent.fetchBoundingClient(payload)
    end

    if action == "boundingResolve" then
        if type(Agent.resolveBoundingClient) ~= "function" then
            return { ok = false, error = "Bounding lookup unavailable on client" }
        end
        return Agent.resolveBoundingClient(payload)
    end

    if action == "boundingDraw" then
        if type(Agent.drawBoundingClient) ~= "function" then
            return { ok = false, error = "Bounding draw unavailable on client" }
        end
        return Agent.drawBoundingClient(payload)
    end

    local hooks = Agent.clientActions
    local handler = hooks and hooks[action]
    if type(handler) == "function" then
        return handler(payload)
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
    if Agent._deferClientReply then
        return nil
    end
    if elementResponse then
        return elementResponse
    end

    return { ok = false, error = "Unknown client action: " .. tostring(action) }
end

---@return string|nil requestId
function Agent.deferClientResponse()
    local requestId = Agent._activeClientRequestId
    if type(requestId) ~= "string" or requestId == "" then
        return nil
    end
    Agent._deferClientReply = true
    return requestId
end

---@param requestId string
---@param response table|nil
function Agent.replyClientRequest(requestId, response)
    if type(requestId) ~= "string" or requestId == "" then
        return
    end
    triggerServerEvent(RESPONSE_EVENT, resourceRoot, requestId, response or { ok = false, error = "empty client response" })
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
    Agent._deferClientReply = false
    Agent._activeClientRequestId = requestId
    local response = dispatchClientAction(action, payload)
    local deferred = Agent._deferClientReply
    Agent._activeClientRequestId = nil
    Agent._deferClientReply = false
    if deferred then
        return
    end
    triggerServerEvent(RESPONSE_EVENT, resourceRoot, requestId, response)
end)

---@param payload table|nil
---@return AgentHttpPayload
function Agent.loadLocalScript(payload)
    payload = type(payload) == "table" and payload or {}
    local code = payload.code
    if type(code) ~= "string" or code == "" then
        return { ok = false, error = "code is required", file = payload.file }
    end

    local fn, err = loadstring(code)
    if not fn then
        return { ok = false, error = tostring(err), file = payload.file }
    end

    local ok, result = pcall(fn)
    if not ok then
        return { ok = false, error = tostring(result), file = payload.file }
    end

    return { ok = true, file = payload.file }
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    Agent.initRegistry(getRealTime().timestamp, Agent.ELEMENT_SIDE_CLIENT)
    triggerServerEvent(READY_EVENT, resourceRoot)
end)
