--- Shared "closest elements" discovery helpers: describes nearby elements with type-specific props and finds the N closest matches to an origin element.

---@class Agent
Agent = Agent or {}

Agent.NEARBY_DEFAULT_TYPES = { "vehicle", "player", "ped", "object", "pickup", "marker" }

--- Rounds a distance value to one decimal place.
---@param distance number|nil
---@return number|nil
local function roundDistance(distance)
    if type(distance) ~= "number" then
        return nil
    end
    return math.floor(distance * 10 + 0.5) / 10
end

--- Returns an element's position as an {x,y,z} table.
---@param element element
---@return AgentVec3
local function positionTable(element)
    local x, y, z = getElementPosition(element)
    return { x = x, y = y, z = z }
end

--- Returns an element's rotation as an {x,y,z} table.
---@param element element
---@return AgentVec3
local function rotationTable(element)
    local rx, ry, rz = getElementRotation(element)
    return { x = rx, y = ry, z = rz }
end

--- Builds the common base props shared by all discovered element types.
---@param element element
---@param distance number|nil
---@return AgentNearbyBaseProps
local function baseProps(element, distance)
    return {
        elementType = getElementType(element),
        id = tostring(element),
        distance = roundDistance(distance),
        position = positionTable(element),
        dimension = getElementDimension(element),
        interior = getElementInterior(element),
    }
end

--- Resolves a vehicle model id to its display name, if the API is available.
---@param model integer
---@return string|nil
local function vehicleNameFromModel(model)
    if type(getVehicleNameFromModel) == "function" then
        return getVehicleNameFromModel(model)
    end
    return nil
end

--- Describes a vehicle element with vehicle-specific props.
---@param vehicle vehicle
---@param distance number|nil
---@return AgentNearbyVehicleProps
local function describeVehicle(vehicle, distance)
    local props = baseProps(vehicle, distance)
    ---@cast props AgentNearbyVehicleProps
    local model = getElementModel(vehicle)
    props.model = model
    props.name = vehicleNameFromModel(model)
    props.health = getElementHealth(vehicle)
    props.locked = isVehicleLocked(vehicle)
    props.engine = getVehicleEngineState(vehicle)
    props.plate = getVehiclePlateText(vehicle)
    props.rotation = rotationTable(vehicle)
    props.occupants = #getVehicleOccupants(vehicle)
    return props
end

--- Describes a player element with player-specific props.
---@param player player
---@param distance number|nil
---@return AgentNearbyPlayerProps
local function describePlayer(player, distance)
    local props = baseProps(player, distance)
    ---@cast props AgentNearbyPlayerProps
    props.name = getPlayerName(player)
    props.health = getElementHealth(player)
    props.armor = getPedArmor(player)
    props.ping = getPlayerPing(player)
    props.team = getPlayerTeam(player) and getTeamName(getPlayerTeam(player)) or nil
    props.weapon = getPedWeapon(player)
    props.inVehicle = isPedInVehicle(player)
    if props.inVehicle then
        local vehicle = getPedOccupiedVehicle(player)
        if vehicle then
            props.vehicle = {
                id = tostring(vehicle),
                model = getElementModel(vehicle),
            }
        end
    end
    return props
end

--- Describes a ped element with ped-specific props.
---@param ped ped
---@param distance number|nil
---@return AgentNearbyPedProps
local function describePed(ped, distance)
    local props = baseProps(ped, distance)
    ---@cast props AgentNearbyPedProps
    props.model = getElementModel(ped)
    props.health = getElementHealth(ped)
    props.inVehicle = isPedInVehicle(ped)
    return props
end

--- Describes an object element with object-specific props.
---@param object object
---@param distance number|nil
---@return AgentNearbyObjectProps
local function describeObject(object, distance)
    local props = baseProps(object, distance)
    ---@cast props AgentNearbyObjectProps
    props.model = getElementModel(object)
    props.rotation = rotationTable(object)
    return props
end

--- Describes a pickup element with pickup-specific props.
---@param pickup pickup
---@param distance number|nil
---@return AgentNearbyPickupProps
local function describePickup(pickup, distance)
    local props = baseProps(pickup, distance)
    ---@cast props AgentNearbyPickupProps
    props.pickupType = getPickupType(pickup)
    props.amount = getPickupAmount(pickup)
    local weapon = getPickupWeapon(pickup)
    if weapon then
        props.weapon = weapon
    end
    return props
end

--- Describes a marker element with marker-specific props.
---@param marker marker
---@param distance number|nil
---@return AgentNearbyMarkerProps
local function describeMarker(marker, distance)
    local props = baseProps(marker, distance)
    ---@cast props AgentNearbyMarkerProps
    props.markerType = getMarkerType(marker)
    props.size = getMarkerSize(marker)
    return props
end

