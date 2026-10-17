--- Live camera matrix. The server copy of getCameraMatrix is only synced every few seconds.
---@class Agent
Agent = Agent or {}

---@return AgentCameraMatrixResult|nil matrix
---@return string|nil error
function Agent.getClientCameraMatrix()
    local x, y, z, lookAtX, lookAtY, lookAtZ, roll, fov = getCameraMatrix()
    if type(x) ~= "number" then
        return nil, "getCameraMatrix failed"
    end

    return {
        source = "client",
        position = { x = x, y = y, z = z },
        lookAt = { x = lookAtX, y = lookAtY, z = lookAtZ },
        roll = roll,
        fov = fov,
    }
end
