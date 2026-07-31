--- Client-side CEGUI tree walker: scans open windows and their widget hierarchies.

---@class Agent
Agent = Agent or {}

Agent.GUI_ELEMENT_TYPES = {
    "gui-window",
    "gui-button",
    "gui-edit",
    "gui-label",
    "gui-memo",
    "gui-gridlist",
    "gui-tabpanel",
    "gui-tab",
    "gui-checkbox",
    "gui-combobox",
    "gui-scrollpane",
    "gui-staticimage",
    "gui-progressbar",
    "gui-radiobutton",
}

Agent.GUI_WALKER_DEFAULT_MAX_DEPTH = 12
Agent.GUI_WALKER_DEFAULT_MAX_NODES = 1500

---@param options AgentGuiScanOptions|table|nil
---@return table normalized normalized scan options
local function normalizeOptions(options)
    options = type(options) == "table" and options or {}
    return {
        windowTitle = options.windowTitle or options.title or options.search,
        openOnly = options.openOnly ~= false,
        visibleOnly = options.visibleOnly,
        maxDepth = tonumber(options.maxDepth) or Agent.GUI_WALKER_DEFAULT_MAX_DEPTH,
        maxNodes = tonumber(options.maxNodes) or Agent.GUI_WALKER_DEFAULT_MAX_NODES,
        flat = options.flat == true,
        trees = options.trees ~= false,
        autoTrack = options.autoTrack == true or options.track == true,
        trackSource = options.trackSource or "guiScan",
        includeAllElements = options.includeAllElements == true,
    }
end

---@param title string|nil
---@param filter string|nil
---@return boolean matches
local function titleMatches(title, filter)
    if type(filter) ~= "string" or filter == "" then
        return true
    end

    title = type(title) == "string" and title or ""
    return title:lower():find(filter:lower(), 1, true) ~= nil
end

---@param element element
---@return string chain human-readable " > "-joined ancestor chain
local function parentChain(element)
    local chain = {}
    local current = element
    local depth = 0

    while isElement(current) and depth < 25 do
        local elementType = getElementType(current)
        local label = elementType

        if elementType == "gui-window" or elementType == "gui-tab" or elementType == "gui-button" or elementType == "gui-label" or elementType == "gui-edit" then
            label = label .. ":" .. tostring(guiGetText(current) or "")
        end

        table.insert(chain, 1, label)

        if elementType == "root" then
            break
        end

        current = getElementParent(current)
        depth = depth + 1
    end

    return table.concat(chain, " > ")
end

---@param element element
---@param elementType string
---@param options table normalized scan options
---@return table item
local function describeGuiElement(element, elementType, options)
    local item = {
        type = elementType,
        mtaHandle = tostring(element),
        localOnly = type(isElementLocal) == "function" and isElementLocal(element) or nil,
        visible = guiGetVisible(element),
        enabled = guiGetEnabled(element),
        alpha = getElementAlpha(element),
        parent = parentChain(element),
    }

    if elementType == "gui-window" or elementType == "gui-button" or elementType == "gui-label" or elementType == "gui-tab" or elementType == "gui-edit" or elementType == "gui-memo" then
        item.text = guiGetText(element)
    end

    if elementType == "gui-gridlist" then
        item.rowCount = guiGridListGetRowCount(element)
        item.columnCount = guiGridListGetColumnCount(element)
    end

    if options.autoTrack and type(Agent.trackElement) == "function" then
        local agentId = Agent.trackElement(element, {
            source = options.trackSource,
            label = item.text,
            meta = {
                parent = item.parent,
                guiType = elementType,
            },
        })
        if agentId then
            item.agentId = agentId
        end
    end

    return item
end

---@param element element
---@param depth integer
---@param options table normalized scan options
---@param state table mutable `{ count, truncated }` accumulator shared across recursive calls
---@return table|nil node
local function buildGuiTree(element, depth, options, state)
    if not isElement(element) or depth > options.maxDepth then
        return nil
    end

    state.count = state.count + 1
    if state.count > options.maxNodes then
        state.truncated = true
        return {
            truncated = true,
            reason = "maxNodes",
            depth = depth,
        }
    end

    local elementType = getElementType(element)
    local node = describeGuiElement(element, elementType, options)
    node.depth = depth
    node.children = {}

    local children = getElementChildren(element)
    if type(children) ~= "table" then
        node.childCount = 0
        return node
    end

    node.childCount = #children

    for index = 1, #children do
        local child = children[index]
        if isElement(child) then
            node.children[index] = buildGuiTree(child, depth + 1, options, state)
            if state.truncated then
                break
            end
        end
    end

    return node
