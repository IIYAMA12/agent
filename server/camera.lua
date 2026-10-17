--- Server-side player camera controls (fade, interior, matrix, target).
---@class Agent
Agent = Agent or {}

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return player|nil, string|nil error
local function resolvePlayer(playerName, options)
    return Agent.resolvePlayerElement(playerName, options)
end

---@param value any
---@return number|nil
local function asNumber(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" and value ~= "" then
        return tonumber(value)
    end
    return nil
end

---@param value any
---@return integer|nil
local function asInt(value)
    local number = asNumber(value)
    if number == nil then
        return nil
    end
    return math.floor(number + 0.5)
end

---@param value any
---@return boolean|nil
local function asBool(value)
    if value == true or value == 1 or value == "1" or value == "true" then
        return true
    end
    if value == false or value == 0 or value == "0" or value == "false" then
        return false
    end
    return nil
end

---@param value any
---@param fallback integer
---@return integer
local function asColor(value, fallback)
    local number = asInt(value)
    if number == nil then
        return fallback
    end
    if number < 0 then
        return 0
    end
    if number > 255 then
        return 255
    end
    return number
end

---@param value any
---@return integer|nil interior
---@return string|nil error
local function asInterior(value)
    local interior = asInt(value)
    if interior == nil then
        return nil, "interior is required"
    end
    if interior < 0 or interior > 255 then
        return nil, "interior must be between 0 and 255"
    end
    return interior
end

---@param text any
---@return boolean
local function isAgentId(text)
    return type(text) == "string" and text:match("^[sc]%-%d+%-%d+$") ~= nil
end

---@param err string|nil
---@param agentId string
---@return string
local function cameraTargetError(err, agentId)
    if err == "staleId" then
        return "Stale agent id (resource restarted): " .. agentId
    end
    if err == "clientIdRequiresBridge" then
        return "Camera target must be a server element (player, ped, or vehicle)"
    end
    if err == "elementDestroyed" then
        return "Camera target element was destroyed"
    end
    if err == "notFound" or err == "invalidId" then
        return "Camera target not found: " .. agentId
    end
    return err or "Camera target not found"
end

---@param element element
---@return boolean
local function isCameraTargetType(element)
    local elementType = getElementType(element)
    return elementType == "player" or elementType == "ped" or elementType == "vehicle"
end

---@param player player
---@param element element
---@return AgentNearbyBaseProps|nil
local function describeCameraTarget(player, element)
    local px, py, pz = getElementPosition(player)
    local tx, ty, tz = getElementPosition(element)
    local distance = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
    return Agent.describeNearbyElement(element, distance)
end

---@param options table
---@return element|nil target
---@return string|nil error
local function resolveCameraTarget(options)
    local agentId = options.agentId
    if type(agentId) ~= "string" or agentId == "" then
        agentId = nil
    end

    local targetName = options.targetPlayer
    if type(targetName) ~= "string" or targetName == "" then
        targetName = options.target
    end
    if type(targetName) ~= "string" or targetName == "" then
        targetName = nil
    end

    if not agentId and isAgentId(targetName) then
        agentId = targetName
        targetName = nil
    end

    if agentId then
        local element, _, err = Agent.resolveElement(agentId)
        if not element then
            return nil, cameraTargetError(err, agentId)
        end
        return element
    end

    if targetName then
        local targetPlayer, err = Agent.resolvePlayerElement(targetName, {})
        if not targetPlayer then
            return nil, err or "Player not found"
        end
        return targetPlayer
    end

    return nil, "target, targetPlayer, or agentId is required"
end

---@param options table
---@return boolean
local function wantsCameraReset(options)
    if asBool(options.reset) == true then
        return true
    end
    local agentId = options.agentId
    local hasAgentId = type(agentId) == "string" and agentId ~= ""
    local target = options.target
    local hasTarget = type(target) == "string" and target ~= ""
    local targetPlayer = options.targetPlayer
    local hasTargetPlayer = type(targetPlayer) == "string" and targetPlayer ~= ""
    return not hasAgentId and not hasTarget and not hasTargetPlayer
end

---@param playerName string|nil
---@param options AgentCameraFadeOptions|table|nil
---@return boolean ok
---@return AgentCameraFadeResult|string result
function Agent.cameraFade(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    local fadeIn = asBool(options.fadeIn)
    if fadeIn == nil then
        return false, "fadeIn must be true or false"
    end

    local time = asNumber(options.time)
    if options.time == nil or options.time == "" then
        time = 1
    end
    if time == nil or time < 0 then
        return false, "time must be a number of seconds >= 0"
    end

    local red = asColor(options.red, 0)
    local green = asColor(options.green, 0)
    local blue = asColor(options.blue, 0)
    local ok = fadeCamera(player, fadeIn, time, red, green, blue)
    if not ok then
        return false, "fadeCamera failed. Server fades must alternate: fade out, then fade in."
    end

    return true, {
        player = Agent.describePlayer(player),
        fadeIn = fadeIn,
        time = time,
        red = red,
        green = green,
        blue = blue,
    }
end

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return boolean ok
---@return AgentCameraInteriorResult|string result
function Agent.cameraGetInterior(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    return true, {
        player = Agent.describePlayer(player),
        interior = getCameraInterior(player),
    }
end

---@param playerName string|nil
---@param options AgentCameraInteriorOptions|table|nil
---@return boolean ok
---@return AgentCameraInteriorResult|string result
function Agent.cameraSetInterior(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    local interior, interiorErr = asInterior(options.interior)
    if not interior then
        return false, interiorErr
    end

    if not setCameraInterior(player, interior) then
        return false, "setCameraInterior failed"
    end

    return true, {
        player = Agent.describePlayer(player),
        interior = interior,
    }
end

--- Live matrix from the client. Server getCameraMatrix is only synced every few seconds.
---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return string|nil id
---@return string|nil error
function Agent.startCameraMatrixFetch(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return nil, err or "Player not found"
    end

    return Agent.startClientRequest(player, "cameraMatrix", {}, {
        timeoutMs = 8000,
        serial = options.serial,
        onComplete = function(request)
            if isElement(player) and type(request.result) == "table" then
                request.result.player = Agent.describePlayer(player)
            end
        end,
    })
end

---@param playerName string|nil
---@param options AgentCameraMatrixOptions|table|nil
---@return boolean ok
---@return AgentCameraMatrixResult|string result
function Agent.cameraSetMatrix(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    local x = asNumber(options.x)
    local y = asNumber(options.y)
    local z = asNumber(options.z)
    if x == nil or y == nil or z == nil then
        return false, "x, y, and z are required"
    end

    local hasLookX = options.lookAtX ~= nil and options.lookAtX ~= ""
    local hasLookY = options.lookAtY ~= nil and options.lookAtY ~= ""
    local hasLookZ = options.lookAtZ ~= nil and options.lookAtZ ~= ""
    local lookAtX, lookAtY, lookAtZ
    local lookAtDefault = false
    if hasLookX or hasLookY or hasLookZ then
        lookAtX = asNumber(options.lookAtX)
        lookAtY = asNumber(options.lookAtY)
        lookAtZ = asNumber(options.lookAtZ)
        if lookAtX == nil or lookAtY == nil or lookAtZ == nil then
            return false, "lookAtX, lookAtY, and lookAtZ are required together"
        end
    else
        lookAtX = x
        lookAtY = y + 1
        lookAtZ = z
        lookAtDefault = true
    end

    local roll = asNumber(options.roll)
    if options.roll == nil or options.roll == "" then
        roll = 0
    end
    if roll == nil or roll < -180 or roll > 180 then
        return false, "roll must be between -180 and 180"
    end

    local fov = asNumber(options.fov)
    if options.fov == nil or options.fov == "" then
        fov = 70
    end
    if fov == nil or fov < 0.01 or fov > 180 then
        return false, "fov must be between 0.01 and 180"
    end

    local interior = nil
    if options.interior ~= nil and options.interior ~= "" then
        local parsedInterior, interiorErr = asInterior(options.interior)
        if not parsedInterior then
            return false, interiorErr
        end
        if not setCameraInterior(player, parsedInterior) then
            return false, "setCameraInterior failed"
        end
        interior = parsedInterior
    end

    if not setCameraMatrix(player, x, y, z, lookAtX, lookAtY, lookAtZ, roll, fov) then
        return false, "setCameraMatrix failed"
    end

    return true, {
        player = Agent.describePlayer(player),
        position = { x = x, y = y, z = z },
        lookAt = { x = lookAtX, y = lookAtY, z = lookAtZ },
        lookAtDefault = lookAtDefault,
        roll = roll,
        fov = fov,
        interior = interior or getCameraInterior(player),
    }
end

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|table|nil
---@return boolean ok
---@return AgentCameraTargetResult|string result
function Agent.cameraGetTarget(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    local target = getCameraTarget(player)
    if not isElement(target) then
        return true, {
            player = Agent.describePlayer(player),
            fixed = true,
        }
    end

    return true, {
        player = Agent.describePlayer(player),
        fixed = false,
        target = describeCameraTarget(player, target),
    }
end

---@param playerName string|nil
---@param options AgentCameraTargetOptions|table|nil
---@return boolean ok
---@return AgentCameraTargetResult|string result
function Agent.cameraSetTarget(playerName, options)
    options = type(options) == "table" and options or {}

    local player, err = resolvePlayer(playerName, options)
    if not player then
        return false, err or "Player not found"
    end

    if wantsCameraReset(options) then
        if not setCameraTarget(player) then
            return false, "setCameraTarget failed"
        end
        return true, {
            player = Agent.describePlayer(player),
            fixed = false,
            reset = true,
            target = describeCameraTarget(player, player),
        }
    end

    local target, targetErr = resolveCameraTarget(options)
    if not target then
        return false, targetErr or "Camera target not found"
    end
    if not isCameraTargetType(target) then
        return false, "Camera target must be a player, ped, or vehicle"
    end
    if not setCameraTarget(player, target) then
        return false, "setCameraTarget failed"
    end

    return true, {
        player = Agent.describePlayer(player),
        fixed = false,
        reset = false,
        target = describeCameraTarget(player, target),
    }
end
