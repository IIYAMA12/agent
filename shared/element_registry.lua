--- Shared element registry: id generation/validation and MTA handle lookup helpers used by both server and client.

---@class Agent
Agent = Agent or {}

Agent.ELEMENT_SIDE_SERVER = "server"
Agent.ELEMENT_SIDE_CLIENT = "client"

--- Initializes (or resets) the element registry for this side.
---@param startupAt integer|nil Epoch timestamp used to namespace ids for this process run; defaults to the current real time.
---@param side "server"|"client"|nil Defaults to Agent.ELEMENT_SIDE_SERVER.
function Agent.initRegistry(startupAt, side)
    local byElement = {}
    setmetatable(byElement, { __mode = "k" })

    Agent.registry = {
        startupAt = startupAt or getRealTime().timestamp,
        side = side or Agent.ELEMENT_SIDE_SERVER,
        seq = 0,
        byElement = byElement,
        byId = {},
    }
end

--- Generates a new unique registry id for the given side.
---@param side "server"|"client"|nil Defaults to server prefix unless Agent.ELEMENT_SIDE_CLIENT.
---@return string|nil id
---@return string|nil err
function Agent.makeElementId(side)
    if not Agent.registry then
        return nil, "Registry not initialized"
    end

    Agent.registry.seq = Agent.registry.seq + 1
    local prefix = side == Agent.ELEMENT_SIDE_CLIENT and "c" or "s"
    return string.format("%s-%d-%d", prefix, Agent.registry.startupAt, Agent.registry.seq)
end

