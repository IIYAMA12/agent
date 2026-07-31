--- Teleport helpers: to map areas, to other players/elements, or to explicit coordinates.
---@class Agent
Agent = Agent or {}

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return player|nil, string|nil error
local function resolvePlayer(playerName, options)
    return Agent.resolvePlayerElement(playerName, options)
end

---@param player player
---@param area AgentArea|table
---@param distance number
---@param px number
---@param py number
---@param pz number
---@param inVehicle boolean
---@return table
local function buildTeleportResult(player, area, distance, px, py, pz, inVehicle)
    return {
        player = getPlayerName(player),
        location = area.name,
        locationId = area.id,
        category = area.category,
        region = area.region,
        distance = distance,
        from = { x = px, y = py, z = pz },
        to = { x = area.x, y = area.y, z = area.z },
        inVehicle = inVehicle,
        airport = area.category == "airport" and area.name or nil,
        airportId = area.category == "airport" and area.id or nil,
    }
end

---@param playerName string|nil
---@param options AgentAreaFilters|AgentResolvePlayerOptions|table|nil
---@return boolean ok
---@return table|string|nil result
function Agent.findClosestAreaFromPlayer(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    local px, py, pz = getElementPosition(player)
    local area, distanceOrError = Agent.findClosestArea(px, py, pz, options)
    if not area then
        return false, type(distanceOrError) == "string" and distanceOrError or "No matching area"
    end

    return true, {
        player = getPlayerName(player),
        origin = { x = px, y = py, z = pz },
        location = Agent.describeArea(area),
        distance = distanceOrError,
    }
end

---@param playerName string|nil
---@param options AgentTeleportAreaOptions|table|nil
---@return boolean ok
---@return table|string|nil result
function Agent.teleportToArea(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    local px, py, pz = getElementPosition(player)
    local area, distanceOrError = Agent.findClosestArea(px, py, pz, options)
    if not area then
        return false, type(distanceOrError) == "string" and distanceOrError or "No matching area"
    end

    ---@type number
    local distance = distanceOrError --[[@as number]]
    local includeVehicle = options.includeVehicle ~= false
    local vehicle = includeVehicle and getPedOccupiedVehicle(player) or nil
    local target = vehicle or player
    local rotation = tonumber(options.rotation) or area.rotation or 0

    setElementPosition(target, area.x, area.y, area.z)
    setElementVelocity(target, 0, 0, 0)
    setElementRotation(target, 0, 0, rotation)

    if options.interior ~= nil then
        setElementInterior(target, options.interior)
    end
    if options.dimension ~= nil then
        setElementDimension(target, options.dimension)
    end

    return true, buildTeleportResult(player, area, distance, px, py, pz, vehicle ~= nil)
end

---@param playerName string|nil
---@param options AgentTeleportAreaOptions|table|nil
---@return boolean ok
---@return table|string|nil result
function Agent.teleportToClosestAirport(playerName, options)
    options = type(options) == "table" and options or {}
    if options.airportId and not options.locationId then
        options.locationId = options.airportId
    end
    if not options.locationId then
        options.category = "airport"
    end
    return Agent.teleportToArea(playerName, options)
end

---@param distance number
---@return number
local function roundDistance(distance)
    return math.floor(distance * 10 + 0.5) / 10
end

---@param options AgentTeleportElementOptions|table
---@return string|nil
local function normalizeTargetName(options)
    return options.targetPlayer
        or options.toPlayer
        or options.target
        or options.playerTarget
end

---@param element element
---@param options AgentTeleportElementOptions|table
---@return boolean
local function elementMatchesQuery(element, options)
    local model = options.model
    if model ~= nil then
        model = tonumber(model)
        if model then
            local elementType = getElementType(element)
            if elementType == "vehicle" or elementType == "ped" or elementType == "object" then
                if getElementModel(element) ~= model then
                    return false
                end
            else
                return false
            end
        end
    end

    local search = options.name or options.search
    if type(search) == "string" and search ~= "" then
        search = search:lower()
        local elementType = getElementType(element)
        if elementType == "player" then
            if not getPlayerName(element):lower():find(search, 1, true) then
                return false
            end
        elseif elementType == "vehicle" then
            local vehicleName
            if type(getVehicleNameFromModel) == "function" then
                vehicleName = getVehicleNameFromModel(getElementModel(element))
            end
            if not vehicleName or not vehicleName:lower():find(search, 1, true) then
                return false
            end
        else
            return false
        end
    end

    return true
end

---@param originElement element
---@param options AgentTeleportElementOptions|table|nil
---@return element|nil element, number|string distanceOrError
local function scanClosestElement(originElement, options)
    if not isElement(originElement) then
        return nil, "Origin element is invalid"
    end

    options = type(options) == "table" and options or {}
    local types = Agent.normalizeNearbyTypes(options)
    local maxDistance = options.maxDistance
    local originDimension = getElementDimension(originElement)
    local originInterior = getElementInterior(originElement)
    local ox, oy, oz = getElementPosition(originElement)

    local closestElement
    local closestDistance

    for i = 1, #types do
        local elementType = types[i]
        for _, element in ipairs(getElementsByType(elementType)) do
            if isElement(element)
                and element ~= originElement
                and getElementDimension(element) == originDimension
                and getElementInterior(element) == originInterior
                and elementMatchesQuery(element, options) then
                local ex, ey, ez = getElementPosition(element)
                local distance = getDistanceBetweenPoints3D(ox, oy, oz, ex, ey, ez)

                if (not maxDistance or distance <= maxDistance)
                    and (not closestDistance or distance < closestDistance) then
                    closestDistance = distance
                    closestElement = element
                end
            end
        end
    end

    if not closestElement then
        return nil, "No matching elements found"
    end

    return closestElement, roundDistance(closestDistance or 0)
end

---@param fromPlayer player
---@param options AgentTeleportElementOptions|table|nil
---@return element|nil element, string|nil error
local function resolveTargetElement(fromPlayer, options)
    options = type(options) == "table" and options or {}

    local targetName = normalizeTargetName(options)
    if targetName and targetName ~= "" then
        local targetPlayer = getPlayerFromName(targetName)
        if not targetPlayer then
            return nil, "Target player not found: " .. targetName
        end
        if targetPlayer == fromPlayer and options.allowSelf ~= true then
            return nil, "Cannot teleport to yourself"
        end
        return targetPlayer
    end

    if type(options.elementId) == "string" and options.elementId ~= "" then
        local element = getElementByID(options.elementId)
        if element and isElement(element) then
            return element
        end
        return nil, "Element not found for id: " .. options.elementId
    end

    if options.type or options.elementType or options.types or options.model or options.name or options.search then
        local element, distOrErr = scanClosestElement(fromPlayer, options)
        if not element then
            return nil, type(distOrErr) == "string" and distOrErr or "No matching elements found"
        end
        return element
    end

    return nil, "Specify targetPlayer, elementId, or type/model/search to find a target element"
end

---@param element element
---@return number
local function getElementFacingZ(element)
    local _, _, rz = getElementRotation(element)
    if getElementType(element) == "player" or getElementType(element) == "ped" then
        rz = getPedRotation(element)
    end
    return rz or 0
end

---@param targetElement element
---@param options AgentTeleportElementOptions|table
---@return number destX, number destY, number destZ, number rotation
local function computeDestinationPosition(targetElement, options)
    local tx, ty, tz = getElementPosition(targetElement)
    local offset = options.offset

    if type(offset) == "table" then
        return tx + (tonumber(offset.x) or 0),
            ty + (tonumber(offset.y) or 0),
            tz + (tonumber(offset.z) or 0),
            tonumber(options.rotation) or getElementFacingZ(targetElement)
    end

    local offsetDistance = tonumber(options.offsetDistance) or 2.5
    local facing = getElementFacingZ(targetElement)
    local rad = math.rad(facing)
    local dx = -math.sin(rad) * offsetDistance
    local dy = math.cos(rad) * offsetDistance
    local zBump = tonumber(options.offsetZ) or 0.3

    return tx + dx, ty + dy, tz + zBump, tonumber(options.rotation) or facing
end

---@param player player
---@param targetElement element
---@param distance number
---@param px number
---@param py number
---@param pz number
---@param destX number
---@param destY number
---@param destZ number
---@param inVehicle boolean
---@return table
local function buildElementTeleportResult(player, targetElement, distance, px, py, pz, destX, destY, destZ, inVehicle)
    local targetDescription = Agent.describeNearbyElement(targetElement, distance) or {
        elementType = getElementType(targetElement),
        id = tostring(targetElement),
        position = { x = destX, y = destY, z = destZ },
    }

    return {
        player = getPlayerName(player),
        target = targetDescription,
        distance = distance,
        from = { x = px, y = py, z = pz },
        to = { x = destX, y = destY, z = destZ },
        inVehicle = inVehicle,
        interior = getElementInterior(targetElement),
        dimension = getElementDimension(targetElement),
    }
end

---@param traveler element
---@param x number
---@param y number
---@param z number
---@param rotation number|nil
---@param targetElement element
---@param options AgentTeleportElementOptions|table
---@return nil
local function applyTeleportState(traveler, x, y, z, rotation, targetElement, options)
    setElementPosition(traveler, x, y, z)
    setElementVelocity(traveler, 0, 0, 0)
    setElementRotation(traveler, 0, 0, rotation or 0)

    local matchWorld = options.matchWorld
    if matchWorld == nil then
        matchWorld = true
    end

    if matchWorld and isElement(targetElement) then
        setElementInterior(traveler, getElementInterior(targetElement))
        setElementDimension(traveler, getElementDimension(targetElement))
    end

    if options.interior ~= nil then
        setElementInterior(traveler, options.interior)
    end
    if options.dimension ~= nil then
        setElementDimension(traveler, options.dimension)
    end
end

---@param playerName string|nil
---@param options AgentTeleportElementOptions|table|nil
---@return boolean ok
---@return table|string|nil result
function Agent.teleportToElement(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    local targetElement, resolveError = resolveTargetElement(player, options)
    if not targetElement then
        return false, resolveError or "Target not found"
    end

    local px, py, pz = getElementPosition(player)
    local tx, ty, tz = getElementPosition(targetElement)
    local distance = roundDistance(getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz))

    local destX, destY, destZ, rotation = computeDestinationPosition(targetElement, options)
    local includeVehicle = options.includeVehicle ~= false
    local vehicle = includeVehicle and getPedOccupiedVehicle(player) or nil
    local traveler = vehicle or player

    applyTeleportState(traveler, destX, destY, destZ, rotation, targetElement, options)

    return true, buildElementTeleportResult(
        player,
        targetElement,
        distance,
        px,
        py,
        pz,
        destX,
        destY,
        destZ,
        vehicle ~= nil
    )
end

---@param playerName string|nil
---@param targetPlayerName string|nil
---@param options AgentTeleportElementOptions|table|nil
---@return boolean ok
---@return table|string|nil result
function Agent.teleportToPlayer(playerName, targetPlayerName, options)
    options = type(options) == "table" and options or {}
    if type(targetPlayerName) ~= "string" or targetPlayerName == "" then
        return false, "targetPlayer is required"
    end
    options.targetPlayer = targetPlayerName
    return Agent.teleportToElement(playerName, options)
end

---@param playerName string|nil
---@param x number|string|nil
---@param y number|string|nil
---@param z number|string|nil
---@param options AgentTeleportPositionOptions|table|nil
---@return boolean ok
---@return table|string|nil result
function Agent.teleportToPosition(playerName, x, y, z, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    local nx = tonumber(x)
    local ny = tonumber(y)
    local nz = tonumber(z)
    if not nx or not ny or not nz then
        return false, "x, y, z are required"
    end

    local px, py, pz = getElementPosition(player)
    local includeVehicle = options.includeVehicle ~= false
    local vehicle = includeVehicle and getPedOccupiedVehicle(player) or nil
    local traveler = vehicle or player
    local rotation = tonumber(options.rotation) or 0

    setElementPosition(traveler, nx, ny, nz)
    setElementVelocity(traveler, 0, 0, 0)
    setElementRotation(traveler, 0, 0, rotation)

    if options.interior ~= nil then
        setElementInterior(traveler, options.interior)
    end
    if options.dimension ~= nil then
        setElementDimension(traveler, options.dimension)
    end

    return true, {
        player = getPlayerName(player),
        from = { x = px, y = py, z = pz },
        to = { x = nx, y = ny, z = nz },
        inVehicle = vehicle ~= nil,
        distance = roundDistance(getDistanceBetweenPoints3D(px, py, pz, nx, ny, nz)),
    }
end
