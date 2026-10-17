--- Persistent default/custom bounding-box records and HTTP jobs for the client measure.
---@class Agent
Agent = Agent or {}

local DEFAULTS_PATH = "data/bounding-defaults.json"
local CUSTOM_PATH = "data/bounding-custom.json"
local KNOWN_EVENT = "agent:boundingKnown"
local CACHE_EVENT = "agent:boundingCache"
local BATCH_EVENT = "agent:boundingBatch"
local CACHE_REQUEST_EVENT = "agent:boundingCacheRequest"
local KNOWN_CHUNK = 2000

Agent.boundingJobs = Agent.boundingJobs or {}
Agent.boundingNextId = Agent.boundingNextId or 0

local defaults = { version = 1, models = {}, count = 0 }
local custom = { version = 1, models = {}, count = 0 }
local dirty = { defaults = false, custom = false }
local loaded = { defaults = false, custom = false }

addEvent(BATCH_EVENT, true)
addEvent(CACHE_REQUEST_EVENT, true)
addEvent(KNOWN_EVENT, true)
addEvent(CACHE_EVENT, true)

---@param elementType string
---@param model integer
---@return string
local function recordKey(elementType, model)
    return elementType .. ":" .. tostring(model)
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

---@param value any
---@return boolean
local function isTrue(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

---@param value any
---@return string[]
local function normalizeTypes(value)
    local allowed = { object = true, vehicle = true, ped = true }
    local list = {}
    local seen = {}
    local function add(name)
        if type(name) == "string" and allowed[name] and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    if type(value) == "string" then
        add(value)
    elseif type(value) == "table" then
        for i = 1, #value do
            add(value[i])
        end
        if #list == 0 then
            for _, name in pairs(value) do
                add(name)
            end
        end
    end
    if #list == 0 then
        return { "object", "vehicle", "ped" }
    end
    return list
end

---@param raw table
---@param source string
---@return table|nil
local function sanitizeEntry(raw, source)
    if type(raw) ~= "table" then
        return nil
    end
    local model = tonumber(raw.model)
    local elementType = raw.elementType
    if elementType ~= "object" and elementType ~= "vehicle" and elementType ~= "ped" then
        return nil
    end
    if not model or model < 0 or model > 65535 then
        return nil
    end
    model = math.floor(model)
    local min = type(raw.min) == "table" and raw.min or nil
    local max = type(raw.max) == "table" and raw.max or nil
    if not min or not max then
        return nil
    end
    local minX, minY, minZ = finiteNumber(min.x), finiteNumber(min.y), finiteNumber(min.z)
    local maxX, maxY, maxZ = finiteNumber(max.x), finiteNumber(max.y), finiteNumber(max.z)
    if not minX or not minY or not minZ or not maxX or not maxY or not maxZ then
        return nil
    end
    return {
        model = model,
        elementType = elementType,
        min = { x = minX, y = minY, z = minZ },
        max = { x = maxX, y = maxY, z = maxZ },
        radius = finiteNumber(raw.radius),
        capturedAt = getRealTime().timestamp,
        source = source,
    }
end

---@param text string
---@return string
local function jsonString(text)
    text = tostring(text)
    text = text:gsub("\\", "\\\\"):gsub("\"", "\\\"")
    return "\"" .. text .. "\""
end

---@param n number|nil
---@return string
local function jsonNumber(n)
    if type(n) ~= "number" then
        return "null"
    end
    return string.format("%.6f", n)
end

---@param entry table
---@return string
local function encodeEntry(entry)
    return string.format(
        "{\"model\":%d,\"elementType\":%s,\"min\":{\"x\":%s,\"y\":%s,\"z\":%s},\"max\":{\"x\":%s,\"y\":%s,\"z\":%s},\"radius\":%s,\"capturedAt\":%d,\"source\":%s}",
        entry.model,
        jsonString(entry.elementType),
        jsonNumber(entry.min.x), jsonNumber(entry.min.y), jsonNumber(entry.min.z),
        jsonNumber(entry.max.x), jsonNumber(entry.max.y), jsonNumber(entry.max.z),
        jsonNumber(entry.radius),
        tonumber(entry.capturedAt) or 0,
        jsonString(entry.source or "default")
    )
end

---@param store table
---@return string
local function encodeStore(store)
    local parts = { "{\"version\":1,\"models\":{" }
    local first = true
    for key, entry in pairs(store.models) do
        if not first then
            parts[#parts + 1] = ","
        end
        first = false
        parts[#parts + 1] = jsonString(key)
        parts[#parts + 1] = ":"
        parts[#parts + 1] = encodeEntry(entry)
    end
    parts[#parts + 1] = "}}"
    return table.concat(parts)
end

---@param path string
---@param text string
---@return boolean
local function writeTextFile(path, text)
    local tmp = path .. ".tmp"
    if fileExists(tmp) then
        fileDelete(tmp)
    end
    local handle = fileCreate(tmp)
    if not handle then
        return false
    end
    local offset = 1
    local length = #text
    while offset <= length do
        local chunk = text:sub(offset, offset + 65535)
        fileWrite(handle, chunk)
        offset = offset + 65536
    end
    fileClose(handle)
    if fileExists(path) then
        fileDelete(path)
    end
    return fileRename(tmp, path) == true
end

---@param path string
---@param source string
---@return table
local function loadStore(path, source)
    local store = { version = 1, models = {}, count = 0 }
    if not fileExists(path) then
        return store
    end
    local handle = fileOpen(path, true)
    if not handle then
        return store
    end
    local size = fileGetSize(handle) or 0
    local raw = ""
    if size > 0 then
        raw = fileRead(handle, size) or ""
    end
    fileClose(handle)
    local decoded = fromJSON(raw)
    if type(decoded) ~= "table" then
        return store
    end
    if type(decoded.models) ~= "table" and type(decoded[1]) == "table" then
        decoded = decoded[1]
    end
    local models = type(decoded) == "table" and decoded.models or nil
    if type(models) ~= "table" then
        return store
    end
    for _, entry in pairs(models) do
        local clean = sanitizeEntry(entry, source)
        if clean then
            local key = recordKey(clean.elementType, clean.model)
            if not store.models[key] then
                store.count = store.count + 1
            end
            store.models[key] = clean
        end
    end
    return store
end

--- Read a record file on first use. Later calls keep the in-memory table.
---@param which "defaults"|"custom"
---@return table
local function ensureStore(which)
    if loaded[which] then
        return which == "custom" and custom or defaults
    end
    if which == "custom" then
        custom = loadStore(CUSTOM_PATH, "custom")
        loaded.custom = true
        return custom
    end
    defaults = loadStore(DEFAULTS_PATH, "default")
    loaded.defaults = true
    return defaults
end

local function ensureStores()
    ensureStore("defaults")
    ensureStore("custom")
end

---@param store table
---@param entry table
---@param overwrite boolean
---@return boolean stored
local function putRecord(store, entry, overwrite)
    local key = recordKey(entry.elementType, entry.model)
    local exists = store.models[key] ~= nil
    if exists and not overwrite then
        return false
    end
    store.models[key] = entry
    if not exists then
        store.count = store.count + 1
    end
    return true
end

---@param force boolean|nil
function Agent.flushBoundingStores(force)
    if (dirty.defaults or force) and defaults.count >= 0 then
        if dirty.defaults then
            if writeTextFile(DEFAULTS_PATH, encodeStore(defaults)) then
                dirty.defaults = false
            end
        end
    end
    if dirty.custom then
        if writeTextFile(CUSTOM_PATH, encodeStore(custom)) then
            dirty.custom = false
        end
    end
end

---@param a table|nil
---@param b table|nil
---@return boolean
local function boxesDiffer(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or type(a.min) ~= "table" or type(b.min) ~= "table" then
        return false
    end
    local function near(left, right)
        return math.abs((tonumber(left) or 0) - (tonumber(right) or 0)) <= 0.001
    end
    return not (
        near(a.min.x, b.min.x) and near(a.min.y, b.min.y) and near(a.min.z, b.min.z)
        and near(a.max.x, b.max.x) and near(a.max.y, b.max.y) and near(a.max.z, b.max.z)
    )
end

---@param model number|string|nil
---@param elementType string|nil
---@param extra table|nil
---@return table
function Agent.boundingLookup(model, elementType, extra)
    ensureStores()
    extra = type(extra) == "table" and extra or {}
    model = tonumber(model)
    local result = {
        model = model,
        elementType = elementType,
        streamedIn = extra.streamedIn,
        agentId = extra.agentId,
        mtaHandle = extra.mtaHandle,
    }
    if not model then
        result.default = nil
        result.custom = nil
        result.differsFromDefault = false
        return result
    end

    if elementType == "object" or elementType == "vehicle" or elementType == "ped" then
        local key = recordKey(elementType, math.floor(model))
        result.default = defaults.models[key]
        result.custom = custom.models[key]
        result.differsFromDefault = result.default ~= nil and result.custom ~= nil and boxesDiffer(result.default, result.custom)
        return result
    end

    local matches = {}
    for _, kind in ipairs({ "object", "vehicle", "ped" }) do
        local key = recordKey(kind, math.floor(model))
        local stock = defaults.models[key]
        local live = custom.models[key]
        if stock or live then
            matches[#matches + 1] = {
                elementType = kind,
                default = stock,
                custom = live,
                differsFromDefault = stock ~= nil and live ~= nil and boxesDiffer(stock, live),
            }
        end
    end
    result.matches = matches
    return result
end

---@param entry table
---@return boolean
function Agent.storeCustomBounding(entry)
    ensureStores()
    local clean = sanitizeEntry(entry, "custom")
    if not clean then
        return false
    end
    putRecord(custom, clean, true)
    dirty.custom = true
    return true
end

---@param job table
---@return table
local function scanSummary(job)
    return {
        status = "complete",
        id = job.id,
        stopped = job.stopped and true or false,
        scanned = job.scanned or 0,
        stored = job.stored or 0,
        skippedExisting = job.skippedExisting or 0,
        skippedReplaced = job.skippedReplaced or 0,
        failed = job.failed or 0,
        total = job.total or 0,
        defaults = defaults.count,
        custom = custom.count,
        types = job.types,
        force = job.force and true or false,
        player = job.player,
    }
end

---@param job table
---@return table
local function scanPending(job)
    return {
        ok = true,
        id = job.id,
        status = "pending",
        scanned = job.scanned or 0,
        stored = job.stored or 0,
        skippedExisting = job.skippedExisting or 0,
        skippedReplaced = job.skippedReplaced or 0,
        failed = job.failed or 0,
        total = job.total or 0,
        defaults = defaults.count,
        custom = custom.count,
        types = job.types,
        force = job.force and true or false,
        player = job.player,
    }
end

---@param job table
---@param stopped boolean
local function completeScan(job, stopped)
    if job.status ~= "pending" then
        return
    end
    job.stopped = stopped and true or false
    job.status = "complete"
    job.result = scanSummary(job)
    Agent.flushBoundingStores(false)
end

---@param player player
---@param jobId string
---@param known table
local function sendKnownIds(player, jobId, known)
    for _, elementType in ipairs({ "object", "vehicle", "ped" }) do
        local ids = known[elementType] or {}
        local index = 1
        while index <= #ids do
            local slice = {}
            local last = math.min(index + KNOWN_CHUNK - 1, #ids)
            for n = index, last do
                slice[#slice + 1] = ids[n]
            end
            triggerClientEvent(player, KNOWN_EVENT, resourceRoot, jobId, elementType, slice)
            index = last + 1
        end
    end
end

---@param types string[]
---@return table
local function collectKnownIds(types)
    local wanted = {}
    for i = 1, #types do
        wanted[types[i]] = true
    end
    local known = { object = {}, vehicle = {}, ped = {} }
    for key in pairs(defaults.models) do
        local elementType, modelText = tostring(key):match("^(%a+):(%d+)$")
        local model = tonumber(modelText)
        if elementType and model and wanted[elementType] and known[elementType] then
            local list = known[elementType]
            list[#list + 1] = model
        end
    end
    return known
end

---@param playerName string|nil
---@param options table|nil
---@return table
function Agent.handleBoundingScan(playerName, options)
    ensureStores()
    options = type(options) == "table" and options or {}
    local action = options.action or "start"

    if action == "status" then
        return Agent.getBoundingScanResult(options.id)
    end

    if action == "stop" then
        local job = Agent.boundingJobs[options.id]
        if not job then
            return { ok = false, error = "Request not found" }
        end
        if job.status ~= "pending" then
            return {
                ok = true,
                id = job.id,
                status = "complete",
                result = job.result or scanSummary(job),
            }
        end
        if isElement(job.playerElement) then
            Agent.callClient(job.playerElement, "boundingScanStop", { jobId = job.id })
        end
        completeScan(job, true)
        return {
            ok = true,
            id = job.id,
            status = "complete",
            result = job.result,
        }
    end

    if action ~= "start" then
        return { ok = false, error = "action must be start, status, or stop" }
    end

    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return { ok = false, error = err or "Player not found" }
    end

    for _, existing in pairs(Agent.boundingJobs) do
        if existing.status == "pending" and existing.playerElement == player then
            if isElement(player) then
                Agent.callClient(player, "boundingScanStop", { jobId = existing.id })
            end
            completeScan(existing, true)
        end
    end

    local types = normalizeTypes(options.types or options.elementType)
    local force = isTrue(options.force)
    Agent.boundingNextId = Agent.boundingNextId + 1
    local id = "bb-" .. getTickCount() .. "-" .. Agent.boundingNextId
    local job = {
        id = id,
        status = "pending",
        player = getPlayerName(player),
        playerElement = player,
        createdAt = getTickCount(),
        types = types,
        force = force,
        scanned = 0,
        stored = 0,
        skippedExisting = 0,
        skippedReplaced = 0,
        failed = 0,
        total = 0,
        stopped = false,
        result = nil,
        error = nil,
    }
    Agent.boundingJobs[id] = job

    if not force then
        sendKnownIds(player, id, collectKnownIds(types))
    end

    local batch = tonumber(options.batch) or 8
    if batch < 1 then batch = 1 end
    if batch > 16 then batch = 16 end

    local sent = Agent.callClient(player, "boundingScanStart", {
        jobId = id,
        types = types,
        batch = batch,
        force = force,
    }, function(clientReturn)
        if job.status ~= "pending" then
            return
        end
        if type(clientReturn) ~= "table" or not clientReturn.ok then
            job.error = (type(clientReturn) == "table" and clientReturn.error) or "Scan failed to start"
            job.status = "complete"
            job.result = scanSummary(job)
            job.result.error = job.error
        end
    end)

    if not sent then
        Agent.boundingJobs[id] = nil
        return { ok = false, error = "Client not loaded (player may not have agent on client — reconnect after restart agent)" }
    end

    return scanPending(job)
end

---@param id any
---@return table
function Agent.getBoundingScanResult(id)
    ensureStores()
    if type(id) ~= "string" or id == "" then
        return { ok = false, error = "Request id required" }
    end
    local job = Agent.boundingJobs[id]
    if not job then
        return { ok = false, error = "Request not found" }
    end
    if job.status == "pending" then
        return scanPending(job)
    end
    if job.error and not job.result then
        return {
            ok = false,
            id = job.id,
            status = "complete",
            error = job.error,
            player = job.player,
        }
    end
    return {
        ok = true,
        id = job.id,
        status = "complete",
        result = job.result or scanSummary(job),
    }
end

---@param payload table
---@param playerElement player
local function applyScanBatch(payload, playerElement)
    ensureStores()
    if type(payload) ~= "table" or type(payload.jobId) ~= "string" then
        return
    end
    local job = Agent.boundingJobs[payload.jobId]
    if not job or job.status ~= "pending" then
        return
    end
    if playerElement ~= job.playerElement then
        return
    end

    local entries = type(payload.entries) == "table" and payload.entries or {}
    for i = 1, #entries do
        local entry = sanitizeEntry(entries[i], "default")
        if entry then
            if putRecord(defaults, entry, job.force) then
                job.stored = job.stored + 1
                dirty.defaults = true
            else
                job.skippedExisting = job.skippedExisting + 1
            end
        end
    end

    job.scanned = job.scanned + (tonumber(payload.scanned) or 0)
    job.failed = job.failed + (tonumber(payload.failed) or 0)
    job.skippedReplaced = job.skippedReplaced + (tonumber(payload.skippedReplaced) or 0)
    local total = tonumber(payload.total)
    if total and total >= 0 then
        job.total = total
    end

    if payload.done or payload.stopped then
        completeScan(job, payload.stopped and true or false)
    end
end

---@param model number|nil
---@param elementType string|nil
---@return table
local function recordsForModel(model, elementType)
    ensureStores()
    local records = {}
    if not model then
        return records
    end
    local kinds = (elementType == "object" or elementType == "vehicle" or elementType == "ped")
        and { elementType }
        or { "object", "vehicle", "ped" }
    for i = 1, #kinds do
        local key = recordKey(kinds[i], math.floor(model))
        if defaults.models[key] then
            records[#records + 1] = defaults.models[key]
        end
        if custom.models[key] then
            records[#records + 1] = custom.models[key]
        end
    end
    return records
end

---@param playerName string|nil
---@param options table|nil
---@return table
function Agent.handleBoundingGet(playerName, options)
    options = type(options) == "table" and options or {}
    local agentId = options.agentId or options.id
    local hasElement = (type(agentId) == "string" and agentId ~= "")
        or (type(options.mtaHandle) == "string" and options.mtaHandle ~= "")

    if not hasElement then
        local model = tonumber(options.model)
        if not model then
            return { ok = false, error = "model, agentId, or mtaHandle required" }
        end
        return {
            ok = true,
            status = "complete",
            result = Agent.boundingLookup(model, options.elementType),
        }
    end

    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return { ok = false, error = err or "Player not found" }
    end

    local id, startErr = Agent.startClientRequest(player, "boundingResolve", options, {
        timeoutMs = 15000,
        serial = options.serial,
        onComplete = function(request, clientReturn)
            local info = type(clientReturn.result) == "table" and clientReturn.result or {}
            request.result = Agent.boundingLookup(info.model, info.elementType, info)
        end,
    })
    if not id then
        return { ok = false, error = startErr }
    end
    return { ok = true, id = id, status = "pending" }
end

---@param id any
---@return table
function Agent.getBoundingGetResult(id)
    return Agent.getClientRequestResult(id)
end

---@param playerName string|nil
---@param options table|nil
---@return table
function Agent.handleBoundingFetch(playerName, options)
    options = type(options) == "table" and options or {}
    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return { ok = false, error = err or "Player not found" }
    end

    local payload = {}
    for key, value in pairs(options) do
        payload[key] = value
    end
    payload.records = recordsForModel(tonumber(options.model), options.elementType)

    local id, startErr = Agent.startClientRequest(player, "boundingFetch", payload, {
        timeoutMs = 20000,
        serial = options.serial,
        onComplete = function(request, clientReturn)
            local entry = clientReturn.result
            if type(entry) == "table" then
                Agent.storeCustomBounding(entry)
                Agent.flushBoundingStores(false)
                request.result = Agent.boundingLookup(entry.model, entry.elementType, {
                    streamedIn = true,
                    agentId = options.agentId or options.id,
                    mtaHandle = options.mtaHandle,
                })
                request.result.measured = Agent.boundingLookup(entry.model, entry.elementType).custom
            end
        end,
    })
    if not id then
        return { ok = false, error = startErr }
    end
    return { ok = true, id = id, status = "pending" }
end

---@param id any
---@return table
function Agent.getBoundingFetchResult(id)
    local result = Agent.getClientRequestResult(id)
    if result.status == "pending" or result.ok then
        return result
    end
    local details = type(result.details) == "table" and result.details or {}
    if details.model then
        local lookup = Agent.boundingLookup(details.model, details.elementType, {
            streamedIn = details.streamedIn,
        })
        result.model = lookup.model
        result.elementType = details.elementType or lookup.elementType
        result.default = lookup.default
        result.custom = lookup.custom
        result.matches = lookup.matches
        result.differsFromDefault = lookup.differsFromDefault
    end
    if result.error == "notStreamedIn" then
        result.hint = "getElementBoundingBox requires a streamed-in element. Cached default and custom records are included when they exist."
    end
    return result
end

---@param playerName string|nil
---@param options table|nil
---@return table
function Agent.handleBoundingDraw(playerName, options)
    options = type(options) == "table" and options or {}
    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return { ok = false, error = err or "Player not found" }
    end

    local payload = {}
    for key, value in pairs(options) do
        payload[key] = value
    end
    payload.records = recordsForModel(tonumber(options.model), options.elementType or options.type)
    payload.nearby = isTrue(options.nearby)

    local id, startErr = Agent.startClientRequest(player, "boundingDraw", payload, {
        timeoutMs = 15000,
        serial = options.serial,
    })
    if not id then
        return { ok = false, error = startErr }
    end
    return { ok = true, id = id, status = "pending" }
end

---@param id any
---@return table
function Agent.getBoundingDrawResult(id)
    return Agent.getClientRequestResult(id)
end

addEventHandler(BATCH_EVENT, resourceRoot, function(payload)
    if source ~= resourceRoot or not client then
        return
    end
    applyScanBatch(payload, client)
end)

addEventHandler(CACHE_REQUEST_EVENT, resourceRoot, function(keys)
    if source ~= resourceRoot or not client or type(keys) ~= "table" then
        return
    end
    ensureStores()
    local records = {}
    local limited = {}
    local count = math.min(#keys, 64)
    for i = 1, count do
        local key = keys[i]
        if type(key) == "string" then
            limited[#limited + 1] = key
            if defaults.models[key] then
                records[#records + 1] = defaults.models[key]
            end
            if custom.models[key] then
                records[#records + 1] = custom.models[key]
            end
        end
    end
    triggerClientEvent(client, CACHE_EVENT, resourceRoot, records, limited)
end)

addEventHandler("onPlayerQuit", root, function()
    for _, job in pairs(Agent.boundingJobs) do
        if job.status == "pending" and job.playerElement == source then
            completeScan(job, true)
        end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    Agent.flushBoundingStores(false)
end)

setTimer(function()
    Agent.flushBoundingStores(false)
    local now = getTickCount()
    local ttl = 30 * 60 * 1000
    for id, job in pairs(Agent.boundingJobs) do
        if now - (job.createdAt or 0) > ttl then
            Agent.boundingJobs[id] = nil
        end
    end
end, 2000, 0)