--- Parses a registry id string into its side/startupAt/seq components.
---@param id string
---@return AgentParsedElementId|nil parsed
function Agent.parseElementId(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end

    local sidePrefix, startupAt, seq = id:match("^([sc])%-(%d+)%-(%d+)$")
    if not sidePrefix then
        return nil
    end

    return {
        side = sidePrefix == "c" and Agent.ELEMENT_SIDE_CLIENT or Agent.ELEMENT_SIDE_SERVER,
        startupAt = tonumber(startupAt),
        seq = tonumber(seq),
    }
end

--- Validates that a registry id is well-formed and belongs to the current process run.
---@param id string
---@return boolean ok
---@return AgentParsedElementId|string|nil result
---@return integer|nil currentStartupAt
function Agent.validateElementId(id)
    if not Agent.registry then
        return false, "Registry not initialized"
    end

    local parsed = Agent.parseElementId(id)
    if not parsed then
        return false, "invalidId"
    end

    if parsed.startupAt ~= Agent.registry.startupAt then
        return false, "staleId", Agent.registry.startupAt
    end

    return true, parsed
end

--- Converts a registry entry into a plain, JSON-safe table (drops the live element reference).
---@param entry AgentRegistryEntry|table
---@return table|nil
function Agent.serializeEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    return {
        id = entry.id,
        side = entry.side,
        localOnly = entry.localOnly == true,
        owner = entry.owner,
        elementType = entry.elementType,
        mtaHandle = entry.mtaHandle,
        startupAt = entry.startupAt,
        createdAt = entry.createdAt,
        lastSeenAt = entry.lastSeenAt,
        label = entry.label,
        meta = entry.meta or {},
        props = entry.props or {},
        source = entry.source,
        alive = entry.alive ~= false,
    }
end

--- Checks whether a registry entry matches the given filters.
---@param entry AgentRegistryEntry|table
---@param filters AgentElementFilters|table|nil
---@return boolean matches
function Agent.matchesElementFilters(entry, filters)
    if type(entry) ~= "table" then
        return false
    end

    filters = type(filters) == "table" and filters or {}

    if filters.alive ~= nil and (entry.alive ~= false) ~= (filters.alive == true) then
        return false
    end

    if filters.side and entry.side ~= filters.side then
        return false
    end

    if filters.localOnly ~= nil and (entry.localOnly == true) ~= (filters.localOnly == true) then
        return false
    end

    if filters.owner and entry.owner ~= filters.owner then
        return false
    end

    if filters.elementType and entry.elementType ~= filters.elementType then
        return false
    end

    if filters.label and entry.label ~= filters.label then
        return false
    end

    if filters.source and entry.source ~= filters.source then
        return false
    end

    return true
end

--- Finds a live element in the registry whose MTA handle string matches.
---@param mtaHandle string
---@return element|nil
function Agent.findElementByMtaHandleInRegistry(mtaHandle)
    if type(mtaHandle) ~= "string" or mtaHandle == "" or not Agent.registry then
        return nil
    end

    for _, entry in pairs(Agent.registry.byId) do
        if entry.mtaHandle == mtaHandle and entry.alive ~= false and isElement(entry.element) then
            return entry.element
        end
    end

    return nil
end

--- Searches a parent element's descendants (up to maxDepth) for a matching MTA handle string.
---@param mtaHandle string
---@param parent element
---@param maxDepth integer|nil Defaults to 1 (direct children only).
---@return element|nil
function Agent.findElementByMtaHandleUnderParent(mtaHandle, parent, maxDepth)
    if type(mtaHandle) ~= "string" or mtaHandle == "" or not isElement(parent) then
        return nil
    end

    maxDepth = tonumber(maxDepth) or 1

    --- Recursively scans children of `element` for a matching handle.
    ---@param element element
    ---@param depth integer
    ---@return element|nil
    local function scan(element, depth)
        if not isElement(element) or depth > maxDepth then
            return nil
        end

        local children = getElementChildren(element)
        if type(children) ~= "table" then
            return nil
        end

        for i = 1, #children do
            local child = children[i]
            if isElement(child) and tostring(child) == mtaHandle then
                return child
            end
        end

        if maxDepth > 1 then
            for i = 1, #children do
                local child = children[i]
                if isElement(child) then
                    local found = scan(child, depth + 1)
                    if found then
                        return found
                    end
                end
            end
        end

        return nil
    end

    return scan(parent, 1)
end

--- Resolves the parent element referenced by a track/lookup options table.
---@param opts AgentTrackElementOpts|table|nil
---@return element|nil
function Agent.resolveParentElementForHandle(opts)
    opts = type(opts) == "table" and opts or {}

    if isElement(opts.parentElement) then
        return opts.parentElement
    end

    if isElement(opts.parent) then
        return opts.parent
    end

    if type(opts.parentMtaHandle) ~= "string" or opts.parentMtaHandle == "" then
        return nil
    end

    local parent = Agent.findElementByMtaHandleInRegistry(opts.parentMtaHandle)
    if parent then
        return parent
    end

    return Agent.findElementByMtaHandle(opts.parentMtaHandle, {
        elementType = opts.parentElementType,
    })
end

--- Resolves a live element for an MTA handle string, using the registry, an optional parent scope, or a global element-type scan.
---@param mtaHandle string
---@param optsOrType AgentTrackElementOpts|string|nil Either an options table or a shorthand elementType string.
---@return element|nil
function Agent.findElementByMtaHandle(mtaHandle, optsOrType)
    if type(mtaHandle) ~= "string" or mtaHandle == "" then
        return nil
    end

    local opts = {}
    if type(optsOrType) == "string" then
        opts.elementType = optsOrType
    elseif type(optsOrType) == "table" then
        opts = optsOrType
    end

    local fromRegistry = Agent.findElementByMtaHandleInRegistry(mtaHandle)
    if fromRegistry then
        return fromRegistry
    end

    local parent = Agent.resolveParentElementForHandle(opts)
    if parent then
        local underParent = Agent.findElementByMtaHandleUnderParent(
            mtaHandle,
            parent,
            opts.maxDepth or opts.parentMaxDepth or 1
        )
        if underParent then
            return underParent
        end
    end

    if opts.elementType and type(opts.elementType) == "string" then
        for _, element in ipairs(getElementsByType(opts.elementType)) do
            if tostring(element) == mtaHandle then
                return element
            end
        end
        return nil
    end

    local types = Agent.WALKER_HANDLE_TYPES or Agent.NEARBY_DEFAULT_TYPES
    for i = 1, #types do
        for _, element in ipairs(getElementsByType(types[i])) do
            if tostring(element) == mtaHandle then
                return element
            end
        end
    end

    return nil
end

--- Tracks an element in the registry if the caller opted in via `opts.autoTrack`.
---@param element element
---@param opts AgentAutoTrackOpts|table|nil
---@return string|nil id
---@return string|nil err
function Agent.maybeAutoTrackElement(element, opts)
    if not opts or opts.autoTrack ~= true then
        return nil
    end

    if type(Agent.trackElement) ~= "function" then
        return nil
    end

    local trackOpts = {
        label = opts.trackLabel,
        meta = opts.trackMeta,
        source = opts.trackSource or opts.source or "autoTrack",
    }

    local id, err = Agent.trackElement(element, trackOpts)
    if not id then
        return nil, err
    end

    return id
end

--- Attaches an `agentId` field to a props table when auto-tracking is enabled.
---@param props table
---@param element element
---@param opts AgentAutoTrackOpts|table|nil
---@return table props
function Agent.attachAgentIdToProps(props, element, opts)
    if type(props) ~= "table" then
        return props
    end

    local agentId = Agent.maybeAutoTrackElement(element, opts)
    if agentId then
        props.agentId = agentId
    end

    return props
end

--- Normalizes the requested element type(s) from nearby/discovery options into a list.
---@param options AgentNearbyOptions|table|nil
---@return string[] types
function Agent.normalizeNearbyTypes(options)
    if type(options) ~= "table" then
        return Agent.NEARBY_DEFAULT_TYPES or { "vehicle", "player", "ped", "object", "pickup", "marker" }
    end

    if type(options.types) == "table" and #options.types > 0 then
        return options.types
    end

    if type(options.type) == "string" and options.type ~= "" and options.type ~= "*" then
        return { options.type }
    end

    return Agent.NEARBY_DEFAULT_TYPES or { "vehicle", "player", "ped", "object", "pickup", "marker" }
end
