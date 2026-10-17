--- Client bounding boxes: streamed-in measure, stock catalog scan, custom fetch, wireframe draw.
--- getElementBoundingBox is client-only and returns false until the element is streamed in.
---@class Agent
Agent = Agent or {}

local BATCH_EVENT = "agent:boundingBatch"
local CACHE_REQUEST_EVENT = "agent:boundingCacheRequest"
local KNOWN_EVENT = "agent:boundingKnown"
local CACHE_EVENT = "agent:boundingCache"

local BATCH_SIZE_DEFAULT = 8
local BATCH_SIZE_MAX = 16
local STREAM_WAIT_MS = 100
local STREAM_WAIT_TICKS = 12
local MODEL_ID_MAX = 20000
local VEHICLE_MIN, VEHICLE_MAX = 400, 611
local PED_MIN, PED_MAX = 0, 312

local IGNORE_MATRIX = {
    pickup = true,
}

local BOX_EDGES = {
    { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
    { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

---@type table<string, table>
local defaults = {}
---@type table<string, table>
local custom = {}
---@type table<string, boolean>
local missingKeys = {}

local knownPending = {}
local scan = nil

local draw = {
    pinned = {},
    nearby = nil,
    color = { 0, 200, 220, 180 },
}
local rendering = false
local pendingCacheKeys = {}
local cacheFlushScheduled = false

addEvent(KNOWN_EVENT, true)
addEvent(CACHE_EVENT, true)
addEvent(BATCH_EVENT, true)
addEvent(CACHE_REQUEST_EVENT, true)

---@param elementType string
---@param model integer
---@return string
local function recordKey(elementType, model)
    return tostring(elementType) .. ":" .. tostring(model)
end

---@param value any
---@return number|nil
local function finiteNumber(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return nil
    end
    return n
end

---@param model integer
---@return "vehicle"|"ped"|"object"
local function classifyModel(model)
    if model >= VEHICLE_MIN and model <= VEHICLE_MAX then
        return "vehicle"
    end
    if model >= PED_MIN and model <= PED_MAX then
        return "ped"
    end
    return "object"
end

---@param element element
---@return string
local function catalogType(element)
    local elementType = getElementType(element)
    if elementType == "player" then
        return "ped"
    end
    return elementType
end

---@param entry table
---@param source string|nil
function Agent.rememberBoundingRecord(entry, source)
    if type(entry) ~= "table" then
        return
    end
    local model = tonumber(entry.model)
    local elementType = entry.elementType
    local min = type(entry.min) == "table" and entry.min or nil
    local max = type(entry.max) == "table" and entry.max or nil
    if not model or type(elementType) ~= "string" or not min or not max then
        return
    end
    local minX, minY, minZ = finiteNumber(min.x), finiteNumber(min.y), finiteNumber(min.z)
    local maxX, maxY, maxZ = finiteNumber(max.x), finiteNumber(max.y), finiteNumber(max.z)
    if not minX or not minY or not minZ or not maxX or not maxY or not maxZ then
        return
    end
    local stored = {
        model = model,
        elementType = elementType,
        min = { x = minX, y = minY, z = minZ },
        max = { x = maxX, y = maxY, z = maxZ },
        radius = finiteNumber(entry.radius),
        capturedAt = tonumber(entry.capturedAt),
        source = source or entry.source or "default",
    }
    local key = recordKey(elementType, model)
    if stored.source == "custom" then
        custom[key] = stored
    else
        defaults[key] = stored
    end
    missingKeys[key] = nil
end

---@param records table|nil
local function rememberRecords(records)
    if type(records) ~= "table" then
        return
    end
    for i = 1, #records do
        Agent.rememberBoundingRecord(records[i])
    end
    if #records == 0 then
        for _, entry in pairs(records) do
            if type(entry) == "table" and entry.model then
                Agent.rememberBoundingRecord(entry)
            end
        end
    end
end

---@param element element
---@return number|nil
local function readRadius(element)
    if type(getElementRadius) ~= "function" then
        return nil
    end
    local radius = getElementRadius(element)
    if type(radius) ~= "number" or radius ~= radius then
        return nil
    end
    return radius
end

---@param element element
---@return table|nil measured
---@return string|nil error
local function measureElement(element)
    if not isElement(element) or not isElementStreamedIn(element) then
        return nil, "notStreamedIn"
    end
    local minX, minY, minZ, maxX, maxY, maxZ = getElementBoundingBox(element)
    local radius = readRadius(element)
    if not minX then
        return nil, "noBoundingBox"
    end
    return {
        min = { x = minX, y = minY, z = minZ },
        max = { x = maxX, y = maxY, z = maxZ },
        radius = radius,
    }
end

---@param elementType string
---@param model integer
---@return element|nil
local function spawnTemp(elementType, model)
    local px, py, pz = getElementPosition(localPlayer)
    local element
    local ok = false
    if elementType == "vehicle" then
        ok, element = pcall(createVehicle, model, px, py, pz + 0.2)
    elseif elementType == "ped" then
        ok, element = pcall(createPed, model, px, py, pz + 0.2)
    else
        ok, element = pcall(createObject, model, px, py, pz + 0.2)
    end
    if not ok or not isElement(element) then
        return nil
    end
    setElementDimension(element, getElementDimension(localPlayer))
    setElementInterior(element, getElementInterior(localPlayer))
    setElementAlpha(element, 0)
    setElementCollisionsEnabled(element, false)
    setElementFrozen(element, true)
    if elementType == "vehicle" then
        setVehicleEngineState(element, false)
    end
    return element
end

---@param model integer
---@param elementType string
---@param measured table
---@param source string
---@return table
local function makeEntry(model, elementType, measured, source)
    return {
        model = model,
        elementType = elementType,
        min = measured.min,
        max = measured.max,
        radius = measured.radius,
        source = source,
    }
end

local function destroyWaiting()
    if not scan or type(scan.waiting) ~= "table" then
        return
    end
    for i = 1, #scan.waiting do
        local element = scan.waiting[i].element
        if isElement(element) then
            destroyElement(element)
        end
    end
    scan.waiting = {}
end

---@param entries table|nil
---@param done boolean
---@param stopped boolean
local function emitScan(entries, done, stopped)
    if not scan then
        return
    end
    local deltaScanned = scan.scanned - scan.sentScanned
    local deltaFailed = scan.failed - scan.sentFailed
    local deltaReplaced = scan.skippedReplaced - scan.sentReplaced
    scan.sentScanned = scan.scanned
    scan.sentFailed = scan.failed
    scan.sentReplaced = scan.skippedReplaced
    triggerServerEvent(BATCH_EVENT, resourceRoot, {
        jobId = scan.jobId,
        entries = entries or {},
        scanned = deltaScanned,
        failed = deltaFailed,
        skippedReplaced = deltaReplaced,
        done = done and true or false,
        stopped = stopped and true or false,
        total = scan.total,
    })
    if done or stopped then
        if scan.timer and isTimer(scan.timer) then
            killTimer(scan.timer)
        end
        destroyWaiting()
        scan = nil
    end
end

local function spawnBatch()
    if not scan or scan.cursor > #scan.queue then
        emitScan({}, true, false)
        return
    end

    scan.waiting = {}
    local spawned = 0
    while scan.cursor <= #scan.queue and spawned < scan.batchSize do
        local item = scan.queue[scan.cursor]
        scan.cursor = scan.cursor + 1
        local element = spawnTemp(item.elementType, item.model)
        if not element then
            scan.failed = scan.failed + 1
            scan.scanned = scan.scanned + 1
        else
            scan.waiting[#scan.waiting + 1] = {
                element = element,
                model = item.model,
                elementType = item.elementType,
                ticks = 0,
            }
            spawned = spawned + 1
        end
    end

    if #scan.waiting == 0 then
        if scan.cursor > #scan.queue then
            emitScan({}, true, false)
        end
    end
end

local function pollWaiting()
    if not scan then
        return
    end
    local still = {}
    local entries = {}
    for i = 1, #scan.waiting do
        local item = scan.waiting[i]
        item.ticks = item.ticks + 1
        local streamed = isElement(item.element) and isElementStreamedIn(item.element)
        local giveUp = item.ticks >= STREAM_WAIT_TICKS
        if streamed or giveUp then
            local measured = streamed and measureElement(item.element) or nil
            if measured then
                local entry = makeEntry(item.model, item.elementType, measured, "default")
                defaults[recordKey(item.elementType, item.model)] = entry
                entries[#entries + 1] = entry
            else
                scan.failed = scan.failed + 1
            end
            scan.scanned = scan.scanned + 1
            if isElement(item.element) then
                destroyElement(item.element)
            end
        else
            still[#still + 1] = item
        end
    end
    scan.waiting = still

    if #still == 0 then
        local done = scan.cursor > #scan.queue
        emitScan(entries, done, false)
        if not done and scan then
            spawnBatch()
        end
    elseif #entries > 0 then
        emitScan(entries, false, false)
    end
end

local function tickScan()
    if not scan then
        return
    end
    if #scan.waiting == 0 then
        spawnBatch()
    else
        pollWaiting()
    end
end

---@param id integer
---@return boolean
local function lodExists(id)
    if type(engineGetModelLODDistance) ~= "function" then
        return false
    end
    return type(engineGetModelLODDistance(id)) == "number"
end

--- True when a sample id in the range does not report a LOD distance, so the whole range is walked.
---@param sampleId integer
---@return boolean
local function rangeWithoutLod(sampleId)
    if type(engineGetModelLODDistance) ~= "function" then
        return true
    end
    return type(engineGetModelLODDistance(sampleId)) ~= "number"
end

---@param types string[]
---@param known table
---@param force boolean
---@return table queue
---@return integer skippedReplaced
local function buildQueue(types, known, force)
    local wanted = {}
    for i = 1, #types do
        wanted[types[i]] = true
    end
    local queue = {}
    local skippedReplaced = 0

    local function push(model, elementType)
        if not force and known[elementType] and known[elementType][model] then
            return
        end
        if type(Agent.isModelReplaced) == "function" and Agent.isModelReplaced(model) then
            skippedReplaced = skippedReplaced + 1
            return
        end
        queue[#queue + 1] = { model = model, elementType = elementType }
    end

    if wanted.vehicle then
        local includeAll = rangeWithoutLod(411)
        for id = VEHICLE_MIN, VEHICLE_MAX do
            if includeAll or lodExists(id) then
                push(id, "vehicle")
            end
        end
    end

    if wanted.ped then
        local includeAll = rangeWithoutLod(7)
        for id = PED_MIN, PED_MAX do
            if includeAll or lodExists(id) then
                push(id, "ped")
            end
        end
    end

    if wanted.object and type(engineGetModelLODDistance) == "function" then
        for id = 313, MODEL_ID_MAX do
            local inVehicle = id >= VEHICLE_MIN and id <= VEHICLE_MAX
            local inPed = id >= PED_MIN and id <= PED_MAX
            if not inVehicle and not inPed and lodExists(id) then
                push(id, "object")
            end
        end
    end

    return queue, skippedReplaced
end

---@param payload table
---@return AgentHttpPayload
function Agent.startBoundingScanClient(payload)
    payload = type(payload) == "table" and payload or {}
    local jobId = payload.jobId
    if type(jobId) ~= "string" or jobId == "" then
        return { ok = false, error = "jobId required" }
    end

    if scan then
        destroyWaiting()
        emitScan({}, true, true)
    end

    local types = payload.types
    if type(types) ~= "table" or #types == 0 then
        types = { "object", "vehicle", "ped" }
    end
    local known = knownPending[jobId] or { object = {}, vehicle = {}, ped = {} }
    knownPending[jobId] = nil
    local force = payload.force == true
    local queue, skippedReplaced = buildQueue(types, known, force)
    local batchSize = tonumber(payload.batch) or BATCH_SIZE_DEFAULT
    if batchSize < 1 then batchSize = 1 end
    if batchSize > BATCH_SIZE_MAX then batchSize = BATCH_SIZE_MAX end

    scan = {
        jobId = jobId,
        queue = queue,
        cursor = 1,
        waiting = {},
        batchSize = batchSize,
        total = #queue,
        scanned = 0,
        failed = 0,
        skippedReplaced = skippedReplaced,
        sentScanned = 0,
        sentFailed = 0,
        sentReplaced = 0,
        timer = nil,
    }

    if #queue == 0 then
        emitScan({}, true, false)
        return { ok = true, result = { started = true, jobId = jobId, total = 0 } }
    end

    emitScan({}, false, false)
    scan.timer = setTimer(tickScan, STREAM_WAIT_MS, 0)
    return { ok = true, result = { started = true, jobId = jobId, total = #queue } }
end

---@param payload table|nil
---@return AgentHttpPayload
function Agent.stopBoundingScanClient(payload)
    payload = type(payload) == "table" and payload or {}
    if not scan then
        return { ok = true, result = { stopped = true, active = false } }
    end
    if type(payload.jobId) == "string" and payload.jobId ~= "" and payload.jobId ~= scan.jobId then
        return { ok = true, result = { stopped = false, active = true, jobId = scan.jobId } }
    end
    destroyWaiting()
    emitScan({}, true, true)
    return { ok = true, result = { stopped = true } }
end

---@param payload table
---@return element|nil
---@return string|nil error
local function resolvePayloadElement(payload)
    local agentId = payload.agentId or payload.id
    if type(agentId) == "string" and agentId ~= "" then
        local element, _, err = Agent.resolveElement(agentId)
        if not element then
            return nil, err or "notFound"
        end
        return element
    end
    if type(payload.mtaHandle) == "string" and payload.mtaHandle ~= "" then
        local element = Agent.findElementByMtaHandle(payload.mtaHandle, payload.elementType)
        if not element then
            return nil, "Element not found for handle: " .. payload.mtaHandle
        end
        return element
    end
    return nil
end

---@param model integer
---@param elementType string
---@param requestId string
local function measureModelLater(model, elementType, requestId)
    local element = spawnTemp(elementType, model)
    if not element then
        Agent.replyClientRequest(requestId, {
            ok = false,
            error = "Failed to create a local element for model " .. tostring(model),
            details = { model = model, elementType = elementType },
        })
        return
    end

    local ticks = 0
    local timer
    timer = setTimer(function()
        ticks = ticks + 1
        local streamed = isElement(element) and isElementStreamedIn(element)
        if not streamed and ticks < STREAM_WAIT_TICKS then
            return
        end
        if isTimer(timer) then
            killTimer(timer)
        end
        local measured = streamed and measureElement(element) or nil
        if isElement(element) then
            destroyElement(element)
        end
        if not measured then
            Agent.replyClientRequest(requestId, {
                ok = false,
                error = streamed and "noBoundingBox" or "notStreamedIn",
                details = { model = model, elementType = elementType, streamedIn = streamed and true or false },
            })
            return
        end
        local entry = makeEntry(model, elementType, measured, "custom")
        custom[recordKey(elementType, model)] = entry
        Agent.replyClientRequest(requestId, { ok = true, result = entry })
    end, STREAM_WAIT_MS, STREAM_WAIT_TICKS)
end

---@param payload table
---@return AgentHttpPayload|nil
function Agent.fetchBoundingClient(payload)
    payload = type(payload) == "table" and payload or {}
    rememberRecords(payload.records)

    local hasElementRef = (type(payload.agentId) == "string" and payload.agentId ~= "")
        or (type(payload.id) == "string" and payload.id ~= "")
        or (type(payload.mtaHandle) == "string" and payload.mtaHandle ~= "")

    if hasElementRef then
        local element, err = resolvePayloadElement(payload)
        if not element then
            return { ok = false, error = err or "notFound" }
        end
        local model = getElementModel(element)
        local elementType = catalogType(element)
        if not isElementStreamedIn(element) then
            return {
                ok = false,
                error = "notStreamedIn",
                details = {
                    model = model,
                    elementType = elementType,
                    streamedIn = false,
                },
            }
        end
        local measured, measureErr = measureElement(element)
        if not measured then
            return {
                ok = false,
                error = measureErr or "noBoundingBox",
                details = { model = model, elementType = elementType, streamedIn = true },
            }
        end
        local entry = makeEntry(model, elementType, measured, "custom")
        custom[recordKey(elementType, model)] = entry
        return { ok = true, result = entry }
    end

    local model = tonumber(payload.model)
    if not model then
        return { ok = false, error = "agentId, mtaHandle, or model required" }
    end
    local elementType = payload.elementType
    if elementType ~= "object" and elementType ~= "vehicle" and elementType ~= "ped" then
        elementType = classifyModel(model)
    end
    local requestId = Agent.deferClientResponse()
    if not requestId then
        return { ok = false, error = "Cannot defer client response" }
    end
    measureModelLater(model, elementType, requestId)
    return nil
end

---@param payload table
---@return AgentHttpPayload
function Agent.resolveBoundingClient(payload)
    payload = type(payload) == "table" and payload or {}
    local element, err = resolvePayloadElement(payload)
    if not element then
        return { ok = false, error = err or "notFound" }
    end
    return {
        ok = true,
        result = {
            model = getElementModel(element),
            elementType = catalogType(element),
            streamedIn = isElementStreamedIn(element) and true or false,
            agentId = payload.agentId or payload.id,
            mtaHandle = tostring(element),
        },
    }
end

-- Editor gridlines shift: model bounds are not centered on the element pivot.
-- https://github.com/multitheftauto/mtasa-blue/blob/master/Client/mods/deathmatch/logic/CClientStreamElement.cpp
---@return number minX, number minY, number minZ, number maxX, number maxY, number maxZ
local function applyEditorHalfCenter(minX, minY, minZ, maxX, maxY, maxZ)
    local halfX = (minX + maxX) * 0.25
    local halfY = (minY + maxY) * 0.25
    local halfZ = (minZ + maxZ) * 0.25
    return minX - halfX, minY - halfY, minZ - halfZ, maxX - halfX, maxY - halfY, maxZ - halfZ
end

---@param element element
---@param x number
---@param y number
---@param z number
---@return number, number, number
local function transformCorner(element, x, y, z)
    local elementType = getElementType(element)
    local matrix = (not IGNORE_MATRIX[elementType]) and getElementMatrix(element) or nil
    if type(matrix) ~= "table" then
        local ox, oy, oz = getElementPosition(element)
        return ox + x, oy + y, oz + z
    end
    return x * matrix[1][1] + y * matrix[2][1] + z * matrix[3][1] + matrix[4][1],
        x * matrix[1][2] + y * matrix[2][2] + z * matrix[3][2] + matrix[4][2],
        x * matrix[1][3] + y * matrix[2][3] + z * matrix[3][3] + matrix[4][3]
end

---@param key string
local function requestCacheKey(key)
    if pendingCacheKeys[key] or missingKeys[key] or defaults[key] or custom[key] then
        return
    end
    pendingCacheKeys[key] = true
    if cacheFlushScheduled then
        return
    end
    cacheFlushScheduled = true
    setTimer(function()
        cacheFlushScheduled = false
        local list = {}
        for cacheKey in pairs(pendingCacheKeys) do
            list[#list + 1] = cacheKey
            if #list >= 64 then
                break
            end
        end
        for i = 1, #list do
            pendingCacheKeys[list[i]] = nil
        end
        if #list > 0 then
            triggerServerEvent(CACHE_REQUEST_EVENT, resourceRoot, list)
        end
    end, 50, 1)
end

---@param element element
---@return number|nil minX, number|nil minY, number|nil minZ, number|nil maxX, number|nil maxY, number|nil maxZ
local function rawBoxForElement(element)
    if isElementStreamedIn(element) then
        local minX, minY, minZ, maxX, maxY, maxZ = getElementBoundingBox(element)
        if minX then
            return minX, minY, minZ, maxX, maxY, maxZ
        end
        local radius = readRadius(element)
        if type(radius) == "number" and radius > 0 then
            return -radius, -radius, -radius, radius, radius, radius
        end
    end

    local model = getElementModel(element)
    local elementType = catalogType(element)
    local key = recordKey(elementType, model)
    local entry = custom[key] or defaults[key]
    if not entry then
        requestCacheKey(key)
        return nil
    end
    return entry.min.x, entry.min.y, entry.min.z, entry.max.x, entry.max.y, entry.max.z
end

---@param element element
---@param color table
local function drawElementBox(element, color)
    if not isElement(element) then
        return
    end
    if getElementDimension(element) ~= getElementDimension(localPlayer) then
        return
    end
    local minX, minY, minZ, maxX, maxY, maxZ = rawBoxForElement(element)
    if not minX then
        return
    end
    minX, minY, minZ, maxX, maxY, maxZ = applyEditorHalfCenter(minX, minY, minZ, maxX, maxY, maxZ)
    local function corner(x, y, z)
        local cx, cy, cz = transformCorner(element, x, y, z)
        return { cx, cy, cz }
    end
    local corners = {
        corner(minX, minY, minZ),
        corner(maxX, minY, minZ),
        corner(maxX, maxY, minZ),
        corner(minX, maxY, minZ),
        corner(minX, minY, maxZ),
        corner(maxX, minY, maxZ),
        corner(maxX, maxY, maxZ),
        corner(minX, maxY, maxZ),
    }
    local lineColor = tocolor(color[1] or 0, color[2] or 200, color[3] or 220, color[4] or 180)
    for i = 1, #BOX_EDGES do
        local edge = BOX_EDGES[i]
        local a = corners[edge[1]]
        local b = corners[edge[2]]
        if a and b and a[1] and a[2] and a[3] and b[1] and b[2] and b[3] then
            dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], lineColor, 2)
        end
    end
end

local function collectNearby()
    local spec = draw.nearby
    if not spec then
        return {}
    end
    local px, py, pz = getElementPosition(localPlayer)
    local types = spec.elementType and { spec.elementType } or { "object", "vehicle", "ped" }
    local found = {}
    local dim = getElementDimension(localPlayer)
    for t = 1, #types do
        local list = getElementsWithinRange(px, py, pz, spec.maxDistance, types[t]) or {}
        for i = 1, #list do
            local element = list[i]
            if isElement(element) and isElementStreamedIn(element) and getElementDimension(element) == dim then
                if not spec.model or getElementModel(element) == spec.model then
                    found[#found + 1] = element
                    if #found >= spec.limit then
                        return found
                    end
                end
            end
        end
    end
    return found
end

local function renderBoundingBoxes()
    local color = draw.color
    for _, pin in pairs(draw.pinned) do
        if isElement(pin.element) then
            drawElementBox(pin.element, color)
        end
    end
    local nearby = collectNearby()
    for i = 1, #nearby do
        drawElementBox(nearby[i], color)
    end
end

local function ensureRender()
    if rendering then
        return
    end
    rendering = true
    addEventHandler("onClientRender", root, renderBoundingBoxes)
end

local function stopRenderIfIdle()
    if next(draw.pinned) or draw.nearby then
        return
    end
    if rendering then
        removeEventHandler("onClientRender", root, renderBoundingBoxes)
        rendering = false
    end
end

---@return table
local function drawSnapshot()
    local pinned = {}
    for key, pin in pairs(draw.pinned) do
        local element = pin.element
        pinned[#pinned + 1] = {
            key = key,
            agentId = pin.agentId,
            mtaHandle = pin.mtaHandle,
            model = isElement(element) and getElementModel(element) or nil,
            elementType = isElement(element) and getElementType(element) or nil,
            streamedIn = isElement(element) and isElementStreamedIn(element) or false,
            alive = isElement(element) and true or false,
        }
    end
    return {
        enabled = (#pinned > 0) or draw.nearby ~= nil,
        pinned = pinned,
        nearby = draw.nearby,
        color = { r = draw.color[1], g = draw.color[2], b = draw.color[3], a = draw.color[4] },
    }
end

---@param payload table
---@return AgentHttpPayload
function Agent.drawBoundingClient(payload)
    payload = type(payload) == "table" and payload or {}
    rememberRecords(payload.records)
    local action = payload.action or "start"

    if action == "list" then
        return { ok = true, result = drawSnapshot() }
    end

    if action == "stop" then
        local agentId = payload.agentId or payload.id
        if type(agentId) == "string" and agentId ~= "" then
            draw.pinned[agentId] = nil
        elseif type(payload.mtaHandle) == "string" and payload.mtaHandle ~= "" then
            draw.pinned[payload.mtaHandle] = nil
        else
            draw.pinned = {}
            draw.nearby = nil
        end
        stopRenderIfIdle()
        return { ok = true, result = drawSnapshot() }
    end

    if action ~= "start" then
        return { ok = false, error = "action must be start, stop, or list" }
    end

    if payload.r or payload.g or payload.b or payload.a then
        draw.color = {
            tonumber(payload.r) or draw.color[1],
            tonumber(payload.g) or draw.color[2],
            tonumber(payload.b) or draw.color[3],
            tonumber(payload.a) or draw.color[4],
        }
    end

    local hasElementRef = (type(payload.agentId) == "string" and payload.agentId ~= "")
        or (type(payload.id) == "string" and payload.id ~= "")
        or (type(payload.mtaHandle) == "string" and payload.mtaHandle ~= "")

    if hasElementRef then
        local element, err = resolvePayloadElement(payload)
        if not element then
            return { ok = false, error = err or "notFound" }
        end
        local key = payload.agentId or payload.id or payload.mtaHandle
        draw.pinned[key] = {
            element = element,
            agentId = payload.agentId or payload.id,
            mtaHandle = tostring(element),
        }
    end

    if payload.nearby == true or not hasElementRef then
        local maxDistance = tonumber(payload.maxDistance) or 80
        if maxDistance < 1 then maxDistance = 1 end
        if maxDistance > 500 then maxDistance = 500 end
        local limit = tonumber(payload.limit) or 25
        if limit < 1 then limit = 1 end
        if limit > 100 then limit = 100 end
        local elementType = payload.elementType or payload.type
        if elementType ~= "object" and elementType ~= "vehicle" and elementType ~= "ped" and elementType ~= "pickup" and elementType ~= "player" then
            elementType = nil
        end
        draw.nearby = {
            elementType = elementType,
            model = tonumber(payload.model),
            maxDistance = maxDistance,
            limit = limit,
        }
    end

    if not next(draw.pinned) and not draw.nearby then
        return { ok = false, error = "agentId, mtaHandle, or nearby required" }
    end

    ensureRender()
    return { ok = true, result = drawSnapshot() }
end

addEventHandler(KNOWN_EVENT, resourceRoot, function(jobId, elementType, ids)
    if source ~= resourceRoot or type(jobId) ~= "string" or type(elementType) ~= "string" or type(ids) ~= "table" then
        return
    end
    local bucket = knownPending[jobId]
    if not bucket then
        bucket = { object = {}, vehicle = {}, ped = {} }
        knownPending[jobId] = bucket
    end
    local set = bucket[elementType]
    if not set then
        return
    end
    for i = 1, #ids do
        local model = tonumber(ids[i])
        if model then
            set[model] = true
        end
    end
end)

addEventHandler(CACHE_EVENT, resourceRoot, function(records, keys)
    if source ~= resourceRoot then
        return
    end
    local seen = {}
    if type(records) == "table" then
        for i = 1, #records do
            local entry = records[i]
            if type(entry) == "table" and entry.elementType and entry.model then
                Agent.rememberBoundingRecord(entry)
                seen[recordKey(entry.elementType, entry.model)] = true
            end
        end
    end
    if type(keys) == "table" then
        for i = 1, #keys do
            local key = keys[i]
            if type(key) == "string" and not seen[key] and not defaults[key] and not custom[key] then
                missingKeys[key] = true
            end
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if scan then
        if scan.timer and isTimer(scan.timer) then
            killTimer(scan.timer)
        end
        destroyWaiting()
        scan = nil
    end
    if rendering then
        removeEventHandler("onClientRender", root, renderBoundingBoxes)
        rendering = false
    end
end)
