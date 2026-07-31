--- Client-side on-screen element scanning and camera look-target resolution.

---@param value number
---@param places integer|nil
---@return number rounded
local function roundNumber(value, places)
    local scale = 10 ^ (places or 1)
    return math.floor(value * scale + 0.5) / scale
end

---@param x number
---@param y number
---@param z number
---@return AgentVec3
local function positionTableFrom(x, y, z)
    return { x = x, y = y, z = z }
end

---@return AgentCameraState
local function getCameraState()
    local camX, camY, camZ, lookX, lookY, lookZ = getCameraMatrix()
    local dx, dy, dz = lookX - camX, lookY - camY, lookZ - camZ
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    local forward

    if length > 0.001 then
        forward = {
            x = dx / length,
            y = dy / length,
            z = dz / length,
        }
    end

    local screenW, screenH = guiGetScreenSize()
    return {
        position = positionTableFrom(camX, camY, camZ),
        lookAt = positionTableFrom(lookX, lookY, lookZ),
        forward = forward,
        viewport = {
            width = screenW,
            height = screenH,
        },
    }
end

---@param props AgentVisibleElementProps|table|nil
---@param element element
---@param camera AgentCameraState
---@return nil
local function addCameraAngleDebug(props, element, camera)
    local forward = camera.forward
    if not props or not props.debug or not forward then
        return
    end

    local camX, camY, camZ = camera.position.x, camera.position.y, camera.position.z
    local ex, ey, ez = getElementPosition(element)
    local toX, toY, toZ = ex - camX, ey - camY, ez - camZ
    local toLength = math.sqrt(toX * toX + toY * toY + toZ * toZ)
    if toLength <= 0.001 then
        return
    end

    local dot = (toX / toLength) * forward.x + (toY / toLength) * forward.y + (toZ / toLength) * forward.z
    dot = math.max(-1, math.min(1, dot))
    props.debug.cameraAngle = roundNumber(math.deg(math.acos(dot)), 1)
end

---@param originElement element
---@param targetElement element
---@return boolean clear
local function hasLineOfSight(originElement, targetElement)
    local ox, oy, oz = getElementPosition(originElement)
    local tx, ty, tz = getElementPosition(targetElement)
    return isLineOfSightClear(
        ox, oy, oz + 0.5,
        tx, ty, tz + 0.5,
        true, false, false, true, false, false, false,
        targetElement
    )
end

---@param element element
---@return AgentScreenDebug
local function buildScreenDebug(element)
    local x, y, z = getElementPosition(element)
    local screenX, screenY = getScreenFromWorldPosition(x, y, z, 0.05, true)
    if not screenX then
        return {
            onScreen = false,
        }
    end

    local screenW, screenH = guiGetScreenSize()
    local normalizedX = roundNumber(screenX, 4)
    local normalizedY = roundNumber(screenY, 4)
    return {
        onScreen = true,
        normalized = {
            x = normalizedX,
            y = normalizedY,
        },
        pixels = {
            x = math.floor(screenX * screenW),
            y = math.floor(screenY * screenH),
        },
        centerDistance = roundNumber(math.sqrt((normalizedX - 0.5) ^ 2 + (normalizedY - 0.5) ^ 2), 4),
    }
end

---@param originElement element
---@param element element
---@param distance number
---@param options AgentVisibleOptions|AgentLookOptions
---@param camera AgentCameraState|nil
---@return AgentVisibleElementProps|nil props
local function buildElementDebug(originElement, element, distance, options, camera)
    local rawProps = Agent.describeNearbyElement(element, distance)
    if not rawProps then
        return nil
    end

    ---@type AgentVisibleElementProps
    local props = rawProps --[[@as AgentVisibleElementProps]]

    local onScreen = isElementOnScreen(element)
    local streamedIn = isElementStreamedIn(element)
    local screen = buildScreenDebug(element)
    local visible = onScreen and screen.onScreen

    props.debug = {
        visible = visible,
        onScreen = onScreen,
        streamedIn = streamedIn,
        alpha = getElementAlpha(element),
        screen = screen,
        dimension = getElementDimension(element),
        interior = getElementInterior(element),
    }

    if options.lineOfSight then
        props.debug.lineOfSight = hasLineOfSight(originElement, element)
    end

    if type(getElementCollisionsEnabled) == "function" then
        props.debug.collisionsEnabled = getElementCollisionsEnabled(element)
    end

    if camera then
        addCameraAngleDebug(props, element, camera)
    end

    if options.autoTrack == true and type(Agent.attachAgentIdToProps) == "function" then
        Agent.attachAgentIdToProps(props, element, {
            autoTrack = true,
            trackSource = options.trackSource or "visible",
        })
    end

    return props
