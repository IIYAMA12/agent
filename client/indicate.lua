--- Virtual 2D and 3D indications. Positions live in a client table and are painted
--- with dxDraw only. This file must not call createMarker or spawn elements.
---@class Agent
Agent = Agent or {}

local MAX_INDICATIONS = 32
local RING_SEGMENTS = 16
local EDGE_INSET = 72
local DEFAULT_TIMEOUT_MS = 15000
local MAX_TIMEOUT_MS = 3600000

local KINDS = { look = true, marker = true, measure = true }
local MODES = { ["2d"] = true, ["3d"] = true, both = true }

local DEFAULT_COLOR = {
    look = { r = 255, g = 196, b = 40, a = 230 },
    marker = { r = 80, g = 220, b = 140, a = 220 },
    measure = { r = 120, g = 190, b = 255, a = 230 },
}

---@type table<string, table>
local byId = {}
---@type string[]
local order = {}
local seq = 0
local rendering = false

---@param value any
---@return boolean
local function isTrue(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

---@param value any
---@return boolean
local function isFalse(value)
    return value == false or value == 0 or value == "0" or value == "false"
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

---@param ms number
---@return number
local function clampTimeoutMs(ms)
    if ms < 0 then
        return 0
    end
    if ms > MAX_TIMEOUT_MS then
        return MAX_TIMEOUT_MS
    end
    return ms
end

--- Explicit cue lifetime in milliseconds. `ttlMs` wins over `timeout` (seconds).
--- Nil when the caller left both unset. Zero means keep until indicate.clear.
---@param raw table
---@return number|nil
local function explicitTimeoutMs(raw)
    if type(raw) ~= "table" then
        return nil
    end
    if raw.ttlMs ~= nil and raw.ttlMs ~= "" then
        local ms = finiteNumber(raw.ttlMs)
        if ms then
            return clampTimeoutMs(ms)
        end
    end
    if raw.timeout ~= nil and raw.timeout ~= "" then
        local seconds = finiteNumber(raw.timeout)
        if seconds then
            return clampTimeoutMs(seconds * 1000)
        end
    end
    return nil
end

---@param value any
---@param fallback integer
---@return integer
local function clampByte(value, fallback)
    local n = tonumber(value)
    if not n then
        return fallback
    end
    if n < 0 then
        return 0
    end
    if n > 255 then
        return 255
    end
    return math.floor(n + 0.5)
end

---@param n number
---@param places integer
---@return number
local function roundTo(n, places)
    local scale = 10 ^ places
    return math.floor(n * scale + 0.5) / scale
end

---@param value any
---@param kind string
---@return table
local function parseColor(value, kind)
    local fallback = DEFAULT_COLOR[kind] or DEFAULT_COLOR.look
    if type(value) == "table" then
        return {
            r = clampByte(value.r or value[1], fallback.r),
            g = clampByte(value.g or value[2], fallback.g),
            b = clampByte(value.b or value[3], fallback.b),
            a = clampByte(value.a or value[4], fallback.a),
        }
    end
    if type(value) == "string" then
        local hex = value:gsub("^#", "")
        if #hex == 6 or #hex == 8 then
            local r = tonumber(hex:sub(1, 2), 16)
            local g = tonumber(hex:sub(3, 4), 16)
            local b = tonumber(hex:sub(5, 6), 16)
            local a = #hex == 8 and tonumber(hex:sub(7, 8), 16) or fallback.a
            if r and g and b and a then
                return { r = r, g = g, b = b, a = a }
            end
        end
    end
    return { r = fallback.r, g = fallback.g, b = fallback.b, a = fallback.a }
end

---@param item table
---@param now integer
---@return boolean
local function isExpired(item, now)
    return item.expiresAt ~= nil and now >= item.expiresAt
end

local function purgeExpired()
    local now = getTickCount()
    local index = 1
    while index <= #order do
        local item = byId[order[index]]
        if not item or isExpired(item, now) then
            byId[order[index]] = nil
            table.remove(order, index)
        else
            index = index + 1
        end
    end
end

---@param id string
---@return boolean
local function removeId(id)
    if not byId[id] then
        return false
    end
    byId[id] = nil
    for index = 1, #order do
        if order[index] == id then
            table.remove(order, index)
            break
        end
    end
    return true
end

---@param agentId string
---@return table|nil pos
---@return string|nil error
local function resolveLive(agentId)
    if type(Agent.resolveElement) ~= "function" then
        return nil, "registry unavailable"
    end
    local element, _, err = Agent.resolveElement(agentId)
    if not element or not isElement(element) then
        return nil, err or "notFound"
    end
    local x, y, z = getElementPosition(element)
    local sameWorld = getElementDimension(element) == getElementDimension(localPlayer)
        and getElementInterior(element) == getElementInterior(localPlayer)
    return { x = x, y = y, z = z, sameWorld = sameWorld }
end

---@param item table
---@param which "from"|"to"
---@return table|nil pos
---@return string|nil error
local function pointOf(item, which)
    local agentId = which == "to" and item.toAgentId or item.agentId
    local fixedX = which == "to" and item.toX or item.x
    local fixedY = which == "to" and item.toY or item.y
    local fixedZ = which == "to" and item.toZ or item.z
    if agentId then
        local pos, err = resolveLive(agentId)
        if pos then
            return pos
        end
        if fixedX and fixedY and fixedZ then
            return { x = fixedX, y = fixedY, z = fixedZ, sameWorld = true, stale = true }, err
        end
        return nil, err or "notFound"
    end
    if fixedX and fixedY and fixedZ then
        return { x = fixedX, y = fixedY, z = fixedZ, sameWorld = true }
    end
    return nil, "position required"
end

---@param x number
---@param y number
---@param z number
---@return number|nil sx
---@return number|nil sy
local function project(x, y, z)
    local sx, sy = getScreenFromWorldPosition(x, y, z, 0, false)
    if not sx or not sy then
        return nil
    end
    local screenW, screenH = guiGetScreenSize()
    if sx < 0 or sy < 0 or sx > screenW or sy > screenH then
        return nil
    end
    return sx, sy
end

---@param worldX number
---@param worldY number
---@return number|nil sx
---@return number|nil sy
---@return number|nil dirX
---@return number|nil dirY
local function edgePoint(worldX, worldY)
    local camX, camY, _, lookX, lookY = getCameraMatrix()
    if not camX then
        return nil
    end
    local yaw = math.atan2(lookY - camY, lookX - camX)
    local bearing = math.atan2(worldY - camY, worldX - camX)
    local angle = bearing - yaw
    local dirX = -math.sin(angle)
    local dirY = -math.cos(angle)
    local length = math.sqrt(dirX * dirX + dirY * dirY)
    if length < 0.001 then
        return nil
    end
    dirX, dirY = dirX / length, dirY / length
    local screenW, screenH = guiGetScreenSize()
    local radiusX = math.max(20, screenW * 0.5 - EDGE_INSET)
    local radiusY = math.max(20, screenH * 0.5 - EDGE_INSET)
    local scale = 1 / math.sqrt((dirX / radiusX) ^ 2 + (dirY / radiusY) ^ 2)
    return screenW * 0.5 + dirX * scale, screenH * 0.5 + dirY * scale, dirX, dirY
end

---@param x number
---@param y number
---@param z number
---@param radius number
---@param color integer
local function drawRing(x, y, z, radius, color)
    local step = (math.pi * 2) / RING_SEGMENTS
    local prevX = x + radius
    local prevY = y
    for index = 1, RING_SEGMENTS do
        local angle = step * index
        local nextX = x + math.cos(angle) * radius
        local nextY = y + math.sin(angle) * radius
        dxDrawLine3D(prevX, prevY, z, nextX, nextY, z, color, 2)
        prevX, prevY = nextX, nextY
    end
end

---@param x number
---@param y number
---@param z number
---@param height number
---@param color integer
local function drawPost(x, y, z, height, color)
    dxDrawLine3D(x, y, z, x, y, z + height, color, 2)
    local arm = math.min(0.25, height * 0.15)
    dxDrawLine3D(x - arm, y, z + height, x + arm, y, z + height, color, 2)
    dxDrawLine3D(x, y - arm, z + height, x, y + arm, z + height, color, 2)
end

---@param sx number
---@param sy number
---@param dirX number
---@param dirY number
---@param color integer
local function drawChevron(sx, sy, dirX, dirY, color)
    local perpX, perpY = -dirY, dirX
    local tipX, tipY = sx + dirX * 14, sy + dirY * 14
    local leftX = sx - dirX * 10 + perpX * 8
    local leftY = sy - dirY * 10 + perpY * 8
    local rightX = sx - dirX * 10 - perpX * 8
    local rightY = sy - dirY * 10 - perpY * 8
    dxDrawLine(leftX, leftY, tipX, tipY, color, 2, false)
    dxDrawLine(rightX, rightY, tipX, tipY, color, 2, false)
end

---@param sx number
---@param sy number
---@param radius number
---@param color integer
local function drawBracket(sx, sy, radius, color)
    local arm = radius * 0.45
    local corners = {
        { sx - radius, sy - radius, 1, 0, 0, 1 },
        { sx + radius, sy - radius, -1, 0, 0, 1 },
        { sx - radius, sy + radius, 1, 0, 0, -1 },
        { sx + radius, sy + radius, -1, 0, 0, -1 },
    }
    for index = 1, #corners do
        local corner = corners[index]
        local ox, oy = corner[1], corner[2]
        dxDrawLine(ox, oy, ox + corner[3] * arm, oy + corner[4] * arm, color, 2, false)
        dxDrawLine(ox, oy, ox + corner[5] * arm, oy + corner[6] * arm, color, 2, false)
    end
end

---@param sx number
---@param sy number
---@param text string
---@param color integer
local function drawLabel(sx, sy, text, color)
    local halfW = 160
    local height = 48
    local shadow = tocolor(0, 0, 0, 200)
    dxDrawText(text, sx - halfW + 1, sy + 1, sx + halfW + 1, sy + height + 1, shadow, 1, "default-bold", "center", "top", false, false, false)
    dxDrawText(text, sx - halfW, sy, sx + halfW, sy + height, color, 1, "default-bold", "center", "top", false, false, false)
end

---@param item table
---@return integer
local function lineColor(item)
    local alpha = item.color.a
    if item.kind == "look" then
        local wave = (math.sin(getTickCount() / 180) + 1) * 0.5
        alpha = math.floor(alpha * (0.65 + 0.35 * wave))
    end
    return tocolor(item.color.r, item.color.g, item.color.b, alpha)
end

---@param meters number|nil
---@return string|nil
local function formatMeters(meters)
    if not meters then
        return nil
    end
    return string.format("%.1f m", meters)
end

---@param item table
---@param meters number|nil
---@return string|nil
local function labelText(item, meters)
    local distanceLabel = item.showDistance and formatMeters(meters) or nil
    if item.label and distanceLabel then
        return item.label .. "\n" .. distanceLabel
    end
    return item.label or distanceLabel
end

---@param item table
---@return table
local function describe(item)
    local fromPos, fromErr = pointOf(item, "from")
    local toPos, toErr = nil, nil
    if item.kind == "measure" then
        toPos, toErr = pointOf(item, "to")
    end

    local px, py, pz = getElementPosition(localPlayer)
    local playerDistance = nil
    local distance = nil
    local anchor = fromPos
    if item.kind == "measure" and fromPos and toPos then
        distance = roundTo(getDistanceBetweenPoints3D(fromPos.x, fromPos.y, fromPos.z, toPos.x, toPos.y, toPos.z), 1)
        local midX = (fromPos.x + toPos.x) * 0.5
        local midY = (fromPos.y + toPos.y) * 0.5
        local midZ = (fromPos.z + toPos.z) * 0.5
        playerDistance = roundTo(getDistanceBetweenPoints3D(px, py, pz, midX, midY, midZ), 1)
        anchor = { x = midX, y = midY, z = midZ, sameWorld = fromPos.sameWorld ~= false and toPos.sameWorld ~= false }
    elseif fromPos then
        distance = roundTo(getDistanceBetweenPoints3D(px, py, pz, fromPos.x, fromPos.y, fromPos.z), 1)
        playerDistance = distance
    end

    local screenX, screenY = nil, nil
    if anchor and anchor.sameWorld ~= false then
        screenX, screenY = project(anchor.x, anchor.y, anchor.z)
    end

    local row = {
        id = item.id,
        kind = item.kind,
        mode = item.mode,
        label = item.label,
        size = item.size,
        showDistance = item.showDistance,
        color = { r = item.color.r, g = item.color.g, b = item.color.b, a = item.color.a },
        distance = distance,
        playerDistance = playerDistance,
        onScreen = screenX ~= nil,
        sameWorld = anchor ~= nil and anchor.sameWorld ~= false,
    }
    if fromPos then
        row.position = { x = roundTo(fromPos.x, 3), y = roundTo(fromPos.y, 3), z = roundTo(fromPos.z, 3) }
        if fromPos.stale then
            row.stale = true
        end
    end
    if fromErr and not fromPos then
        row.positionError = fromErr
    elseif fromPos and fromPos.stale and fromErr then
        row.positionError = fromErr
    end
    if item.kind == "measure" then
        if toPos then
            row.to = { x = roundTo(toPos.x, 3), y = roundTo(toPos.y, 3), z = roundTo(toPos.z, 3) }
            if toPos.stale then
                row.stale = true
            end
        end
        if toErr and (not toPos or toPos.stale) then
            row.toError = toErr
        end
    end
    if screenX then
        row.screen = { x = math.floor(screenX + 0.5), y = math.floor(screenY + 0.5) }
    end
    if item.expiresAt then
        row.ttlMs = math.max(0, item.expiresAt - getTickCount())
    end
    return row
end

---@return table
local function snapshot()
    purgeExpired()
    local items = {}
    for index = 1, #order do
        items[#items + 1] = describe(byId[order[index]])
    end
    return { count = #items, items = items }
end

---@param item table
local function drawItem(item)
    local fromPos = pointOf(item, "from")
    if not fromPos or fromPos.sameWorld == false then
        return
    end

    local toPos = nil
    if item.kind == "measure" then
        toPos = pointOf(item, "to")
        if not toPos or toPos.sameWorld == false then
            return
        end
    end

    local px, py, pz = getElementPosition(localPlayer)
    local meters = nil
    local anchorX, anchorY, anchorZ = fromPos.x, fromPos.y, fromPos.z
    if item.kind == "measure" and toPos then
        meters = getDistanceBetweenPoints3D(fromPos.x, fromPos.y, fromPos.z, toPos.x, toPos.y, toPos.z)
        anchorX = (fromPos.x + toPos.x) * 0.5
        anchorY = (fromPos.y + toPos.y) * 0.5
        anchorZ = (fromPos.z + toPos.z) * 0.5
    else
        meters = getDistanceBetweenPoints3D(px, py, pz, fromPos.x, fromPos.y, fromPos.z)
    end

    local color = lineColor(item)
    local textColor = tocolor(item.color.r, item.color.g, item.color.b, item.color.a)
    local draw3d = item.mode == "3d" or item.mode == "both"
    local draw2d = item.mode == "2d" or item.mode == "both"
    local lift = 0.05

    if draw3d and item.kind == "measure" and toPos then
        dxDrawLine3D(fromPos.x, fromPos.y, fromPos.z + lift, toPos.x, toPos.y, toPos.z + lift, color, 2)
        local ring = math.max(0.15, item.size * 0.45)
        drawRing(fromPos.x, fromPos.y, fromPos.z + lift, ring, color)
        drawRing(toPos.x, toPos.y, toPos.z + lift, ring, color)
    elseif draw3d then
        local height = math.min(8, math.max(1, item.size * 2))
        drawRing(fromPos.x, fromPos.y, fromPos.z + lift, item.size, color)
        drawPost(fromPos.x, fromPos.y, fromPos.z + lift, height, color)
    end

    local text = labelText(item, meters)
    local screenX, screenY = project(anchorX, anchorY, anchorZ)
    if screenX then
        if draw2d then
            drawBracket(screenX, screenY, 16, color)
        end
        if text then
            drawLabel(screenX, screenY + (draw2d and 18 or 8), text, textColor)
        end
        return
    end

    if not draw2d then
        return
    end

    local edgeX, edgeY, dirX, dirY = edgePoint(anchorX, anchorY)
    if not edgeX then
        return
    end
    drawChevron(edgeX, edgeY, dirX, dirY, color)
    if text then
        drawLabel(edgeX - dirX * 18, edgeY - dirY * 18, text, textColor)
    end
end

local function renderIndications()
    if not isElement(localPlayer) then
        return
    end
    purgeExpired()
    for index = 1, #order do
        local item = byId[order[index]]
        if item then
            drawItem(item)
        end
    end
    if #order == 0 and rendering then
        removeEventHandler("onClientRender", root, renderIndications)
        rendering = false
    end
end

local function syncRender()
    if #order == 0 then
        if rendering then
            removeEventHandler("onClientRender", root, renderIndications)
            rendering = false
        end
        return
    end
    if not rendering then
        addEventHandler("onClientRender", root, renderIndications)
        rendering = true
    end
end

---@param value any
---@return table|nil list
---@return string|nil error
local function coerceItems(value)
    if type(value) == "string" then
        if value == "" then
            return nil, "items JSON is invalid"
        end
        local decoded = fromJSON(value)
        if type(decoded) ~= "table" then
            return nil, "items JSON is invalid"
        end
        value = decoded
    end
    if type(value) ~= "table" then
        return nil
    end
    if type(value[1]) == "table" then
        return value
    end
    if value.x ~= nil or value.y ~= nil or value.z ~= nil or value.agentId or value.kind
        or value.label or value.toX ~= nil or value.toY ~= nil or value.toZ ~= nil
        or value.toAgentId or value.mode or (type(value.id) == "string" and value.id ~= "") then
        return { value }
    end
    return nil
end

---@param raw table
---@param fallbackMs number|nil
---@return table|nil item
---@return string|nil error
local function sanitizeItem(raw, fallbackMs)
    if type(raw) ~= "table" then
        return nil, "item must be an object"
    end

    local kind = raw.kind
    if kind == nil or kind == "" then
        kind = "look"
    end
    if not KINDS[kind] then
        return nil, "kind must be look, marker, or measure"
    end

    local mode = raw.mode
    if mode == nil or mode == "" then
        mode = kind == "look" and "both" or "3d"
    end
    if not MODES[mode] then
        return nil, "mode must be 2d, 3d, or both"
    end

    local id = raw.id
    if id == nil or id == "" then
        id = nil
    elseif type(id) ~= "string" or not id:match("^[%w_%-]+$") or #id > 64 then
        return nil, "invalid id"
    end

    local agentId = nil
    if type(raw.agentId) == "string" and raw.agentId ~= "" then
        agentId = raw.agentId
    end
    local toAgentId = nil
    if type(raw.toAgentId) == "string" and raw.toAgentId ~= "" then
        toAgentId = raw.toAgentId
    end

    local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
    local hasFixed = x ~= nil and y ~= nil and z ~= nil
    local toX, toY, toZ = tonumber(raw.toX), tonumber(raw.toY), tonumber(raw.toZ)
    local hasTo = toX ~= nil and toY ~= nil and toZ ~= nil

    if not hasFixed and not agentId then
        return nil, "x, y, z or agentId is required"
    end
    if kind == "measure" and not hasTo and not toAgentId then
        return nil, "measure requires toX, toY, toZ or toAgentId"
    end

    local size = tonumber(raw.size) or (kind == "measure" and 0.45 or 0.6)
    if size < 0.05 then
        size = 0.05
    elseif size > 50 then
        size = 50
    end

    local ttlMs = explicitTimeoutMs(raw)
    if ttlMs == nil then
        if fallbackMs == nil then
            ttlMs = DEFAULT_TIMEOUT_MS
        else
            ttlMs = fallbackMs
        end
    end

    local label = nil
    if type(raw.label) == "string" and raw.label ~= "" then
        label = raw.label:sub(1, 80)
    end

    return {
        id = id,
        kind = kind,
        mode = mode,
        x = hasFixed and x or nil,
        y = hasFixed and y or nil,
        z = hasFixed and z or nil,
        agentId = agentId,
        toX = hasTo and toX or nil,
        toY = hasTo and toY or nil,
        toZ = hasTo and toZ or nil,
        toAgentId = toAgentId,
        label = label,
        color = parseColor(raw.color, kind),
        size = size,
        showDistance = not isFalse(raw.showDistance),
        expiresAt = ttlMs > 0 and (getTickCount() + ttlMs) or nil,
    }
end

---@param payload table
---@return table
local function setIndications(payload)
    local rawItems, itemsErr
    if payload.items ~= nil then
        rawItems, itemsErr = coerceItems(payload.items)
        if itemsErr then
            return { ok = false, error = itemsErr }
        end
        if not rawItems then
            return { ok = false, error = "items is invalid" }
        end
    else
        rawItems = coerceItems(payload)
        if not rawItems then
            return { ok = false, error = "x, y, z or agentId is required" }
        end
    end

    local fallbackMs = explicitTimeoutMs(payload)
    if fallbackMs == nil then
        fallbackMs = DEFAULT_TIMEOUT_MS
    end

    local accepted = {}
    local rejected = {}
    for index = 1, #rawItems do
        local item, err = sanitizeItem(rawItems[index], fallbackMs)
        if item then
            accepted[#accepted + 1] = item
        else
            rejected[#rejected + 1] = { index = index, error = err or "invalid item" }
        end
    end
    if #accepted == 0 then
        return { ok = false, error = "no valid items", details = { rejected = rejected } }
    end

    if isTrue(payload.replace) then
        byId = {}
        order = {}
    end

    local dropped = {}
    for index = 1, #accepted do
        local item = accepted[index]
        if not item.id then
            seq = seq + 1
            item.id = string.format("ind-%d-%d", getTickCount(), seq)
        end
        local isNew = byId[item.id] == nil
        if isNew then
            while #order >= MAX_INDICATIONS do
                local oldest = table.remove(order, 1)
                if oldest then
                    byId[oldest] = nil
                    dropped[#dropped + 1] = oldest
                else
                    break
                end
            end
            order[#order + 1] = item.id
        end
        byId[item.id] = item
    end

    syncRender()
    local result = snapshot()
    if #rejected > 0 then
        result.rejected = rejected
    end
    if #dropped > 0 then
        result.dropped = dropped
    end
    return { ok = true, result = result }
end

---@param payload table
---@return table
local function clearIndications(payload)
    if isTrue(payload.all) then
        local cleared = #order
        byId = {}
        order = {}
        syncRender()
        return { ok = true, result = { cleared = cleared, count = 0, items = {} } }
    end
    if type(payload.id) ~= "string" or payload.id == "" then
        return { ok = false, error = "id or all is required" }
    end
    if not removeId(payload.id) then
        return { ok = false, error = "notFound" }
    end
    syncRender()
    local result = snapshot()
    result.cleared = 1
    result.id = payload.id
    return { ok = true, result = result }
end

---@param payload table|nil
---@return table
function Agent.handleClientIndicate(payload)
    payload = type(payload) == "table" and payload or {}
    local action = payload.action or "list"
    if action == "set" then
        return setIndications(payload)
    end
    if action == "clear" then
        return clearIndications(payload)
    end
    if action == "list" then
        return { ok = true, result = snapshot() }
    end
    return { ok = false, error = "action must be set, clear, or list" }
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if rendering then
        removeEventHandler("onClientRender", root, renderIndications)
        rendering = false
    end
    byId = {}
    order = {}
end)
