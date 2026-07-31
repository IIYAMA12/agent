--- Resolve players by name or serial.
---@class Agent
Agent = Agent or {}

Agent.SERIAL_LENGTH = 32

---@param text any
---@return boolean
function Agent.isPlayerSerial(text)
    if type(text) ~= "string" then
        return false
    end

    text = text:gsub("%s+", "")
    return #text == Agent.SERIAL_LENGTH and text:match("^[%x]+$") ~= nil
end

---@param serial any
---@return string|nil
function Agent.normalizePlayerSerial(serial)
    if type(serial) ~= "string" then
        return nil
    end

    serial = serial:gsub("%s+", ""):lower()
    if not Agent.isPlayerSerial(serial) then
        return nil
    end

    return serial
end

---@param serial string|nil
---@return player|nil
function Agent.getPlayerFromSerial(serial)
    serial = Agent.normalizePlayerSerial(serial)
    if not serial then
        return nil
    end

    for _, player in ipairs(getElementsByType("player")) do
        if isElement(player) and getPlayerSerial(player):lower() == serial then
            return player
        end
    end

    return nil
end

---@param player player|element|nil
---@return AgentPlayerInfo|nil
function Agent.describePlayer(player)
    if not isElement(player) or getElementType(player) ~= "player" then
        return nil
    end

    return {
        name = getPlayerName(player),
        serial = getPlayerSerial(player),
    }
end

---@return AgentPlayerInfo[]
function Agent.listOnlinePlayers()
    local players = getElementsByType("player")
    local listed = {}

    for i = 1, #players do
        local info = Agent.describePlayer(players[i])
        if info then
            listed[#listed + 1] = info
        end
    end

    return listed
end

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|nil
---@return player|nil
---@return string|nil err
function Agent.resolvePlayerElement(playerName, options)
    options = type(options) == "table" and options or {}

    local serial = Agent.normalizePlayerSerial(options.serial)
    if serial then
        local player = Agent.getPlayerFromSerial(serial)
        if player then
            return player
        end
        return nil, "Player not found for serial: " .. serial
    end

    if type(playerName) == "string" and playerName ~= "" and playerName ~= "*" then
        if Agent.isPlayerSerial(playerName) then
            local player = Agent.getPlayerFromSerial(playerName)
            if player then
                return player
            end
            return nil, "Player not found for serial: " .. playerName
        end

        local player = getPlayerFromName(playerName)
        if player then
            return player
        end
        return nil, "Player not found: " .. playerName
    end

    local players = getElementsByType("player")
    if #players == 0 then
        return nil, "No players online"
    end

    return players[1]
end

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|nil
---@return string|nil
---@return string|nil err
function Agent.resolvePlayerName(playerName, options)
    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return nil, err
    end
    return getPlayerName(player)
end

---@param playerName string|nil
---@param options AgentResolvePlayerOptions|nil
---@return AgentPlayerInfo|nil
---@return string|nil err
function Agent.resolvePlayerInfo(playerName, options)
    local player, err = Agent.resolvePlayerElement(playerName, options)
    if not player then
        return nil, err
    end
    return Agent.describePlayer(player)
end
