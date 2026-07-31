--- Tracks this resource's granted ACL rights (from requested access) for pre-flight checks before ACL auto-install.

---@type table<string, boolean>
requestedRightAccess = {}

local requests = getResourceACLRequests(getThisResource())
for i = 1, #requests do
    requestedRightAccess[requests[i].name] = requests[i].access
end

---@param list string[]
---@return boolean
function hasAccessToRights(list)
    for i = 1, #list do
        if not requestedRightAccess[list[i]] then
            return false
        end
    end
    return true
end