end

---@param elements table[] list of items produced by `describeGuiElement`
---@return table<string, integer> byType count of elements per `type`
local function summarizeByType(elements)
    local byType = {}
    for i = 1, #elements do
        local elementType = elements[i].type
        byType[elementType] = (byType[elementType] or 0) + 1
    end
    return byType
end

---@param options table normalized scan options
---@return table[] elements
local function collectGuiElements(options)
    local elements = {}

    for i = 1, #Agent.GUI_ELEMENT_TYPES do
        local elementType = Agent.GUI_ELEMENT_TYPES[i]
        for _, element in ipairs(getElementsByType(elementType)) do
            if isElement(element) then
                local item = describeGuiElement(element, elementType, options)
                if options.visibleOnly ~= true or item.visible then
                    elements[#elements + 1] = item
                end
            end
        end
    end

    return elements
end

---@param element element
---@param options table normalized scan options
---@return table window
local function describeWindow(element, options)
    local title = guiGetText(element) or ""
    local visible = guiGetVisible(element)
    local children = getElementChildren(element)
    local childCount = type(children) == "table" and #children or 0

    local window = {
        title = title,
        mtaHandle = tostring(element),
        visible = visible,
        enabled = guiGetEnabled(element),
        localOnly = type(isElementLocal) == "function" and isElementLocal(element) or nil,
        childCount = childCount,
        parent = parentChain(element),
    }

    if options.autoTrack and type(Agent.trackElement) == "function" then
        local agentId = Agent.trackElement(element, {
            source = options.trackSource,
            label = title,
            meta = { guiType = "gui-window" },
        })
        if agentId then
            window.agentId = agentId
        end
    end

    return window
end

---@param options AgentGuiScanOptions|table|nil
---@return table result GUI scan snapshot (windows, openWindows, trees, byType stats)
function Agent.scanGui(options)
    options = normalizeOptions(options)

    local allElements = collectGuiElements({ autoTrack = false })
    local windows = {}
    local openWindows = {}
    local trees = {}

    for _, element in ipairs(getElementsByType("gui-window")) do
        if not isElement(element) then
        else
            local window = describeWindow(element, options)
            local matchesFilter = titleMatches(window.title, options.windowTitle)

            if matchesFilter then
                windows[#windows + 1] = window
                if window.visible then
                    openWindows[#openWindows + 1] = window
                end

                local shouldTree = options.trees and (not options.openOnly or window.visible)
                if shouldTree and matchesFilter then
                    local state = { count = 0, truncated = false }
                    local tree = buildGuiTree(element, 0, options, state)
                    trees[#trees + 1] = {
                        title = window.title,
                        visible = window.visible,
                        mtaHandle = window.mtaHandle,
                        agentId = window.agentId,
                        nodeCount = state.count,
                        truncated = state.truncated,
                        tree = tree,
                    }
                end
            end
        end
    end

    table.sort(windows, function(a, b)
        if a.visible ~= b.visible then
            return a.visible
        end
        return (a.title or "") < (b.title or "")
    end)

    local trackedElements = options.autoTrack and collectGuiElements(options) or allElements
    local result = {
        side = Agent.ELEMENT_SIDE_CLIENT,
        startupAt = Agent.registry and Agent.registry.startupAt or nil,
        filters = {
            windowTitle = options.windowTitle,
            openOnly = options.openOnly,
            visibleOnly = options.visibleOnly,
        },
        windowCount = #windows,
        openWindowCount = #openWindows,
        totalGuiElements = #allElements,
        byType = summarizeByType(allElements),
        windows = windows,
        openWindows = openWindows,
        trees = trees,
    }

    if options.includeAllElements or options.flat then
        result.elements = trackedElements
        result.byTypeFiltered = summarizeByType(trackedElements)
    end

    return result
end
