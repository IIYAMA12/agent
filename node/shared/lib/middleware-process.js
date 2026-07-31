const { execSync, spawn } = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");
const { assertRestartAllowed } = require("./restart-policy");

const NODE_ROOT = path.join(__dirname, "../..");
const MCP_MIDDLEWARE_STATE_FILE = path.join(NODE_ROOT, "data/mcp-middleware.json");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getMiddlewareHost() {
  return process.env.MIDDLEWARE_HOST || "127.0.0.1";
}

function getMiddlewarePort() {
  return Number(process.env.MIDDLEWARE_PORT || 3847);
}

function isPortOpen(host, port) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(500);
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("timeout", () => {
      socket.destroy();
      resolve(false);
    });
    socket.once("error", () => resolve(false));
    socket.connect(port, host);
  });
}

function findListeningPids(port) {
  const pids = new Set();

  if (process.platform === "win32") {
    try {
      const output = execSync(`netstat -ano | findstr :${port}`, { encoding: "utf8" });
      for (const line of output.split(/\r?\n/)) {
        if (!line.includes("LISTENING")) continue;
        const parts = line.trim().split(/\s+/);
        const pid = Number(parts[parts.length - 1]);
        if (Number.isInteger(pid) && pid > 0) {
          pids.add(pid);
        }
      }
    } catch {
      return [];
    }
  } else {
    try {
      const output = execSync(`lsof -ti tcp:${port}`, { encoding: "utf8" });
      for (const line of output.split(/\r?\n/)) {
        const pid = Number(line.trim());
        if (Number.isInteger(pid) && pid > 0) {
          pids.add(pid);
        }
      }
    } catch {
      return [];
    }
  }

  return [...pids];
}

function killPid(pid) {
  if (process.platform === "win32") {
    execSync(`taskkill /PID ${pid} /F`, { stdio: "ignore" });
    return;
  }

  process.kill(pid, "SIGTERM");
}

function isProcessAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) {
    return false;
  }

  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

async function stopMiddleware(options = {}) {
  const host = options.host || getMiddlewareHost();
  const port = options.port || getMiddlewarePort();
  let pids;
  let stopMode = "port";

  if (Number.isInteger(options.pid) && options.pid > 0) {
    const listening = findListeningPids(port);
    if (listening.includes(options.pid)) {
      pids = [options.pid];
      stopMode = "pid";
    } else if (!(await isPortOpen(host, port))) {
      return {
        ok: true,
        stoppedPids: [],
        host,
        port,
        stopMode,
        reason: "already_stopped",
      };
    } else {
      // Port is open under a different pid (e.g. a newer MCP instance restarted middleware).
      return {
        ok: true,
        stoppedPids: [],
        host,
        port,
        stopMode,
        reason: "pid_not_listening",
        listeningPids: listening,
      };
    }
  } else {
    pids = findListeningPids(port).filter((pid) => pid !== process.pid);
  }

  for (const pid of pids) {
    try {
      killPid(pid);
    } catch {
      // Process may already be gone.
    }
  }

  for (let attempt = 0; attempt < 30; attempt += 1) {
    if (!(await isPortOpen(host, port))) {
      return { ok: true, stoppedPids: pids, host, port, stopMode };
    }
    await sleep(100);
  }

  const error = new Error(`Middleware still listening on ${host}:${port}`);
  error.code = "MIDDLEWARE_STOP_FAILED";
  throw error;
}

function startMiddleware(options = {}) {
  const host = options.host || getMiddlewareHost();
  const port = options.port || getMiddlewarePort();
  const entry = path.join(NODE_ROOT, "middleware/index.js");
  const child = spawn(process.execPath, [entry], {
    cwd: NODE_ROOT,
    detached: true,
    stdio: "ignore",
    env: {
      ...process.env,
      MIDDLEWARE_HOST: host,
      MIDDLEWARE_PORT: String(port),
    },
  });
  child.unref();

  return {
    ok: true,
    pid: child.pid,
    host,
    port,
    entry,
  };
}

async function waitForMiddleware(options = {}) {
  const host = options.host || getMiddlewareHost();
  const port = options.port || getMiddlewarePort();
  const timeoutMs = options.timeoutMs || 10000;
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    if (await isPortOpen(host, port)) {
      return { ok: true, host, port, readyInMs: Date.now() - startedAt };
    }
    await sleep(200);
  }

  const error = new Error(`Middleware did not become ready on ${host}:${port}`);
  error.code = "MIDDLEWARE_START_TIMEOUT";
  const listeningPids = findListeningPids(port);
  console.error(
    `[mta-agent-mcp] middleware start timeout after ${timeoutMs}ms on ${host}:${port}` +
      (listeningPids.length ? ` (pids on port: ${listeningPids.join(", ")})` : " (port not listening)")
  );
  throw error;
}

async function getMiddlewareStatus() {
  const host = getMiddlewareHost();
  const port = getMiddlewarePort();
  const listening = await isPortOpen(host, port);
  return {
    host,
    port,
    listening,
    pids: listening ? findListeningPids(port) : [],
  };
}

let ensureMiddlewarePromise = null;

