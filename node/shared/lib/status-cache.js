const { getOnlinePlayers } = require("./player-session");

const DEFAULT_POLL_MS = Number(process.env.STATUS_POLL_INTERVAL_MS || 8000);
const DEFAULT_PERF_CATEGORIES = (process.env.STATUS_PERF_CATEGORIES || "Lua timing,Lua memory")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const FALLBACK_PERF_CATEGORIES = [
  "Lua timing",
  "Lua memory",
  "Lib memory",
  "Packet usage",
  "RPC Packet usage",
  "Event Packet usage",
  "Player packet usage",
  "Sqlite timing",
  "Bandwidth reduction",
  "Bandwidth usage",
  "Server info",
  "Server timing",
  "Function stats",
  "Debug info",
  "Debug table",
];

let snapshot = null;
let pollTimer = null;
let refreshing = false;
let cachedPerformanceCategories = null;

function normalizePerfTable(table) {
  if (!table || typeof table !== "object") {
    return null;
  }
  const rows = Array.isArray(table.rows) ? table.rows : [];
  const columns = Array.isArray(table.columns) ? table.columns : [];
  return {
    columns,
    rows,
    rowCount: table.rowCount ?? rows.length,
  };
}

async function ensurePerformanceCategoryList(ctx) {
  if (cachedPerformanceCategories?.length) {
    return cachedPerformanceCategories;
  }
  try {
    const health = await ctx.mta.invoke("healthGet", [
      null,
      { side: "server", listPerformanceCategories: true },
    ]);
    const rows = health?.performanceCategories?.rows || [];
    const list = rows
      .map((row) => row.Categories || row.categories || row[0])
      .filter(Boolean);
    if (list.length) {
      cachedPerformanceCategories = list;
      return list;
    }
  } catch {
    // fall through
  }
  cachedPerformanceCategories = FALLBACK_PERF_CATEGORIES;
  return cachedPerformanceCategories;
}

async function fetchPerformanceCategory(ctx, category, options = "", filter = "") {
  const health = await ctx.mta.invoke("healthGet", [
    null,
    {
      side: "server",
      includeCpu: false,
      includeLuaCpu: false,
      networkUsage: false,
      performanceCategory: category,
      performanceOptions: options,
      performanceFilter: filter,
    },
  ]);
  return normalizePerfTable(health?.performance);
}

async function fetchPerformanceTables(ctx, categories = DEFAULT_PERF_CATEGORIES) {
  if (!categories.length) {
    return {};
  }
  const health = await ctx.mta.invoke("healthGet", [
    null,
    {
      side: "server",
      includeCpu: false,
      includeLuaCpu: false,
      networkUsage: false,
      performanceCategories: categories,
    },
  ]);
  const tables = {};
  for (const category of categories) {
    tables[category] = normalizePerfTable(health?.performance?.[category]);
  }
  return tables;
}

function buildRunningResourcePerf(runningResources, luaTop = []) {
  const perfByName = {};
  for (const entry of luaTop) {
    if (entry?.name) {
      perfByName[entry.name] = {
        cpu5s: entry.cpu5s ?? null,
        cpu60s: entry.cpu60s ?? null,
      };
    }
  }

  return runningResources
    .map((resource) => {
      const perf = perfByName[resource.name] || {};
      return {
        name: resource.name,
        state: resource.state || "running",
        cpu5s: perf.cpu5s ?? null,
        cpu60s: perf.cpu60s ?? null,
      };
    })
    .sort((a, b) => (b.cpu5s ?? 0) - (a.cpu5s ?? 0));
}

function aggregateResourceStates(resources = []) {
  const counts = {};
  for (const entry of resources) {
    const state = entry.state || "unknown";
    counts[state] = (counts[state] || 0) + 1;
  }
  return {
    total: resources.length,
    running: counts.running || 0,
    loaded: counts.loaded || 0,
    starting: counts.starting || 0,
    stopping: counts.stopping || 0,
    stopped: counts.stopped || 0,
    failed: counts.failed || 0,
    byState: counts,
  };
}

function summarizeHealth(health) {
  if (!health || typeof health !== "object") {
    return null;
  }

  const server = health.server || health;
  if (!server || typeof server !== "object") {
    return null;
  }

  const memory = server.memory
    ? {
        residentMiB: server.memory.residentMiB,
        virtualMiB: server.memory.virtualMiB,
        privateMiB: server.memory.privateMiB,
      }
    : null;

  let cpu = null;
  if (server.cpu) {
    let threads;
    if (Array.isArray(server.cpu.threads)) {
      threads = server.cpu.threads.map((t) => ({
        name: t.name,
        percent: t.percent,
        systemPercent: t.systemPercent,
      }));
    } else if (server.cpu.threads && typeof server.cpu.threads === "object") {
      threads = Object.entries(server.cpu.threads).map(([name, t]) => ({
        name,
        percent: t?.percent,
        systemPercent: t?.systemPercent,
      }));
    }

    cpu = {
      totalPercent: server.cpu.totalPercent,
      serverFps: server.cpu.serverFps,
      threads,
      lua: server.cpu.lua
        ? {
            total5sPercent: server.cpu.lua.total5sPercent,
            resourceCount: server.cpu.lua.resourceCount,
            top: (server.cpu.lua.top || []).map((r) => ({
              name: r.name,
              cpu5s: r.cpu5s,
              cpu60s: r.cpu60s,
            })),
          }
        : null,
    };
  }

  let networkUsage = null;
  if (server.networkUsage && typeof server.networkUsage === "object") {
    networkUsage = {};
    for (const direction of ["in", "out"]) {
      const dir = server.networkUsage[direction];
      if (dir && Array.isArray(dir.top)) {
        networkUsage[direction] = dir.top.slice(0, 5).map((row) => ({
          id: row.id,
          count: row.count,
          bits: row.bits,
        }));
      }
    }
  }

  return {
    fpsLimit: server.fpsLimit,
    timerCount: server.timerCount,
    memory,
    cpu,
    networkUsage,
  };
}

