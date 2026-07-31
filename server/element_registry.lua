--- Server-side element registry: tracking, resolving, listing, and modifying elements by stable agent id.
---@class Agent
Agent = Agent or {}

Agent.clientShadows = Agent.clientShadows or {} ---@type table<string, AgentClientShadowStore>

---@return integer
local function nowTimestamp()
    return getRealTime().timestamp
end

---@param entry AgentRegistryEntry|table|nil
---@return AgentRegistryEntry|table|nil
local function refreshEntryProps(entry)
    if not entry or not isElement(entry.element) then
        return entry
    end

    entry.props = Agent.describeNearbyElement(entry.element, (entry.props and entry.props.distance) or 0) or entry.props
    entry.lastSeenAt = nowTimestamp()
    entry.alive = true
    return entry
end

---@param entry AgentRegistryEntry|table|nil
---@return nil
local function unregisterEntry(entry)
    if not entry or not Agent.registry then
        return
    end

    if entry.element then
        Agent.registry.byElement[entry.element] = nil
    end
    if entry.id then
        Agent.registry.byId[entry.id] = nil
    end
end

---@param element element
---@param opts AgentTrackElementOpts|table|nil
---@return string|nil id
---@return string|nil error
function Agent.trackElement(element, opts)
    if not Agent.registry then
        return nil, "Registry not initialized"
    end

    if not isElement(element) then
        return nil, "Invalid element"
    end

    opts = type(opts) == "table" and opts or {}

    local existing = Agent.registry.byElement[element]
    if existing and existing.alive ~= false then
        if opts.label then
            existing.label = opts.label
        end
        if type(opts.meta) == "table" then
            existing.meta = existing.meta or {}
            for key, value in pairs(opts.meta) do
                existing.meta[key] = value
            end
        end
        if opts.source then
            existing.source = opts.source
        end
        refreshEntryProps(existing)
        return existing.id
    end

    local id, err = Agent.makeElementId(Agent.ELEMENT_SIDE_SERVER)
    if not id then
        return nil, err
    end

    local timestamp = nowTimestamp()
    ---@type AgentRegistryEntry
    local entry = {
        id = id,
        element = element,
        side = Agent.ELEMENT_SIDE_SERVER,
        localOnly = false,
        owner = opts.owner,
        elementType = getElementType(element),
        mtaHandle = tostring(element),
        startupAt = Agent.registry.startupAt,
        createdAt = timestamp,
        lastSeenAt = timestamp,
        label = opts.label,
        meta = type(opts.meta) == "table" and opts.meta or {},
        props = {},
        source = opts.source or "manual",
        alive = true,
    }

    refreshEntryProps(entry)
    Agent.registry.byElement[element] = entry
    Agent.registry.byId[id] = entry

    return id
end

---@param mtaHandle string
---@param opts AgentTrackElementOpts|table|nil
---@return string|nil id, string|nil error
function Agent.trackElementByHandle(mtaHandle, opts)
    opts = type(opts) == "table" and opts or {}
    local element = Agent.findElementByMtaHandle(mtaHandle, opts)
    if not element then
        return nil, "Element not found for handle: " .. tostring(mtaHandle)
    end
    return Agent.trackElement(element, opts)
end

---@param id string
---@return element|nil element
---@return AgentRegistryEntry|nil entry
---@return string|nil error
---@return integer|nil currentStartupAt
function Agent.resolveElement(id)
    if not Agent.registry then
        return nil, nil, "Registry not initialized"
    end

    local valid, parsedOrErr, currentStartupAt = Agent.validateElementId(id)
    if not valid then
        if parsedOrErr == "staleId" then
            return nil, nil, "staleId", currentStartupAt
        end
        return nil, nil, type(parsedOrErr) == "string" and parsedOrErr or "invalidId"
    end

    ---@cast parsedOrErr AgentParsedElementId
    if parsedOrErr.side == Agent.ELEMENT_SIDE_CLIENT then
        return nil, nil, "clientIdRequiresBridge"
    end

    local entry = Agent.registry.byId[id]
    if not entry then
        return nil, nil, "notFound"
    end

    if not isElement(entry.element) then
        entry.alive = false
        return nil, entry, "elementDestroyed"
    end

    return entry.element, entry
end

---@param id string
---@param options AgentGetElementOptions|table|nil
---@return table|nil serialized
---@return table|nil error
function Agent.getElement(id, options)
    options = type(options) == "table" and options or {}

    local element, entry, err, currentStartupAt = Agent.resolveElement(id)
    if err == "staleId" then
        return nil, { error = err, currentStartupAt = currentStartupAt }
    end

    if err == "clientIdRequiresBridge" then
        local shadow = Agent.findClientShadowEntry(id)
        if shadow then
            entry = shadow
        else
            return nil, { error = err }
        end
    elseif err == "notFound" then
        return nil, { error = err }
    elseif err == "elementDestroyed" then
        if not entry then
            return nil, { error = err }
        end
        return Agent.serializeEntry(entry), { error = err, entry = Agent.serializeEntry(entry) }
    end

    if not entry then
        return nil, { error = err or "notFound" }
    end

    if element and options.refresh ~= false then
        refreshEntryProps(entry)
    end

    return Agent.serializeEntry(entry)
