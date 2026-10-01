--- Client: apply generated DFF/TXD/COL replacements and spawn a preview object.

---@class Agent
Agent = Agent or {}

Agent.MODEL_REPLACE_DEFAULT_ID = 1851

---@type table<integer, { modelId: integer, object: element|nil, dff: userdata|nil, txd: userdata|nil, col: userdata|nil }>
local activeByModel = {}

---@param data string
---@param encoding string|nil
---@param compressed string|nil
---@return string|nil, string|nil
local function decodePayload(data, encoding, compressed)
    if type(data) ~= "string" or data == "" then
        return nil, "empty buffer"
    end

    local raw = data
    if encoding == "base64" then
        local decoded = decodeString("base64", data)
        if not decoded then
            return nil, "base64 decode failed"
        end
        raw = decoded
    end

    if compressed == "gzip" or compressed == "zlib" then
        local inflated = decodeString("zlib", raw)
        if not inflated then
            return nil, "zlib decode failed"
        end
        raw = inflated
    end

    return raw
end

---@param modelId integer
local function clearActive(modelId)
    local active = activeByModel[modelId]
    if not active then
        return
    end
    if isElement(active.object) then
        destroyElement(active.object)
    end
    if active.dff then
        engineRestoreModel(modelId)
    end
    if active.col then
        engineRestoreCOL(modelId)
    end
    if active.txd then
        destroyElement(active.txd)
    end
    activeByModel[modelId] = nil
end

---@param modelId integer
function Agent.clearModelPreview(modelId)
    clearActive(modelId)
end

---@param payload table
---@return AgentHttpPayload
function Agent.applyModelReplace(payload)
    payload = type(payload) == "table" and payload or {}

    local modelId = tonumber(payload.modelId) or Agent.MODEL_REPLACE_DEFAULT_ID
    local encoding = payload.encoding or "base64"
    local compressed = payload.compressed or "gzip"

    local dffData, dffErr = decodePayload(payload.dff, encoding, compressed)
    if not dffData then
        return { ok = false, error = "dff: " .. tostring(dffErr) }
    end
    local txdData, txdErr = decodePayload(payload.txd, encoding, compressed)
    if not txdData then
        return { ok = false, error = "txd: " .. tostring(txdErr) }
    end
    local colData = nil
    if type(payload.col) == "string" and payload.col ~= "" then
        local colErr
        colData, colErr = decodePayload(payload.col, encoding, compressed)
        if not colData then
            return { ok = false, error = "col: " .. tostring(colErr) }
        end
    end

    clearActive(modelId)

    local col = nil
    if colData then
        col = engineLoadCOL(colData)
        if not col then
            return { ok = false, error = "engineLoadCOL failed" }
        end
        if not engineReplaceCOL(col, modelId) then
            destroyElement(col)
            return { ok = false, error = "engineReplaceCOL failed" }
        end
    end

    local txd = engineLoadTXD(txdData, true)
    if not txd then
        if col then
            engineRestoreCOL(modelId)
            destroyElement(col)
        end
        return { ok = false, error = "engineLoadTXD failed" }
    end
    engineImportTXD(txd, modelId)

    local dff = engineLoadDFF(dffData)
    if not dff then
        if col then
            engineRestoreCOL(modelId)
            destroyElement(col)
        end
        destroyElement(txd)
        return { ok = false, error = "engineLoadDFF failed" }
    end
    if not engineReplaceModel(dff, modelId) then
        if col then
            engineRestoreCOL(modelId)
            destroyElement(col)
        end
        destroyElement(txd)
        destroyElement(dff)
        return { ok = false, error = "engineReplaceModel failed" }
    end

    local px, py, pz = getElementPosition(localPlayer)
    local _, _, rot = getElementRotation(localPlayer)
    local dist = tonumber(payload.offsetDistance) or 3
    local offsetZ = tonumber(payload.offsetZ) or 0
    local rad = math.rad(rot)
    local ox = px - math.sin(rad) * dist
    local oy = py + math.cos(rad) * dist
    local oz = pz + offsetZ

    local object = createObject(modelId, ox, oy, oz, 0, 0, rot)
    if object then
        setElementDimension(object, getElementDimension(localPlayer))
        setElementInterior(object, getElementInterior(localPlayer))
        setElementCollisionsEnabled(object, true)
    end

    activeByModel[modelId] = {
        modelId = modelId,
        object = object,
        dff = dff,
        txd = txd,
        col = col,
        buildId = payload.id,
    }

    return {
        ok = true,
        result = {
            modelId = modelId,
            buildId = payload.id,
            object = object and true or false,
            position = { x = ox, y = oy, z = oz },
            replaced = true,
        },
    }
end

---@param payload table|nil
---@return AgentHttpPayload
function Agent.restoreModelReplace(payload)
    payload = type(payload) == "table" and payload or {}
    local modelId = tonumber(payload.modelId)

    if modelId then
        clearActive(modelId)
        return { ok = true, result = { modelId = modelId, restored = true } }
    end

    local restored = {}
    for id in pairs(activeByModel) do
        restored[#restored + 1] = id
        clearActive(id)
    end
    return { ok = true, result = { restored = restored } }
end