function readMcpMiddlewareState() {
  try {
    const raw = fs.readFileSync(MCP_MIDDLEWARE_STATE_FILE, "utf8");
    const parsed = JSON.parse(raw);
    const mcpPids = Array.isArray(parsed.mcpPids)
      ? parsed.mcpPids.filter((pid) => Number.isInteger(pid) && pid > 0)
      : [];
    const refs =
      typeof parsed.refs === "number" && parsed.refs >= 0
        ? parsed.refs
        : mcpPids.length;
    if (refs < 0) {
      return null;
    }
    return {
      refs,
      startedByMcp: Boolean(parsed.startedByMcp),
      pid: Number.isInteger(parsed.pid) ? parsed.pid : null,
      mcpPids,
    };
  } catch {
    return null;
  }
}

function writeMcpMiddlewareState(state) {
  fs.mkdirSync(path.dirname(MCP_MIDDLEWARE_STATE_FILE), { recursive: true });
  fs.writeFileSync(MCP_MIDDLEWARE_STATE_FILE, JSON.stringify(state), "utf8");
}

function clearMcpMiddlewareState() {
  try {
    fs.unlinkSync(MCP_MIDDLEWARE_STATE_FILE);
  } catch {
    // State file may already be gone.
  }
}

function registerMcpMiddlewareUse(ensureResult = {}) {
  const mcpPid = process.pid;
  const state = readMcpMiddlewareState() || {
    refs: 0,
    startedByMcp: false,
    pid: null,
    mcpPids: [],
  };

  state.mcpPids = state.mcpPids.filter(isProcessAlive);
  if (!state.mcpPids.includes(mcpPid)) {
    state.mcpPids.push(mcpPid);
  }
  state.refs = state.mcpPids.length;

  if (ensureResult.started) {
    state.startedByMcp = true;
    state.pid = ensureResult.pid ?? state.pid;
  } else if (ensureResult.alreadyRunning && !state.pid) {
    const [middlewarePid] = findListeningPids(getMiddlewarePort());
    state.pid = middlewarePid ?? null;
  }

  writeMcpMiddlewareState(state);
  return { ...state };
}

async function stopMiddlewareWhenUnreferenced(state, options = {}) {
  console.error(
    `[mta-agent-mcp] middleware release: last MCP disconnected, stopping pid ${state.pid ?? "unknown"}`
  );
  const result = await stopMiddleware({ ...options, pid: state.pid ?? undefined });
  if (result.reason === "pid_not_listening") {
    console.error(
      "[mta-agent-mcp] middleware release: skipped stop — port owned by another pid",
      result.listeningPids
    );
  }
  return { ok: true, stopped: result.stoppedPids?.length > 0, ...result };
}

async function releaseMcpMiddlewareUse(options = {}) {
  const mcpPid = options.mcpPid ?? process.pid;
  const state = readMcpMiddlewareState();
  if (!state || state.mcpPids.length === 0) {
    return { ok: true, stopped: false, reason: "no_state" };
  }

  state.mcpPids = state.mcpPids.filter((pid) => pid !== mcpPid);
  state.refs = state.mcpPids.length;

  if (state.mcpPids.length > 0) {
    writeMcpMiddlewareState(state);
    return { ok: true, stopped: false, refs: state.refs };
  }

  clearMcpMiddlewareState();
  return stopMiddlewareWhenUnreferenced(state, options);
}

function pruneDeadMcpPids(state) {
  const alive = state.mcpPids.filter(isProcessAlive);
  return {
    ...state,
    mcpPids: alive,
    refs: alive.length,
  };
}

function startMcpWatchdog(options = {}) {
  const intervalMs = options.intervalMs || 3000;

  return setInterval(() => {
    const state = readMcpMiddlewareState();
    if (!state || state.mcpPids.length === 0) {
      return;
    }

    const pruned = pruneDeadMcpPids(state);
    if (pruned.mcpPids.length === state.mcpPids.length) {
      return;
    }

    if (pruned.mcpPids.length > 0) {
      console.error(
        `[agent-middleware] pruned dead MCP pids (refs=${pruned.refs}, alive=${pruned.mcpPids.join(", ")})`
      );
      writeMcpMiddlewareState(pruned);
      return;
    }

    console.error("[agent-middleware] no MCP instances remain — shutting down");
    clearMcpMiddlewareState();
    process.exit(0);
  }, intervalMs);
}

