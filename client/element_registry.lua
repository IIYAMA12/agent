--- Client-side tracked element registry: track/resolve/modify elements by stable agent id.

---@class Agent
Agent = Agent or {}

---@return integer timestamp
local function nowTimestamp()
    return getRealTime().timestamp
end

---@param element element
---@return boolean
local function isLocalElement(element)
    if type(isElementLocal) == "function" then
        return isElementLocal(element) == true
    end
    return false
end

---@param entry AgentRegistryEntry|nil
---@return AgentRegistryEntry|nil entry
local function refreshEntryProps(entry)
    if not entry or not isElement(entry.element) then
        return entry
    end

    entry.props = Agent.describeNearbyElement(entry.element, (entry.props and entry.props.distance) or 0) or entry.props
    entry.lastSeenAt = nowTimestamp()
    entry.alive = true
    return entry
end

---@param entry AgentRegistryEntry|nil
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

    local id, err = Agent.makeElementId(Agent.ELEMENT_SIDE_CLIENT)
    if not id then
        return nil, err
    end

    local timestamp = nowTimestamp()
    local owner = opts.owner
    if not owner and isElement(localPlayer) then
        owner = getPlayerName(localPlayer)
    end

    local entry = {
        id = id,
        element = element,
        side = Agent.ELEMENT_SIDE_CLIENT,
        localOnly = isLocalElement(element),
        owner = owner,
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
---@return string|nil id
---@return string|nil error
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
---@return AgentRegistryEntry|nil entry
---@return table|nil errorInfo
function Agent.getElement(id, options)
    options = type(options) == "table" and options or {}

    local element, entry, err, currentStartupAt = Agent.resolveElement(id)
    if err == "staleId" then
        return nil, { error = err, currentStartupAt = currentStartupAt }
    end
    if err == "notFound" then
        return nil, { error = err }
    end
    if err == "elementDestroyed" then
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
---@return AgentRegistryEntry[] entries
function Agent.listElements(filters)
    filters = type(filters) == "table" and filters or {}
    local results = {}

    if not Agent.registry then
        return results
    end

    for _, entry in pairs(Agent.registry.byId) do
        if Agent.matchesElementFilters(entry, filters) then
            results[#results + 1] = Agent.serializeEntry(entry)
        end
    end

    table.sort(results, function(a, b)
        return (a.createdAt or 0) < (b.createdAt or 0)
    end)

    return results
end

---@param id string
---@return boolean success
---@return string|nil error
function Agent.releaseElement(id)
    local valid, parsedOrErr = Agent.validateElementId(id)
    if not valid then
        return false, type(parsedOrErr) == "string" and parsedOrErr or "invalidId"
    end

    local entry = Agent.registry and Agent.registry.byId[id]
    if not entry then
        return false, "notFound"
    end

    unregisterEntry(entry)
    return true
end

---@param id string
---@param patch table|nil
---@return boolean success
---@return string|table|nil result
function Agent.setElementMeta(id, patch)
    patch = type(patch) == "table" and patch or {}
    local element, entry, err = Agent.resolveElement(id)
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
---@param ops AgentElementModifyOps|AgentElementModifySet|table|nil
---@return boolean success
---@return string|table|nil result
function Agent.modifyElement(id, ops)
    ops = type(ops) == "table" and ops or {}
    ---@type AgentElementModifySet
    local set = type(ops.set) == "table" and ops.set or ops --[[@as AgentElementModifySet]]

    local element, entry, err = Agent.resolveElement(id)
    if not element or not entry then
        return false, err or "notFound"
    end

    applyCommonModify(element, entry.elementType, set)
    refreshEntryProps(entry)

    return true, Agent.serializeEntry(entry)
end

---@param element element
---@return AgentRegistryEntry|nil entry
function Agent.getRegistryEntryForElement(element)
    if not Agent.registry or not isElement(element) then
        return nil
    end

    return Agent.registry.byElement[element]
end

---@return AgentRegistryEntry[] entries
function Agent.exportRegistrySnapshot()
    return Agent.listElements({})
end

addEventHandler("onClientElementDestroy", root, function()
    if not Agent.registry then
        return
    end

    local entry = Agent.registry.byElement[source]
    if entry then
        unregisterEntry(entry)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    Agent.registry = nil
end)
