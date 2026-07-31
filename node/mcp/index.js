require("../shared/load-env").loadEnv();

const { McpServer } = require("@modelcontextprotocol/sdk/server/mcp.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");
const { VERSION } = require("../shared/config");
const {
  ensureMiddlewareRunning,
  registerMcpMiddlewareUse,
  releaseMcpMiddlewareUse,
} = require("../shared/lib/middleware-process");
const { registerMcpTools } = require("./register-tools");
const { registerMcpResources } = require("./register-resources");

const server = new McpServer({ name: "mta-agent", version: VERSION });
registerMcpTools(server);
registerMcpResources(server);

let shutdownPromise = null;
let middlewareRetryTimer = null;
let isShuttingDown = false;

function logMiddlewareStartFailure(error) {
  const details = [
    "[mta-agent-mcp] middleware auto-start failed:",
    error.message,
    error.code ? `(code: ${error.code})` : null,
    "— start manually: cd node && npm start",
  ]
    .filter(Boolean)
    .join(" ");
  console.error(details);
  if (error.stack) {
    console.error(error.stack);
  }
}

function registerMcpEarly() {
  const refState = registerMcpMiddlewareUse({});
  console.error(
    `[mta-agent-mcp] MCP process registered (pid ${process.pid}, refs=${refState.refs})`
  );
}

async function ensureMiddlewareForMcp(options = {}) {
  const ensureResult = await ensureMiddlewareRunning(options);
  const refState = registerMcpMiddlewareUse(ensureResult);

  if (ensureResult.alreadyRunning) {
    console.error(
      `[mta-agent-mcp] middleware already running at http://${ensureResult.host}:${ensureResult.port}`
    );
  } else if (ensureResult.started) {
    console.error(
      `[mta-agent-mcp] middleware started at http://${ensureResult.host}:${ensureResult.port} (pid ${ensureResult.pid}, ready in ${ensureResult.readyInMs}ms)`
    );
  }

  console.error(
    `[mta-agent-mcp] middleware ref registered (refs=${refState.refs}, mcpPid=${process.pid}, middlewarePid=${refState.pid ?? "unknown"})`
  );
  return ensureResult;
}

function scheduleMiddlewareEnsureRetry() {
  if (middlewareRetryTimer || isShuttingDown) {
    return;
  }

  console.error("[mta-agent-mcp] scheduling background middleware start retries");
  let attempt = 0;
  middlewareRetryTimer = setInterval(async () => {
    if (isShuttingDown) {
      clearInterval(middlewareRetryTimer);
      middlewareRetryTimer = null;
      return;
    }

    attempt += 1;
    try {
      await ensureMiddlewareForMcp({ retries: 3, timeoutMs: 3000 });
      clearInterval(middlewareRetryTimer);
      middlewareRetryTimer = null;
      console.error(
        `[mta-agent-mcp] middleware ready on background retry (attempt ${attempt})`
      );
    } catch (error) {
      if (attempt >= 15) {
        clearInterval(middlewareRetryTimer);
        middlewareRetryTimer = null;
        logMiddlewareStartFailure(error);
      }
    }
  }, 2000);
}

function shutdown() {
  isShuttingDown = true;
  if (middlewareRetryTimer) {
    clearInterval(middlewareRetryTimer);
    middlewareRetryTimer = null;
  }

  if (!shutdownPromise) {
    shutdownPromise = (async () => {
      try {
        const result = await releaseMcpMiddlewareUse();
        if (result.stopped) {
          console.error("[mta-agent-mcp] middleware stopped", result.stoppedPids || "");
        } else if (result.refs > 0) {
          console.error(`[mta-agent-mcp] middleware still running (${result.refs} MCP ref(s) remain)`);
        } else if (result.reason) {
          console.error(`[mta-agent-mcp] middleware left running (${result.reason})`);
        }
      } catch (error) {
        console.error(
          "[mta-agent-mcp] middleware stop failed:",
          error.message,
          error.code ? `(code: ${error.code})` : ""
        );
      }
    })();
  }
  return shutdownPromise;
}

function shutdownAndExit(code = 0) {
  shutdown().finally(() => process.exit(code));
}

async function main() {
  registerMcpEarly();

  void ensureMiddlewareForMcp({ startupDelayMs: 400, retries: 5, timeoutMs: 3000 }).catch(
    (error) => {
      logMiddlewareStartFailure(error);
      scheduleMiddlewareEnsureRetry();
    }
  );

  const transport = new StdioServerTransport();
  transport.onclose = () => shutdownAndExit(0);
  process.once("SIGINT", () => shutdownAndExit(0));
  process.once("SIGTERM", () => shutdownAndExit(0));
  process.stdin.once("end", () => shutdownAndExit(0));

  await server.connect(transport);
}

main().catch((error) => {
  console.error("[mta-agent-mcp] fatal:", error);
  shutdownAndExit(1);
});
