---@alias createVehicle_server fun(model: vehicleId, x: number, y: number, z: number, rx?: number): vehicle
---@alias createVehicle_client fun(model: vehicleId, x: number, y: number, z: number): vehicle
--[[
[Wiki](https://wiki.multitheftauto.com/wiki/CreateVehicle)
]]
---@type createVehicle_server | createVehicle_client
function createVehicle() end

--[[
[Wiki](https://wiki.multitheftauto.com/wiki/GetElementPosition)
]]
---@type fun(theElement: element): x: number, y: number, z: number Returns three floats indicating the position
function getElementPosition() end

---@alias fadeCamera_server (fun(thePlayer: player, fadeIn: boolean, timeToFade?: number): boolean)
---@alias fadeCamera_client (fun(fadeIn: boolean, timeToFade?: number): boolean)
--[[
[Wiki](https://wiki.multitheftauto.com/wiki/FadeCamera)
]]
---@type fadeCamera_server | fadeCamera_client
function fadeCamera() end

---@alias big_1 fun(): boolean
---@alias big_2 fun(): boolean
---@alias big_3 fun(): boolean
---@alias big_4 fun(): boolean
---@alias big_5 fun(): boolean
---@alias big_6 fun(): boolean
---@alias big_7 fun(): boolean
---@alias big_8 fun(): boolean
---@alias big_9 fun(): boolean
---@alias big_10 fun(): boolean
---@alias big_11 fun(): boolean
---@alias big_12 fun(): boolean
---@alias big_13 fun(): boolean
---@alias bigAll big_1 | big_2 | big_3 | big_4 | big_5 | big_6 | big_7 | big_8 | big_9 | big_10 | big_11 | big_12 | big_13
---@type bigAll
function tooBig() end