end

---@param filters AgentElementFilters|table|nil
---@return AgentRegistryEntry[]|table[]
function Agent.listElements(filters)
    filters = type(filters) == "table" and filters or {}
    local results = {}

    if Agent.registry then
        for _, entry in pairs(Agent.registry.byId) do
            if Agent.matchesElementFilters(entry, filters) then
                results[#results + 1] = Agent.serializeEntry(entry)
            end
        end
    end

    if filters.includeClientShadows ~= false then
        local ownerFilter = filters.owner
        for playerName, store in pairs(Agent.clientShadows) do
            if not ownerFilter or ownerFilter == playerName then
                for _, entry in pairs(store.byId or {}) do
                    if Agent.matchesElementFilters(entry, filters) then
                        results[#results + 1] = Agent.serializeEntry(entry)
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.createdAt or 0) < (b.createdAt or 0)
    end)

    return results
end

---@param id string
---@return boolean ok
---@return string|nil error
function Agent.releaseElement(id)
    local valid, parsedOrErr = Agent.validateElementId(id)
    if not valid then
        return false, type(parsedOrErr) == "string" and parsedOrErr or "invalidId"
    end

    ---@cast parsedOrErr AgentParsedElementId
    if parsedOrErr.side == Agent.ELEMENT_SIDE_CLIENT then
        local shadow, playerName = Agent.findClientShadowEntry(id)
        if shadow and playerName and Agent.clientShadows[playerName] then
            Agent.clientShadows[playerName].byId[id] = nil
            return true
        end
        return false, "notFound"
    end

    local entry = Agent.registry and Agent.registry.byId[id]
    if not entry then
        return false, "notFound"
    end

    unregisterEntry(entry)
    return true
end

---@param id string
---@param patch { label?: string, meta?: table }|table|nil
---@return boolean, table|string|nil result
function Agent.setElementMeta(id, patch)
    patch = type(patch) == "table" and patch or {}
    local element, entry, err = Agent.resolveElement(id)

    if err == "clientIdRequiresBridge" then
        local shadow, playerName = Agent.findClientShadowEntry(id)
        if not shadow then
            return false, "notFound"
        end
        if patch.label then
            shadow.label = patch.label
        end
        if type(patch.meta) == "table" then
            shadow.meta = shadow.meta or {}
            for key, value in pairs(patch.meta) do
                shadow.meta[key] = value
            end
        end
        return true, Agent.serializeEntry(shadow)
    end

    if not entry then
        return false, err or "notFound"
    end

    if patch.label then
        entry.label = patch.label
    end
    if type(patch.meta) == "table" then
        entry.meta = entry.meta or {}
        for key, value in pairs(patch.meta) do
            entry.meta[key] = value
        end
    end

    return true, Agent.serializeEntry(entry)
end

---@param id string
---@return AgentRegistryEntry|table|nil entry, string|nil playerName
function Agent.findClientShadowEntry(id)
    for playerName, store in pairs(Agent.clientShadows) do
        local entry = store.byId and store.byId[id]
        if entry then
            return entry, playerName
        end
    end
    return nil
end

---@param playerName string
---@param entries AgentRegistryEntry[]|table[]|nil
---@return boolean ok
---@return string|nil error
function Agent.updateClientShadows(playerName, entries)
    if type(playerName) ~= "string" or playerName == "" then
        return false, "Player name required"
    end

    ---@type AgentClientShadowStore
    local storeRoot = { byId = {} }
    Agent.clientShadows[playerName] = storeRoot
    local store = storeRoot.byId

    if type(entries) ~= "table" then
        return true
    end

    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and type(entry.id) == "string" then
            store[entry.id] = entry
        end
    end

    return true
end

---@param element element
---@param elementType string
---@param set AgentElementModifySet
---@return nil
local function applyCommonModify(element, elementType, set)
    local p = set.position
    if p then
        setElementPosition(element, p.x, p.y, p.z)
    end

    local r = set.rotation
    if r then
        setElementRotation(element, r.x, r.y, r.z)
    end

    if set.dimension ~= nil then
        setElementDimension(element, set.dimension)
    end

    if set.interior ~= nil then
        setElementInterior(element, set.interior)
    end

    if set.health ~= nil then
        setElementHealth(element, set.health)
    end

    if set.frozen ~= nil then
        setElementFrozen(element, set.frozen == true)
    end

    if set.alpha ~= nil then
        setElementAlpha(element, set.alpha)
    end

    if elementType == "vehicle" then
        if set.locked ~= nil then
            setVehicleLocked(element, set.locked == true)
        end
        if set.engine ~= nil then
            setVehicleEngineState(element, set.engine == true)
        end
        if set.plate ~= nil then
            setVehiclePlateText(element, tostring(set.plate))
        end
    end

    if elementType == "player" or elementType == "ped" then
        if set.armor ~= nil then
            setPedArmor(element, set.armor)
        end
        if set.skin ~= nil then
            setElementModel(element, set.skin)
        end
    end
end

