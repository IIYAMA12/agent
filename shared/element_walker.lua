--- Shared element tree walker: describes resource/element trees for discovery, with optional auto-tracking and flattening.

---@class Agent
Agent = Agent or {}

Agent.WALKER_DEFAULT_MAX_DEPTH = 8
Agent.WALKER_DEFAULT_MAX_NODES = 500
Agent.WALKER_LARGE_MAP_THRESHOLD = 100
Agent.WALKER_DEFAULT_MAP_CHILD_LIMIT = 20
Agent.WALKER_DEFAULT_AUTO_TRACK_CHILD_LIMIT = 10
Agent.WALKER_HANDLE_TYPES = {
    "vehicle",
    "player",
    "ped",
    "object",
    "pickup",
    "marker",
    "blip",
    "colshape",
    "comElement",
}

--- Returns true if `element` is a valid MTA element.
---@param element any
---@return boolean
local function isWalkerElement(element)
    return isElement(element)
end

--- Resolves the resource name that owns a given resource-root element.
---@param element element
---@return string|nil
function Agent.resolveResourceNameFromElement(element)
    if not isWalkerElement(element) or getElementType(element) ~= "resource" then
        return nil
    end

    local elementId = getElementID(element)
    if type(elementId) == "string" and elementId ~= "" then
        return elementId
    end

    if type(getResources) == "function" and type(getResourceRootElement) == "function" then
        for _, resourceElement in ipairs(getResources()) do
            if getResourceRootElement(resourceElement) == element then
                return getResourceName(resourceElement)
            end
        end
    end

    return nil
end

--- Resolves the root element to start walking from, based on resourceName/rootId/root options.
---@param options AgentWalkOptions|table|nil
---@return element|nil root
---@return string|nil err
function Agent.resolveWalkRoot(options)
    options = type(options) == "table" and options or {}

    if type(options.resourceName) == "string" and options.resourceName ~= "" then
        if type(getResourceFromName) == "function" and type(getResourceRootElement) == "function" then
            local resourceElement = getResourceFromName(options.resourceName)
            if resourceElement then
                local rootElement = getResourceRootElement(resourceElement)
                if isWalkerElement(rootElement) then
                    return rootElement
                end
            end
        end

        if type(getElementByID) == "function" then
            local byId = getElementByID(options.resourceName)
            if isWalkerElement(byId) then
                return byId
            end
        end

        return nil, "Resource not found: " .. options.resourceName
    end

    if type(options.rootId) == "string" and options.rootId ~= "" and type(getElementByID) == "function" then
        local element = getElementByID(options.rootId)
        if isWalkerElement(element) then
            return element
        end
        return nil, "Element id not found: " .. options.rootId
    end

    if isWalkerElement(options.root) then
        return options.root
    end

    return getRootElement()
end

