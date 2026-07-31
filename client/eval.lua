--- Client-side HTTP bridge entry point for running arbitrary Lua via `Agent.runEval`.

---@param code string Lua source code to execute
---@return AgentHttpPayload response `{ ok = true, result }` on success, `{ ok = false, error }` on failure
function runEval(code)
    local success, value = Agent.runEval(code)
    if success then
        return { ok = true, result = value }
    end
    return { ok = false, error = value }
end