---@param id string
---@param ops AgentElementModifyOps|AgentElementModifySet|table
---@return boolean ok
---@return table|string|nil result
function Agent.modifyElement(id, ops)
    ops = type(ops) == "table" and ops or {}
    ---@type AgentElementModifySet
    local set = type(ops.set) == "table" and ops.set or ops --[[@as AgentElementModifySet]]

    local parsed = Agent.parseElementId(id)
    if not parsed then
        return false, "invalidId"
    end

    if parsed.side == Agent.ELEMENT_SIDE_CLIENT then
        return false, "clientIdRequiresBridge"
    end

    local element, entry, err = Agent.resolveElement(id)
    if not element or not entry then
        return false, err or "notFound"
    end

    applyCommonModify(element, entry.elementType, set)
    refreshEntryProps(entry)

    return true, Agent.serializeEntry(entry)
end

---@param playerName string
---@param id string
---@param ops AgentElementModifyOps|AgentElementModifySet|table
---@return string|false|nil id
---@return string|nil error
function Agent.modifyElementOnClient(playerName, id, ops)
    if type(Agent.startClientRequest) ~= "function" then
        return false, "Client bridge unavailable"
    end

    return Agent.startClientRequest(playerName, "elementModify", {
        id = id,
        ops = ops,
    })
end

-- Best-effort, fire-and-forget refresh of client-side shadow entries. The
-- client reply arrives asynchronously (HTTP export calls cannot block for it),
-- so shadows update once the response is delivered rather than inline.
---@param playerName string
---@return boolean, string|nil idOrError
function Agent.syncClientRegistry(playerName)
    if type(Agent.startClientRequest) ~= "function" then
        return false, "Client bridge unavailable"
    end

    local id, err = Agent.startClientRequest(playerName, "elementRegistrySync", {}, {
        onComplete = function(request, clientReturn)
            Agent.updateClientShadows(playerName, clientReturn.entries or {})
        end,
    })
    if not id then
        return false, err
    end

    return true, id
end

---@param playerName string
---@param action string
---@param payload table|nil
---@return string|false|nil id
---@return string|nil error
function Agent.callClientElementAction(playerName, action, payload)
    if type(Agent.startClientRequest) ~= "function" then
        return false, "Client bridge unavailable"
    end

    return Agent.startClientRequest(playerName, action, payload or {})
end

---@param result AgentVisibleResult|AgentLookResult|table
---@param options AgentAutoTrackOpts|table|nil
---@return AgentVisibleResult|AgentLookResult|table result
function Agent.processClientDiscoveryResult(result, options)
    if type(result) ~= "table" or not options or options.autoTrack ~= true then
        return result
    end

    if type(result.elements) == "table" then
        Agent.autoTrackDiscoveryResults(result.elements, {
            autoTrack = true,
            trackSource = options.trackSource or "visible",
        })
    end

    if type(result.lookingAt) == "table" then
        Agent.autoTrackLookTarget(result, {
            autoTrack = true,
            trackSource = options.trackSource or "lookTarget",
        })
    end

    return result
end

---@param results AgentNearbyProps[]|table[]
---@param opts AgentAutoTrackOpts|table|nil
---@return AgentNearbyProps[]|table[] results
function Agent.autoTrackDiscoveryResults(results, opts)
    if not opts or opts.autoTrack ~= true or type(results) ~= "table" then
        return results
    end

    local trackOpts = {
        autoTrack = true,
        trackSource = opts.trackSource or opts.source,
        trackLabel = opts.trackLabel,
        trackMeta = opts.trackMeta,
    }

    for i = 1, #results do
        local props = results[i]
        if type(props) == "table" and props.id then
            local element = Agent.findElementByMtaHandle(props.id, props.elementType)
            if element then
                Agent.attachAgentIdToProps(props, element, trackOpts)
            end
        end
    end

    return results
end

---@param result AgentLookResult|table
---@param opts AgentAutoTrackOpts|table|nil
---@return AgentLookResult|table result
function Agent.autoTrackLookTarget(result, opts)
    if not opts or opts.autoTrack ~= true or type(result) ~= "table" then
        return result
    end

    local lookingAt = result.lookingAt
    if type(lookingAt) ~= "table" or not lookingAt.id then
        return result
    end

    local element = Agent.findElementByMtaHandle(lookingAt.id, lookingAt.elementType)
    if element then
        Agent.attachAgentIdToProps(lookingAt, element, {
            autoTrack = true,
            trackSource = opts.trackSource or "lookTarget",
        })
    end

    return result
end

---@param element element
---@return AgentRegistryEntry|table|nil
function Agent.getRegistryEntryForElement(element)
    if not Agent.registry or not isElement(element) then
        return nil
    end

    return Agent.registry.byElement[element]
end

addEventHandler("onElementDestroy", root, function()
    if not Agent.registry then
        return
    end

    local entry = Agent.registry.byElement[source]
    if entry then
        unregisterEntry(entry)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    local playerName = getPlayerName(source)
    Agent.clientShadows[playerName] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function(stoppedResource)
    if stoppedResource ~= resource then
        return
    end

    Agent.registry = nil
    Agent.clientShadows = {}
end)