--- Summarizes the direct children of an element by count and type.
---@param element element
---@return { total: integer, byType: table<string, integer> }
local function summarizeDirectChildren(element)
    local children = getElementChildren(element)
    if type(children) ~= "table" then
        return { total = 0, byType = {} }
    end

    local byType = {}
    for i = 1, #children do
        local child = children[i]
        if isWalkerElement(child) then
            local childType = getElementType(child)
            byType[childType] = (byType[childType] or 0) + 1
        end
    end

    return { total = #children, byType = byType }
end

--- Returns true if the walk options request auto-tracking of visited elements.
---@param options AgentWalkOptions|table|nil
---@return boolean
local function shouldAutoTrack(options)
    return type(options) == "table" and (options.autoTrack == true or options.track == true)
end

--- Returns true if the walk options request auto-tracking of child stub elements too.
---@param options AgentWalkOptions|table|nil
---@return boolean
local function shouldAutoTrackChildren(options)
    return type(options) == "table" and shouldAutoTrack(options) and options.autoTrackChildren == true
end

--- Tracks `element` in the registry when auto-tracking is enabled for this walk.
---@param element element
---@param options AgentWalkOptions|table|nil
---@param meta table|nil
---@return string|nil agentId
local function trackWalkerElement(element, options, meta)
    if not shouldAutoTrack(options) or type(Agent.trackElement) ~= "function" or not isWalkerElement(element) then
        return nil
    end

    meta = type(meta) == "table" and meta or {}
    return Agent.trackElement(element, {
        source = (options and options.trackSource) or "walker",
        meta = meta,
    })
end

--- Tracks `element` and attaches the resulting agentId onto `node.agentId` when tracking succeeds.
---@param node table
---@param element element
---@param options AgentWalkOptions|table|nil
---@param meta table|nil
---@return table node
local function attachTrackedAgentId(node, element, options, meta)
    if type(node) ~= "table" then
        return node
    end

    local agentId = trackWalkerElement(element, options, meta)
    if agentId then
        node.agentId = agentId
    end

    return node
end

--- Builds lightweight stub descriptions (and optional truncation marker) for an element's direct children.
---@param element element
---@param limit integer|nil Defaults to Agent.WALKER_DEFAULT_MAP_CHILD_LIMIT.
---@param options AgentWalkOptions|table|nil
---@param trackContext table|nil Context (resourceName/mapName/role/path) used when auto-tracking children.
---@return table[] stubs
local function listDirectChildStubs(element, limit, options, trackContext)
    limit = tonumber(limit) or Agent.WALKER_DEFAULT_MAP_CHILD_LIMIT
    options = type(options) == "table" and options or {}
    trackContext = type(trackContext) == "table" and trackContext or {}

    local children = getElementChildren(element)
    if type(children) ~= "table" then
        return {}
    end

    local trackChildLimit = math.min(
        limit,
        tonumber(options.autoTrackChildLimit) or Agent.WALKER_DEFAULT_AUTO_TRACK_CHILD_LIMIT
    )
    local stubs = {}

    for index = 1, math.min(#children, limit) do
        local child = children[index]
        if isWalkerElement(child) then
            local childType = getElementType(child)
            local stub = {
                index = index,
                elementType = childType,
                mtaHandle = tostring(child),
                elementId = getElementID(child),
            }

            if childType == "resource" then
                stub.resourceName = Agent.resolveResourceNameFromElement(child)
            end

            local nested = getElementChildren(child)
            if type(nested) == "table" then
                stub.childCount = #nested
            end

            if shouldAutoTrackChildren(options) and index <= trackChildLimit then
                attachTrackedAgentId(stub, child, options, {
                    resourceName = trackContext.resourceName,
                    mapName = trackContext.mapName,
                    role = trackContext.role,
                    path = (trackContext.path or "children") .. "/" .. index,
                })
            end

            stubs[#stubs + 1] = stub
        end
    end

    if #children > limit then
        stubs[#stubs + 1] = {
            truncated = true,
            omitted = #children - limit,
            totalChildren = #children,
        }
    end

    return stubs
end

--- Describes a resource map root element (e.g. "dynamic" or a named map), with optional child listing.
---@param element element
---@param mapName string|nil Defaults to the element's id, or "unknown".
---@param options AgentWalkOptions|table|nil
---@param trackContext table|nil Context (resourceName) used when auto-tracking.
---@return table|nil node
local function describeResourceMapRoot(element, mapName, options, trackContext)
    if not isWalkerElement(element) then
        return nil
    end

    options = type(options) == "table" and options or {}
    trackContext = type(trackContext) == "table" and trackContext or {}

    mapName = mapName or getElementID(element) or "unknown"
    local summary = summarizeDirectChildren(element)
    local role = mapName == "dynamic" and "dynamicElementRoot" or "resourceMapRoot"
    local node = {
        role = role,
        mapName = mapName,
        elementType = getElementType(element),
        mtaHandle = tostring(element),
        elementId = getElementID(element),
        childCount = summary.total,
        childSummary = summary.byType,
    }

    if summary.total >= Agent.WALKER_LARGE_MAP_THRESHOLD then
        node.largeMap = true
        node.note = "Map has many direct children; only summaries tracked by default. Use listMapChildren with a small limit to sample."
    end

    if options.listMapChildren == true then
        node.children = listDirectChildStubs(
            element,
            options.mapChildLimit,
            options,
            {
                resourceName = trackContext.resourceName,
                mapName = mapName,
                role = role,
                path = role .. "/" .. mapName,
            }
        )
    end

    attachTrackedAgentId(node, element, options, {
        resourceName = trackContext.resourceName,
        mapName = mapName,
        role = role,
        path = trackContext.resourceName and (trackContext.resourceName .. "/" .. role) or role,
    })

    return node
end

--- Lists resources (optionally filtered by name/state/query) with their root/dynamic/map element summaries.
---@param options AgentWalkOptions|table|nil
---@return boolean ok
---@return table result
function Agent.walkResourceTops(options)
    options = type(options) == "table" and options or {}
    local query = options.query or options.q or options.resourceName or ""
    query = tostring(query):lower()
    local stateFilter = options.state
    if stateFilter == nil and options.runningOnly ~= false then
        stateFilter = "running"
    end
    local limit = tonumber(options.limit) or 50
    if limit < 1 then
        limit = 50
    end

    local resources = {}
    local matchedTotal = 0
    local tracked = { roots = 0, children = 0, total = 0 }

    --- Recursively counts how many nodes in `node` (and its children) received an agentId.
    ---@param node table|nil
    local function countTracked(node)
        if type(node) ~= "table" then
            return
        end
        if node.agentId then
            if node.role == "resourceRoot" or node.role == "dynamicElementRoot" or node.role == "resourceMapRoot" then
                tracked.roots = tracked.roots + 1
            else
                tracked.children = tracked.children + 1
            end
            tracked.total = tracked.total + 1
        end
        if type(node.children) == "table" then
            for i = 1, #node.children do
                countTracked(node.children[i])
            end
        end
    end

    for _, resourceElement in ipairs(getResources()) do
        local name = getResourceName(resourceElement)
        local state = getResourceState(resourceElement)

        if options.resourceName and name ~= options.resourceName then
        elseif stateFilter and state ~= stateFilter then
        elseif query ~= "" and not string.lower(name):find(query, 1, true) then
        else
            matchedTotal = matchedTotal + 1

            local entry = {
                name = name,
                state = state,
            }

            local resourceRoot = type(getResourceRootElement) == "function"
                and getResourceRootElement(resourceElement)
                or nil

            if isWalkerElement(resourceRoot) then
                ---@cast resourceRoot element
                local rootChildren = getElementChildren(resourceRoot)
                entry.resourceRoot = {
                    role = "resourceRoot",
                    elementType = getElementType(resourceRoot),
                    mtaHandle = tostring(resourceRoot),
                    elementId = getElementID(resourceRoot),
                    childCount = type(rootChildren) == "table" and #rootChildren or 0,
                }
                attachTrackedAgentId(entry.resourceRoot, resourceRoot, options, {
                    resourceName = name,
                    role = "resourceRoot",
                    path = name .. "/resourceRoot",
                })
            end

            if state == "running" then
                local dynamicRoot = type(getResourceDynamicElementRoot) == "function"
                    and getResourceDynamicElementRoot(resourceElement)
                    or nil

                if isWalkerElement(dynamicRoot) then
                    ---@cast dynamicRoot element
                    entry.dynamicElementRoot = describeResourceMapRoot(dynamicRoot, "dynamic", options, {
                        resourceName = name,
                    })
                end

                entry.mapRoots = {}
                if isWalkerElement(resourceRoot) then
                    local rootChildren = getElementChildren(resourceRoot)
                    if type(rootChildren) == "table" then
                        for mapIndex = 1, #rootChildren do
                            local child = rootChildren[mapIndex]
                            if isWalkerElement(child) and getElementType(child) == "map" then
                                local mapId = getElementID(child) or ("map-" .. mapIndex)
                                if mapId ~= "dynamic" then
                                    entry.mapRoots[#entry.mapRoots + 1] =
                                        describeResourceMapRoot(child, mapId, options, {
                                            resourceName = name,
                                        })
                                end
                            end
                        end
                    end
                end
            end

            countTracked(entry.resourceRoot)
            countTracked(entry.dynamicElementRoot)
            if type(entry.mapRoots) == "table" then
                for mapIndex = 1, #entry.mapRoots do
                    countTracked(entry.mapRoots[mapIndex])
                end
            end

            resources[#resources + 1] = entry
        end
    end

    table.sort(resources, function(a, b)
        return a.name < b.name
    end)

    local trimmed = {}
    for i = 1, math.min(#resources, limit) do
        trimmed[i] = resources[i]
    end

    return true, {
        mode = "resourceTops",
        side = Agent.registry and Agent.registry.side or "server",
        query = options.query or options.q or options.resourceName or "",
        state = stateFilter,
        count = #trimmed,
        matchedTotal = matchedTotal,
        total = #getResources(),
        limit = limit,
        autoTrack = shouldAutoTrack(options),
        autoTrackChildren = shouldAutoTrackChildren(options),
        tracked = tracked,
        resources = trimmed,
    }
end

--- Recursively describes an element and its children as an AgentWalkerNode tree, honoring depth/node limits.
---@param element element
---@param options AgentWalkOptions|table|nil
---@param depth integer|nil Defaults to 0.
---@param path string|nil Defaults to "root".
---@param state { count: integer, truncated: boolean }|nil Shared traversal state; created if omitted.
---@return AgentWalkerNode|nil
function Agent.describeWalkerNode(element, options, depth, path, state)
    if not isWalkerElement(element) then
        return nil
    end

    options = type(options) == "table" and options or {}
    depth = depth or 0
    path = path or "root"
    state = state or { count = 0, truncated = false }

    state.count = state.count + 1
    local maxNodes = tonumber(options.maxNodes) or Agent.WALKER_DEFAULT_MAX_NODES
    if state.count > maxNodes then
        state.truncated = true
        return { truncated = true, reason = "maxNodes", path = path }
    end

    local elementType = getElementType(element)
    local node = {
        elementType = elementType,
        mtaHandle = tostring(element),
        elementId = getElementID(element),
        depth = depth,
        path = path,
    }

    if elementType == "resource" then
        node.resourceName = Agent.resolveResourceNameFromElement(element)
        if options.resourceState and type(getResourceFromName) == "function" and node.resourceName then
            local resourceElement = getResourceFromName(node.resourceName)
            if resourceElement and type(getResourceState) == "function" then
                node.resourceState = getResourceState(resourceElement)
            end
        end
    end

    if type(isElementLocal) == "function" then
        node.localOnly = isElementLocal(element) == true
    end

    if options.track == true or options.autoTrack == true then
        if type(Agent.trackElement) == "function" then
            local agentId = Agent.trackElement(element, {
                source = options.trackSource or "walker",
                meta = {
                    path = path,
                    resourceName = node.resourceName,
                },
            })
            if agentId then
                node.agentId = agentId
            end
        end
    end

    local maxDepth = tonumber(options.maxDepth) or Agent.WALKER_DEFAULT_MAX_DEPTH
    local childType = options.childType
    local children = getElementChildren(element, childType)
    if type(children) ~= "table" then
        node.childCount = 0
        return node
    end

    node.childCount = #children

    if depth >= maxDepth then
        node.depthLimit = true
        return node
    end

    if #children == 0 then
        return node
    end

    node.children = {}
    for index = 1, #children do
        local child = children[index]
        if isWalkerElement(child) then
            node.children[index] = Agent.describeWalkerNode(
                child,
                options,
                depth + 1,
                path .. "/" .. index,
                state
            )
            if state.truncated then
                break
            end
        end
    end

    return node
end

--- Recursively counts the (non-truncated) nodes in an AgentWalkerNode tree.
---@param node AgentWalkerNode|table|nil
---@return integer count
function Agent.countWalkerNodes(node)
    if type(node) ~= "table" or node.truncated then
        return 0
    end

    local count = 1
    if type(node.children) == "table" then
        for i = 1, #node.children do
            count = count + Agent.countWalkerNodes(node.children[i])
        end
    end
    return count
end

--- Flattens an AgentWalkerNode tree into a flat list, optionally filtered by elementType/resourceName.
---@param node AgentWalkerNode|table|nil
---@param list table[]|nil Accumulator list; created if omitted.
---@param filters { elementType?: string, resourceName?: string, resourcesOnly?: boolean }|nil
---@return table[] list
function Agent.flattenWalkerTree(node, list, filters)
    list = list or {}
    filters = type(filters) == "table" and filters or {}

    if type(node) ~= "table" or node.truncated then
        return list
    end

    local include = true
    if filters.elementType and node.elementType ~= filters.elementType then
        include = false
    end
    if filters.resourceName and node.resourceName ~= filters.resourceName then
        include = false
    end
    if filters.resourcesOnly and node.elementType ~= "resource" and not node.resourceName then
        include = false
    end

    if include then
        list[#list + 1] = {
            path = node.path,
            depth = node.depth,
            elementType = node.elementType,
            mtaHandle = node.mtaHandle,
            elementId = node.elementId,
            resourceName = node.resourceName,
            resourceState = node.resourceState,
            localOnly = node.localOnly,
            agentId = node.agentId,
            childCount = node.childCount,
        }
    end

    if type(node.children) == "table" then
        for i = 1, #node.children do
            Agent.flattenWalkerTree(node.children[i], list, filters)
        end
    end

    return list
end

--- Summarizes an AgentWalkerNode tree: total nodes, counts by element type, max depth, and resource list.
---@param node AgentWalkerNode|table|nil
---@return { nodes: integer, byType: table<string, integer>, resources: table[], maxDepth: integer } summary
function Agent.summarizeWalkerTree(node)
    local summary = {
        nodes = 0,
        byType = {},
        resources = {},
        maxDepth = 0,
    }

    --- Recursively walks `entry` (and its children), accumulating into `summary`.
    ---@param entry AgentWalkerNode|table|nil
    ---@param depth integer
    local function walk(entry, depth)
        if type(entry) ~= "table" or entry.truncated then
            return
        end

        summary.nodes = summary.nodes + 1
        summary.maxDepth = math.max(summary.maxDepth, depth)
        summary.byType[entry.elementType] = (summary.byType[entry.elementType] or 0) + 1

        if entry.elementType == "resource" then
            summary.resources[#summary.resources + 1] = {
                resourceName = entry.resourceName,
                elementId = entry.elementId,
                mtaHandle = entry.mtaHandle,
                resourceState = entry.resourceState,
                childCount = entry.childCount,
                agentId = entry.agentId,
            }
        end

        if type(entry.children) == "table" then
            for i = 1, #entry.children do
                walk(entry.children[i], depth + 1)
            end
        end
    end

    walk(node, (node and node.depth) or 0)
    return summary
end

--- Lists the direct children of the resolved walk root (mode = "roots").
---@param options AgentWalkOptions|table|nil
---@return boolean ok
---@return table|string result Result table on success, error message on failure.
function Agent.listRootChildren(options)
    options = type(options) == "table" and options or {}
    local root, err = Agent.resolveWalkRoot(options)
    if not root then
        return false, err or "Root element unavailable"
    end

    local children = getElementChildren(root, options.childType)
    if type(children) ~= "table" then
        return false, "Could not read root children"
    end

    local results = {}
    for index = 1, #children do
        local child = children[index]
        if isWalkerElement(child) then
            local elementType = getElementType(child)
            if not options.resourcesOnly or elementType == "resource" then
                local entry = {
                    index = index,
                    elementType = elementType,
                    mtaHandle = tostring(child),
                    elementId = getElementID(child),
                    path = "root/" .. index,
                }

                if elementType == "resource" then
                    entry.resourceName = Agent.resolveResourceNameFromElement(child)
                    if options.resourceState and type(getResourceFromName) == "function" and entry.resourceName then
                        local resourceElement = getResourceFromName(entry.resourceName)
                        if resourceElement and type(getResourceState) == "function" then
                            entry.resourceState = getResourceState(resourceElement)
                        end
                    end
                    entry.summary = summarizeDirectChildren(child)
                end

                if type(isElementLocal) == "function" then
                    entry.localOnly = isElementLocal(child) == true
                end

                if options.track == true or options.autoTrack == true then
                    if type(Agent.trackElement) == "function" then
                        entry.agentId = Agent.trackElement(child, {
                            source = options.trackSource or "walker",
                            meta = { path = entry.path, resourceName = entry.resourceName },
                        })
                    end
                end

                results[#results + 1] = entry
            end
        end
    end

    return true, {
        root = {
            elementType = getElementType(root),
            mtaHandle = tostring(root),
            childCount = #children,
        },
        children = results,
    }
end

--- Entry point for element tree walking: dispatches to resourceTops/roots modes or performs a full recursive walk.
---@param options AgentWalkOptions|table|nil
---@return boolean ok
---@return table|string result Result table on success, error message on failure.
function Agent.walkElementTree(options)
    options = type(options) == "table" and options or {}

    if options.mode == "resourceTops" then
        return Agent.walkResourceTops(options)
    end

    if options.mode == "roots" or options.rootsOnly == true then
        return Agent.listRootChildren(options)
    end

    local root, err = Agent.resolveWalkRoot(options)
    if not root then
        return false, err or "Root element unavailable"
    end

    local state = { count = 0, truncated = false }
    local tree = Agent.describeWalkerNode(root, options, 0, "root", state)
    local result = {
        side = Agent.registry and Agent.registry.side or nil,
        startupAt = Agent.registry and Agent.registry.startupAt or nil,
        root = {
            elementType = getElementType(root),
            mtaHandle = tostring(root),
            elementId = getElementID(root),
            resourceName = Agent.resolveResourceNameFromElement(root),
        },
        tree = tree,
        truncated = state.truncated,
        nodeCount = Agent.countWalkerNodes(tree),
        summary = Agent.summarizeWalkerTree(tree),
    }

    if options.flat == true then
        result.flat = Agent.flattenWalkerTree(tree, {}, {
            elementType = options.elementType,
            resourceName = options.resourceName,
            resourcesOnly = options.resourcesOnly,
        })
    end

    return true, result
end