end

---@param camera AgentCameraState
---@param maxDistance number
---@param origin element
---@param options AgentLookOptions
---@return AgentVisibleElementProps|table|nil item
---@return "raycast"|"screenCenter"|nil method
local function raycastFromCamera(camera, maxDistance, origin, options)
    local forward = camera.forward
    if not forward then
        return nil
    end

    local camX, camY, camZ = camera.position.x, camera.position.y, camera.position.z
    local endX = camX + forward.x * maxDistance
    local endY = camY + forward.y * maxDistance
    local endZ = camZ + forward.z * maxDistance

    local hit, hitX, hitY, hitZ, hitElement = processLineOfSight(
        camX, camY, camZ,
        endX, endY, endZ,
        true, true, true, true, false, false, false, false,
        origin
    )

    if not hit then
        return nil
    end

    if hitElement and isElement(hitElement) then
        local ox, oy, oz = getElementPosition(origin)
        local ex, ey, ez = getElementPosition(hitElement)
        local distance = getDistanceBetweenPoints3D(ox, oy, oz, ex, ey, ez)
        local item = buildElementDebug(origin, hitElement, distance, options, camera)
        if item then
            item.debug.lookMethod = "raycast"
            item.debug.hitPosition = positionTableFrom(hitX, hitY, hitZ)
        end
        return item, "raycast"
    end

    return {
        elementType = "world",
        id = "world",
        debug = {
            lookMethod = "raycast",
            hitPosition = positionTableFrom(hitX, hitY, hitZ),
        },
    }, "raycast"
end

---@param origin element
---@param camera AgentCameraState
---@param options AgentLookOptions
---@return AgentVisibleElementProps|nil item
---@return "raycast"|"screenCenter"|nil method
local function pickScreenCenterTarget(origin, camera, options)
    local types = Agent.normalizeNearbyTypes(options)
    local maxDistance = options.maxDistance
    local screenCenterMax = tonumber(options.screenCenterMax) or 0.35
    local maxCameraAngle = tonumber(options.maxCameraAngle) or 25

    local ox, oy, oz = getElementPosition(origin)
    local originDimension = getElementDimension(origin)
    local originInterior = getElementInterior(origin)

    local bestItem
    local bestScore

    for i = 1, #types do
        local elementType = types[i]
        if type(elementType) == "string" then
            for _, element in ipairs(getElementsByType(elementType)) do
                if isElement(element) and element ~= origin
                    and isElementStreamedIn(element)
                    and isElementOnScreen(element)
                    and getElementDimension(element) == originDimension
                    and getElementInterior(element) == originInterior then
                    local ex, ey, ez = getElementPosition(element)
                    local distance = getDistanceBetweenPoints3D(ox, oy, oz, ex, ey, ez)
                    if not maxDistance or distance <= maxDistance then
                        local item = buildElementDebug(origin, element, distance, options, camera)
                        if item and item.debug.visible and item.debug.screen.onScreen then
                            local centerDistance = item.debug.screen.centerDistance or 1
                            local cameraAngle = item.debug.cameraAngle or 180
                            if centerDistance <= screenCenterMax and cameraAngle <= maxCameraAngle then
                                local score = centerDistance * 2 + cameraAngle / 90
                                if not bestScore or score < bestScore then
                                    bestScore = score
                                    bestItem = item
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if bestItem then
        bestItem.debug.lookMethod = "screenCenter"
    end

    return bestItem, "screenCenter"
end

---@param options AgentLookOptions|table|nil
---@return AgentHttpPayload response `{ ok = true, result: AgentLookResult }` or `{ ok = false, error }`
function getLookTarget(options)
    options = type(options) == "table" and options or {}
    local origin = localPlayer
    if not isElement(origin) then
        return { ok = false, error = "localPlayer unavailable" }
    end

    local maxDistance = tonumber(options.maxDistance) or 300
    local camera = getCameraState()
    local ox, oy, oz = getElementPosition(origin)

    local lookingAt, method = raycastFromCamera(camera, maxDistance, origin, options)
    if not lookingAt or lookingAt.elementType == "world" then
        local screenTarget, screenMethod = pickScreenCenterTarget(origin, camera, options)
        if screenTarget then
            lookingAt = screenTarget
            method = screenMethod
        elseif lookingAt and lookingAt.elementType == "world" then
            method = "raycast"
        else
            lookingAt = nil
            method = nil
        end
    end

    if options.debugLog and lookingAt then
        outputDebugString(
            "[agent-look] " .. tostring(lookingAt.elementType or "none")
            .. " method=" .. tostring(method)
            .. " id=" .. tostring(lookingAt.id),
            3
        )
    end

    return {
        ok = true,
        result = {
            player = getPlayerName(origin),
            origin = positionTableFrom(ox, oy, oz),
            camera = camera,
            method = method,
            lookingAt = lookingAt,
        },
    }
