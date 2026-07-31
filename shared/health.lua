--- Shared health/performance collection helpers: memory, network, CPU, and getPerformanceStats snapshots for server/client.

---@class Agent
Agent = Agent or {}
---@class AgentHealthNS
Agent.Health = Agent.Health or {}

local Health = Agent.Health
local MIB = 1024 * 1024

--- Normalizes raw getProcessMemoryStats output, adding MiB-converted fields.
---@param stats table|nil Raw stats with virtual/resident/shared/private byte counts.
---@return table|nil
function Health.normalizeMemory(stats)
    if type(stats) ~= "table" then
        return nil
    end

    --- Converts a byte count to MiB, rounded to 2 decimal places.
    ---@param bytes number|nil
    ---@return number|nil
    local function mib(bytes)
        if type(bytes) ~= "number" then
            return nil
        end
        return math.floor((bytes / MIB) * 100 + 0.5) / 100
    end

    return {
        virtual = stats.virtual,
        resident = stats.resident,
        shared = stats.shared,
        private = stats.private,
        virtualMiB = mib(stats.virtual),
        residentMiB = mib(stats.resident),
        sharedMiB = mib(stats.shared),
        privateMiB = mib(stats.private),
    }
end

--- Converts parallel getPerformanceStats columns/rows arrays into an array of column-keyed row objects.
---@param columns string[]
---@param rows table[]
---@return { columns: string[], rows: table[], rowCount: integer }
function Health.formatPerformanceTable(columns, rows)
    columns = type(columns) == "table" and columns or {}
    rows = type(rows) == "table" and rows or {}

    local formattedRows = {}
    for i = 1, #rows do
        local row = rows[i]
        local obj = {}
        for j = 1, #columns do
            obj[columns[j]] = row[j]
        end
        formattedRows[#formattedRows + 1] = obj
    end

    return {
        columns = columns,
        rows = formattedRows,
        rowCount = #formattedRows,
    }
end

--- Lists available getPerformanceStats categories (queried via the empty-string category).
---@return { columns: string[], rows: table[], rowCount: integer }|nil
function Health.listPerformanceCategories()
    if type(getPerformanceStats) ~= "function" then
        return nil
    end

    local columns, rows = getPerformanceStats("")
    if type(columns) ~= "table" then
        return nil
    end
    if type(rows) ~= "table" then
        rows = {}
    end

    local categories = {}
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" then
            categories[#categories + 1] = row[1]
        end
    end

    return Health.formatPerformanceTable(columns, rows)
end

--- Collects a formatted getPerformanceStats table for the given category.
---@param category string
---@param perfOptions string|nil
---@param filter string|nil
---@return { columns: string[], rows: table[], rowCount: integer }|nil
function Health.collectPerformance(category, perfOptions, filter)
    if type(getPerformanceStats) ~= "function" then
        return nil
    end
    if type(category) ~= "string" or category == "" then
        return nil
    end

    perfOptions = type(perfOptions) == "string" and perfOptions or ""
    filter = type(filter) == "string" and filter or ""

    local columns, rows = getPerformanceStats(category, perfOptions, filter)
    if type(columns) ~= "table" then
        return nil
    end
    if type(rows) ~= "table" then
        rows = {}
    end

    return Health.formatPerformanceTable(columns, rows)
end

--- Summarizes getNetworkUsageData into the top N in/out entries by packet count.
---@param data table|nil Raw network usage data with `in`/`out` tables of count/bits maps.
---@param limit integer|nil Defaults to 10.
---@return table<string, { top: table[], activeIds: integer }>|nil
function Health.summarizeNetworkUsage(data, limit)
    if type(data) ~= "table" then
        return nil
    end

    limit = tonumber(limit) or 10
    local summary = {}

    for _, direction in ipairs({ "in", "out" }) do
        local dir = data[direction]
        if type(dir) == "table" then
            local counts = dir.count or {}
            local bits = dir.bits or {}
            local entries = {}

            for id, count in pairs(counts) do
                count = tonumber(count) or 0
                if count > 0 then
                    entries[#entries + 1] = {
                        id = id,
                        count = count,
                        bits = tonumber(bits[id]) or 0,
                    }
                end
            end

            table.sort(entries, function(a, b)
                if a.count ~= b.count then
                    return a.count > b.count
                end
                return a.bits > b.bits
            end)

            local top = {}
            for i = 1, math.min(#entries, limit) do
                top[i] = entries[i]
            end

            summary[direction] = {
                top = top,
                activeIds = #entries,
            }
        end
    end

    return summary
end

--- Calls `fn(...)` inside pcall, returning its result or nil on error/invalid function.
---@param fn function|nil
---@param ... any
---@return any|nil
function Health.safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

--- Parses a percentage value from a number or a "NN.N%"/"NN.N" style string.
---@param text string|number|nil
---@return number|nil
function Health.parsePercentValue(text)
    if type(text) == "number" then
        return text
    end
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local value = text:match("(%d+%.?%d*)%%") or text:match("^(%d+%.?%d*)$")
    return value and tonumber(value) or nil
end

--- Parses a CPU stat string (e.g. "12.3% Avg: 10.0% Sys: 5.0%") into its component values.
---@param text string|nil
---@return { percent: number|nil, avgPercent: number|nil, systemPercent: number|nil, raw: string }|nil
function Health.parseCpuValue(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local current = text:match("(%d+%.?%d*)%%")
    local avg = text:match("Avg:%s*(%d+%.?%d*)%%") or text:match("avg:%s*(%d+%.?%d*)%%")
    local system = text:match("Sys:%s*(%d+%.?%d*)%%") or text:match("sys:%s*(%d+%.?%d*)%%")

    return {
        percent = current and tonumber(current) or nil,
        avgPercent = avg and tonumber(avg) or nil,
        systemPercent = system and tonumber(system) or nil,
        raw = text,
    }
end

--- Parses an FPS sync stat string (e.g. "60 (59)") into sync/actual values.
---@param text string|nil
---@return { sync: integer|nil, actual: integer|nil, raw: string }|nil
function Health.parseFpsSyncValue(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local sync, actual = text:match("(%d+)%s*%((%d+)%)")
    if sync then
        return {
            sync = tonumber(sync),
            actual = tonumber(actual),
            raw = text,
        }
    end

    return { raw = text }
end

--- Normalizes a "Server info" performance row name (e.g. "Foo thread CPU") into a snake_case key.
---@param name string|nil
---@return string|nil
local function normalizeThreadKey(name)
    if type(name) ~= "string" then
        return nil
    end

    local key = name:gsub(" thread CPU", ""):lower():gsub("[^a-z0-9]+", "_"):gsub("_+$", "")
    if key == "" then
        return nil
    end
    return key
end

--- Collects per-thread CPU usage and server FPS sync info from the "Server info" performance category.
---@return { threads: table<string, table>, totalPercent: number, serverFps: table|nil }|nil
function Health.collectThreadCpu()
    local perf = Health.collectPerformance("Server info")
    if type(perf) ~= "table" or type(perf.rows) ~= "table" then
        return nil
    end

    local cpu = {
        threads = {},
        totalPercent = 0,
    }

    for i = 1, #perf.rows do
        local row = perf.rows[i]
        local infoName = row["Info.Name"]
        local infoValue = row["Info.Value"]
        local statusName = row["Status.Name"]
        local statusValue = row["Status.Value"]

        if type(infoName) == "string" and infoName:find("CPU", 1, true) then
            local key = normalizeThreadKey(infoName)
            if key then
                local parsed = Health.parseCpuValue(infoValue) or { raw = infoValue }
                cpu.threads[key] = parsed
                -- Only sum each thread's own CPU%; systemPercent is the
                -- whole-process figure and adding it per thread inflates the total.
                cpu.totalPercent = cpu.totalPercent + (parsed.percent or 0)
            end
        end

        if type(statusName) == "string" and statusName:find("FPS sync", 1, true) then
            cpu.serverFps = Health.parseFpsSyncValue(statusValue)
        end
    end

    cpu.totalPercent = math.floor(cpu.totalPercent * 100 + 0.5) / 100
    return cpu
end

--- Collects the top Lua resources by CPU usage from the "Lua timing" performance category.
---@param limit integer|nil Defaults to 5.
---@return { total5sPercent: number, top: table[], resourceCount: integer }|nil
function Health.collectLuaTimingCpu(limit)
    limit = tonumber(limit) or 5
    local perf = Health.collectPerformance("Lua timing")
    if type(perf) ~= "table" or type(perf.rows) ~= "table" then
        return nil
    end

    local total5s = 0
    local resources = {}

    for i = 1, #perf.rows do
        local row = perf.rows[i]
        local name = row.name or row["name"]
        local cpu5s = Health.parsePercentValue(row["5s.cpu"] or row["5s_cpu"])
        if type(name) == "string" and cpu5s then
            total5s = total5s + cpu5s
            resources[#resources + 1] = {
                name = name,
                cpu5s = cpu5s,
                cpu60s = Health.parsePercentValue(row["60s.cpu"] or row["60s_cpu"]),
            }
        end
    end

    table.sort(resources, function(a, b)
        return (a.cpu5s or 0) > (b.cpu5s or 0)
    end)

    local top = {}
    for i = 1, math.min(#resources, limit) do
        top[i] = resources[i]
    end

    return {
        total5sPercent = math.floor(total5s * 100 + 0.5) / 100,
        top = top,
        resourceCount = #resources,
    }
end

--- Collects CPU usage info: per-thread breakdown on server, Lua timing breakdown on both sides.
---@param options AgentHealthOptions|table|nil
---@param context { side: "server"|"client"|nil }|table|nil
---@return table|nil cpu
function Health.collectCpu(options, context)
    options = type(options) == "table" and options or {}
    context = type(context) == "table" and context or {}

    local cpu = {}

    if context.side == "server" then
        cpu.threads = Health.collectThreadCpu()
        if cpu.threads then
            cpu.totalPercent = cpu.threads.totalPercent
            cpu.serverFps = cpu.threads.serverFps
            cpu.threads = cpu.threads.threads
        end
    end

    if options.includeLuaCpu ~= false then
        cpu.lua = Health.collectLuaTimingCpu(options.luaCpuLimit)
        if context.side == "client" and cpu.lua and cpu.lua.total5sPercent then
            cpu.totalPercent = cpu.lua.total5sPercent
        end
    end

    if next(cpu) == nil then
        return nil
    end

    return cpu
end

--- Builds a full AgentHealthSnapshot for the given side/player context.
---@param options AgentHealthOptions|table|nil
---@param context { side: "server"|"client"|nil, player: string|nil, playerElement: element|nil }|table|nil
---@return AgentHealthSnapshot
function Health.collectSnapshot(options, context)
    options = type(options) == "table" and options or {}
    context = type(context) == "table" and context or {}

    local snapshot = {
        at = getTickCount(),
        side = context.side,
        player = context.player,
        fpsLimit = Health.safeCall(getFPSLimit),
        timerCount = type(getTimers) == "function" and #getTimers() or nil,
    }

    snapshot.memory = Health.normalizeMemory(Health.safeCall(_G["getProcessMemoryStats"]))

    if options.networkUsage ~= false then
        snapshot.networkUsage = Health.summarizeNetworkUsage(
            Health.safeCall(getNetworkUsageData),
            options.networkUsageLimit
        )
    end

    if context.side == "client" then
        snapshot.networkStats = Health.safeCall(getNetworkStats)
        snapshot.transferBoxActive = Health.safeCall(isTransferBoxActive)
        snapshot.dx = Health.safeCall(dxGetStatus)
    elseif context.side == "server" and context.playerElement and isElement(context.playerElement) then
        snapshot.networkStats = Health.safeCall(getNetworkStats, context.playerElement)
    end

    if options.includeCpu ~= false then
        snapshot.cpu = Health.collectCpu(options, context)
    end

    if options.listPerformanceCategories then
        snapshot.performanceCategories = Health.listPerformanceCategories()
    elseif type(options.performanceCategories) == "table" and #options.performanceCategories > 0 then
        snapshot.performance = {}
        for i = 1, #options.performanceCategories do
            local category = options.performanceCategories[i]
            snapshot.performance[category] = Health.collectPerformance(
                category,
                options.performanceOptions,
                options.performanceFilter
            )
        end
    elseif type(options.performanceCategory) == "string" and options.performanceCategory ~= "" then
        snapshot.performance = Health.collectPerformance(
            options.performanceCategory,
            options.performanceOptions,
            options.performanceFilter
        )
    end

    return snapshot
end