--- Dispatches to the type-specific describe function for a discovered element.
---@param element element|nil
---@param distance number|nil
---@return AgentNearbyProps|nil
function Agent.describeNearbyElement(element, distance)
    if not isElement(element) then
        return nil
    end
    ---@cast element element

    local elementType = getElementType(element)
    if elementType == "vehicle" then
        return describeVehicle(element, distance)
    end
    if elementType == "player" then
        return describePlayer(element, distance)
    end
    if elementType == "ped" then
        return describePed(element, distance)
    end
    if elementType == "object" then
        return describeObject(element, distance)
    end
    if elementType == "pickup" then
        return describePickup(element, distance)
    end
    if elementType == "marker" then
        return describeMarker(element, distance)
    end

    return baseProps(element, distance)
end

--- Normalizes the requested element type(s) from nearby options into a list.
---@param options AgentNearbyOptions|table|nil
---@return string[] types
local function normalizeTypes(options)
    if type(options) ~= "table" then
        return Agent.NEARBY_DEFAULT_TYPES
    end

    if type(options.types) == "table" and #options.types > 0 then
        return options.types
    end

    if type(options.type) == "string" and options.type ~= "" and options.type ~= "*" then
        return { options.type }
    end

    return Agent.NEARBY_DEFAULT_TYPES
end

--- Determines whether a candidate element should be excluded from nearby results (self, dimension mismatch handled elsewhere, or too far).
---@param element element
---@param originElement element
---@param options AgentNearbyOptions|table
---@return boolean exclude
local function shouldExcludeElement(element, originElement, options)
    if not isElement(element) then
        return true
    end

    if originElement and element == originElement then
        if options.excludeSelf ~= false then
            return true
        end
    end

    if originElement and isElement(originElement) and getElementType(originElement) == "player" then
        if getElementType(element) == "player" and element == originElement and options.excludeSelf ~= false then
            return true
        end
    end

    local maxDistance = options.maxDistance
    if maxDistance then
        local ox, oy, oz = getElementPosition(originElement)
        local ex, ey, ez = getElementPosition(element)
        if getDistanceBetweenPoints3D(ox, oy, oz, ex, ey, ez) > maxDistance then
            return true
        end
    end

    return false
end

--- Finds the closest matching elements to `originElement`, sorted by distance (optionally per-type).
---@param originElement element
---@param options AgentNearbyOptions|table|nil
---@return boolean ok
---@return AgentNearbyProps[]|string results Results list on success, error message on failure.
function Agent.findClosestElements(originElement, options)
    if not isElement(originElement) then
        return false, "Origin element is invalid"
    end

    options = type(options) == "table" and options or {}
    local types = normalizeTypes(options)
    local limit = tonumber(options.limit) or 1
    if limit < 1 then
        limit = 1
    end

    local originDimension = getElementDimension(originElement)
    local originInterior = getElementInterior(originElement)
    local ox, oy, oz = getElementPosition(originElement)

    local matches = {}

    for i = 1, #types do
        local elementType = types[i]
        if type(elementType) == "string" then
            for _, element in ipairs(getElementsByType(elementType)) do
                if not shouldExcludeElement(element, originElement, options)
                    and getElementDimension(element) == originDimension
                    and getElementInterior(element) == originInterior then
                    local ex, ey, ez = getElementPosition(element)
                    local distance = getDistanceBetweenPoints3D(ox, oy, oz, ex, ey, ez)
                    matches[#matches + 1] = {
                        element = element,
                        distance = distance,
                    }
                end
            end
        end
    end

    table.sort(matches, function(a, b)
        return a.distance < b.distance
    end)

    if options.perType then
        local perTypeLimit = tonumber(options.perTypeLimit) or 1
        local byType = {}
        local results = {}

        for i = 1, #matches do
            local entry = matches[i]
            local elementType = getElementType(entry.element)
            local bucket = byType[elementType]
            if not bucket then
                bucket = { count = 0 }
                byType[elementType] = bucket
            end
            if bucket.count < perTypeLimit then
                bucket.count = bucket.count + 1
                results[#results + 1] = Agent.describeNearbyElement(entry.element, entry.distance)
            end
        end

        table.sort(results, function(a, b)
            return a.distance < b.distance
        end)

        return true, results
    end

    local results = {}
    local resultCount = math.min(limit, #matches)
    for i = 1, resultCount do
        local entry = matches[i]
        results[i] = Agent.describeNearbyElement(entry.element, entry.distance)
    end

    return true, results
end

--- Resolves a player by name/serial and finds the closest matching elements around them.
---@param playerName string|nil
---@param options AgentNearbyOptions|table|nil
---@return boolean ok
---@return AgentNearbyResult|string|nil result Result table on success, error message (or nil) on failure.
function Agent.findClosestFromPlayer(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return false, err
    end

    local success, results = Agent.findClosestElements(player, options)
    if not success then
        return false, results
    end
    ---@cast results AgentNearbyProps[]

    if options.autoTrack == true then
        Agent.autoTrackDiscoveryResults(results, {
            autoTrack = true,
            trackSource = options.trackSource or "findNearby",
        })
    end

    return true, {
        player = getPlayerName(player),
        origin = positionTable(player),
        results = results,
    }
end