async function ensureMiddlewareRunningOnce(options = {}) {
  const host = options.host || getMiddlewareHost();
  const port = options.port || getMiddlewarePort();

  if (await isPortOpen(host, port)) {
    return { ok: true, alreadyRunning: true, host, port };
  }

  await sleep(options.settleMs ?? 100);
  if (await isPortOpen(host, port)) {
    return { ok: true, alreadyRunning: true, host, port };
  }

  console.error(`[mta-agent-mcp] middleware not running — starting http://${host}:${port}`);
  const started = startMiddleware({ host, port });
  try {
    const ready = await waitForMiddleware({
      host,
      port,
      timeoutMs: options.timeoutMs || 5000,
    });
    console.error(
      `[mta-agent-mcp] middleware ready in ${ready.readyInMs}ms (pid ${started.pid})`
    );
    return { ok: true, started: true, ...started, readyInMs: ready.readyInMs };
  } catch (error) {
    const listeningPids = findListeningPids(port);
    if (listeningPids.includes(started.pid)) {
      return { ok: true, started: true, ...started, readyInMs: 0 };
    }
    if (Number.isInteger(started.pid) && isProcessAlive(started.pid)) {
      try {
        const grace = await waitForMiddleware({ host, port, timeoutMs: 5000 });
        return { ok: true, started: true, ...started, readyInMs: grace.readyInMs };
      } catch {
        // Child stayed alive but never bound the port.
      }
    }
    if (Number.isInteger(started.pid)) {
      try {
        killPid(started.pid);
      } catch {
        // Failed spawn may already be gone.
      }
    }
    throw error;
  }
}

async function ensureMiddlewareRunning(options = {}) {
  if (ensureMiddlewarePromise) {
    return ensureMiddlewarePromise;
  }

  const retries = options.retries ?? 3;
  const retryDelayMs = options.retryDelayMs ?? 600;

  ensureMiddlewarePromise = (async () => {
    if (options.startupDelayMs) {
      await sleep(options.startupDelayMs);
    }

    let lastError;
    for (let attempt = 1; attempt <= retries; attempt += 1) {
      try {
        return await ensureMiddlewareRunningOnce({
          ...options,
          settleMs: attempt === 1 ? options.settleMs : 200,
        });
      } catch (error) {
        lastError = error;
        if (attempt < retries) {
          console.error(
            `[mta-agent-mcp] middleware start attempt ${attempt}/${retries} failed: ${error.message}` +
              (error.code ? ` (${error.code})` : "")
          );
          await sleep(retryDelayMs);
        }
      }
    }
    throw lastError;
  })().finally(() => {
    ensureMiddlewarePromise = null;
  });

  return ensureMiddlewarePromise;
}

function scheduleSelfRestart(options = {}) {
  const scriptPath = path.join(NODE_ROOT, "scripts/restart-middleware.js");
  const delayMs = options.delayMs || 500;
  spawn(process.execPath, [scriptPath, String(delayMs)], {
    cwd: NODE_ROOT,
    detached: true,
    stdio: "ignore",
    env: process.env,
  }).unref();

  // Release the port so the freshly spawned process can bind it.
  setTimeout(() => process.exit(0), 250);

  return {
    ok: true,
    action: "restart_scheduled",
    selfExit: true,
    delayMs,
    message: "Middleware restart scheduled; this process will exit shortly",
  };
}

async function restartMiddleware(options = {}) {
  if (options.requireAllowed !== false) {
    assertRestartAllowed();
  }

  const host = options.host || getMiddlewareHost();
  const port = options.port || getMiddlewarePort();

  // If we are the process currently listening, we cannot stop+rebind in place
  // (stopMiddleware skips our own pid, so a second process would fail to bind).
  // Hand off to a detached restart script and exit, mirroring the admin route.
  if (options.allowSelfExit !== false && findListeningPids(port).includes(process.pid)) {
    return scheduleSelfRestart(options);
  }

  if (options.delayMs) {
    await sleep(options.delayMs);
  }

  await stopMiddleware({ ...options, host, port });
  const started = startMiddleware({ ...options, host, port });
  if (options.wait !== false) {
    await waitForMiddleware({ ...options, host, port });
  }

  return {
    ok: true,
    action: "restart",
    ...started,
  };
}

async function restartAgentResource(mta, options = {}) {
  assertRestartAllowed();

  const resource = options.resource || process.env.MTA_RESOURCE || "agent";
  const result = await mta.invoke("resourceRestart", [resource]);

  if (options.wait === false) {
    return { ok: true, resource, result };
  }

  const timeoutMs = options.timeoutMs || 15000;
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    try {
      const ping = await mta.ping();
      if (ping?.ok) {
        return {
          ok: true,
          resource,
          result,
          ping,
          readyInMs: Date.now() - startedAt,
        };
      }
    } catch {
      // MTA may briefly refuse connections during restart.
    }
    await sleep(500);
  }

  return {
    ok: true,
    resource,
    result,
    warning: "Restart command sent but MTA ping was not confirmed within timeout",
  };
}

async function restartAgentAndMiddleware(mta, options = {}) {
  assertRestartAllowed();

  const agent = await restartAgentResource(mta, options);
  const middleware = await restartMiddleware(options);
  return {
    ok: true,
    agent,
    middleware,
  };
}

module.exports = {
  NODE_ROOT,
  getMiddlewareHost,
  getMiddlewarePort,
  isPortOpen,
  findListeningPids,
  getMiddlewareStatus,
  ensureMiddlewareRunning,
  registerMcpMiddlewareUse,
  releaseMcpMiddlewareUse,
  startMcpWatchdog,
  stopMiddleware,
  startMiddleware,
  waitForMiddleware,
  restartMiddleware,
  restartAgentResource,
  restartAgentAndMiddleware,
};