async function collectStatus(ctx) {
  const next = {
    updatedAt: new Date().toISOString(),
    pollIntervalMs: DEFAULT_POLL_MS,
    middleware: {
      ok: true,
      version: ctx.version,
    },
    mta: { ok: false },
    players: { count: 0, online: [] },
    resources: { total: 0, running: 0, loaded: 0, starting: 0, stopping: 0, stopped: 0, failed: 0, byState: {} },
    runningResources: [],
    performance: { categories: [], polled: [], tables: {} },
    health: null,
    errors: [],
  };

  try {
    next.mta = await ctx.mta.ping();
  } catch (error) {
    next.errors.push({ scope: "mta.ping", message: error.message });
  }

  if (next.mta?.ok !== true && next.mta?.resource !== "agent") {
    return next;
  }

  try {
    const online = await getOnlinePlayers(ctx.mta);
    next.players = {
      count: online.length,
      online: online.map((p) => ({
        name: p.name || p,
        serial: p.serial || null,
        ping: p.ping ?? null,
      })),
    };
  } catch (error) {
    next.errors.push({ scope: "players", message: error.message });
  }

  try {
    const [search, runningSearch] = await Promise.all([
      ctx.mta.resourceSearch({ query: "", limit: 500 }),
      ctx.mta.resourceSearch({ query: "", state: "running", limit: 500 }),
    ]);
    let list = search?.resources || [];
    // resourceSearch caps results at `limit`; if there are more matches than
    // returned rows, re-fetch the full set so state counts aren't undercounted.
    const matchedTotal = search?.matchedTotal ?? list.length;
    if (matchedTotal > list.length) {
      const full = await ctx.mta.resourceSearch({ query: "", limit: matchedTotal });
      if (Array.isArray(full?.resources) && full.resources.length >= list.length) {
        list = full.resources;
      }
    }
    const runningList = runningSearch?.resources || [];
    const aggregated = aggregateResourceStates(list);
    next.resources = {
      ...aggregated,
      catalogTotal: search?.total ?? list.length,
      matchedTotal: search?.matchedTotal ?? list.length,
    };
    next.runningResources = runningList.map((r) => ({
      name: r.name,
      state: r.state,
      cpu5s: null,
      cpu60s: null,
    }));
  } catch (error) {
    next.errors.push({ scope: "resources", message: error.message });
  }

  try {
    const [health, perfTables, perfCategories] = await Promise.all([
      ctx.mta.invoke("healthGet", [
        null,
        {
          side: "server",
          includeCpu: true,
          includeLuaCpu: true,
          luaCpuLimit: 500,
          networkUsage: true,
          networkUsageLimit: 5,
        },
      ]),
      fetchPerformanceTables(ctx, DEFAULT_PERF_CATEGORIES),
      ensurePerformanceCategoryList(ctx),
    ]);
    next.health = summarizeHealth(health);
    next.performance = {
      categories: perfCategories,
      polled: DEFAULT_PERF_CATEGORIES,
      tables: perfTables,
    };
    if (next.runningResources.length && next.health?.cpu?.lua?.top) {
      next.runningResources = buildRunningResourcePerf(
        next.runningResources,
        next.health.cpu.lua.top
      );
    }
  } catch (error) {
    next.errors.push({ scope: "health", message: error.message });
  }

  return next;
}

async function refreshStatus(ctx) {
  if (refreshing) {
    return snapshot;
  }
  refreshing = true;
  try {
    snapshot = await collectStatus(ctx);
    return snapshot;
  } finally {
    refreshing = false;
  }
}

function getStatusSnapshot() {
  return snapshot;
}

function startStatusPolling(ctx, intervalMs = DEFAULT_POLL_MS) {
  if (pollTimer) {
    return pollTimer;
  }

  const tick = () => {
    refreshStatus(ctx).catch((error) => {
      snapshot = {
        ...(snapshot || {}),
        updatedAt: new Date().toISOString(),
        errors: [{ scope: "poll", message: error.message }],
      };
    });
  };

  tick();
  pollTimer = setInterval(tick, intervalMs);
  if (typeof pollTimer.unref === "function") {
    pollTimer.unref();
  }
  return pollTimer;
}

function stopStatusPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

module.exports = {
  DEFAULT_POLL_MS,
  DEFAULT_PERF_CATEGORIES,
  aggregateResourceStates,
  buildRunningResourcePerf,
  summarizeHealth,
  normalizePerfTable,
  ensurePerformanceCategoryList,
  fetchPerformanceCategory,
  fetchPerformanceTables,
  collectStatus,
  refreshStatus,
  getStatusSnapshot,
  startStatusPolling,
  stopStatusPolling,
};