end

---@param item AgentVisibleElementProps
---@return nil
local function logVisibleElement(item)
    local debugInfo = item.debug or {}
    local screen = debugInfo.screen or {}
    local normalized = screen.normalized or {}
    local label = string.format(
        "[agent-visible] %s dist=%sm visible=%s screen=(%.2f, %.2f) id=%s",
        tostring(item.elementType),
        tostring(item.distance),
        tostring(debugInfo.visible),
        tonumber(normalized.x) or -1,
        tonumber(normalized.y) or -1,
        tostring(item.id)
    )
    outputDebugString(label, 3)
end

---@param options AgentVisibleOptions|table|nil
---@return AgentHttpPayload response `{ ok = true, result: AgentVisibleResult }` or `{ ok = false, error }`
function getVisibleElements(options)
    options = type(options) == "table" and options or {}
    local origin = localPlayer
    if not isElement(origin) then
        return { ok = false, error = "localPlayer unavailable" }
    end

    local types = Agent.normalizeNearbyTypes(options)
    local limit = tonumber(options.limit) or 25
    if limit < 1 then
        limit = 1
    end

    local maxDistance = options.maxDistance
    local includeOffScreen = options.includeOffScreen == true
    local onlyVisible = options.onlyVisible ~= false
    local debugLog = options.debugLog == true
    local camera = getCameraState()

    local ox, oy, oz = getElementPosition(origin)
    local originDimension = getElementDimension(origin)
    local originInterior = getElementInterior(origin)

    local matches = {}
    local stats = {
        scanned = 0,
        streamedIn = 0,
        onScreen = 0,
        visible = 0,
        returned = 0,
    }

    for i = 1, #types do
        local elementType = types[i]
        if type(elementType) == "string" then
            for _, element in ipairs(getElementsByType(elementType)) do
                if isElement(element) and element ~= origin then
                    stats.scanned = stats.scanned + 1

                    if getElementDimension(element) ~= originDimension
                        or getElementInterior(element) ~= originInterior then
                    elseif not isElementStreamedIn(element) then
                    else
                        stats.streamedIn = stats.streamedIn + 1

                        local ex, ey, ez = getElementPosition(element)
                        local distance = getDistanceBetweenPoints3D(ox, oy, oz, ex, ey, ez)
                        if maxDistance and distance > maxDistance then
                        else
                            local onScreen = isElementOnScreen(element)
                            if onScreen then
                                stats.onScreen = stats.onScreen + 1
                            end

                            local screen = buildScreenDebug(element)
                            local visible = onScreen and screen.onScreen

                            if visible then
                                stats.visible = stats.visible + 1
                            end

                            if options.lineOfSight and not hasLineOfSight(origin, element) then
                            elseif onlyVisible and not visible then
                            elseif not includeOffScreen and not onScreen then
                            else
                                local item = buildElementDebug(origin, element, distance, options, camera)
                                if item then
                                    matches[#matches + 1] = {
                                        distance = distance,
                                        item = item,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(matches, function(a, b)
        return a.distance < b.distance
    end)

    local results = {}
    local resultCount = math.min(limit, #matches)
    for index = 1, resultCount do
        results[index] = matches[index].item
        if debugLog then
            logVisibleElement(results[index])
        end
    end
    stats.returned = resultCount

    local lookResult = getLookTarget(options)
    local lookingAt = lookResult.ok and lookResult.result.lookingAt or nil
    local lookMethod = lookResult.ok and lookResult.result.method or nil

    return {
        ok = true,
        result = {
            player = getPlayerName(origin),
            origin = positionTableFrom(ox, oy, oz),
            camera = camera,
            method = lookMethod,
            lookingAt = lookingAt,
            stats = stats,
            elements = results,
        },
    }
end
