const { spawn } = require("child_process");
const path = require("path");

require("../shared/load-env").loadEnv();

// Cursor MCP may spawn this file with a bundled Node whose ABI does not match
// better-sqlite3 (built for PATH node). Re-exec under PATH/NODE_BINARY then.
(function reexecIfSqliteAbiMismatch() {
  if (process.env.AGENT_MIDDLEWARE_REEXEC === "1") {
    return;
  }
  try {
    const Database = require("better-sqlite3");
    const probe = new Database(":memory:");
    probe.close();
  } catch (error) {
    if (!error || error.code !== "ERR_DLOPEN_FAILED") {
      throw error;
    }
    const nodeBinary = process.env.NODE_BINARY || "node";
    const child = spawn(nodeBinary, [__filename, ...process.argv.slice(2)], {
      cwd: path.join(__dirname, ".."),
      detached: true,
      stdio: "ignore",
      env: {
        ...process.env,
        AGENT_MIDDLEWARE_REEXEC: "1",
      },
    });
    child.unref();
    process.exit(0);
  }
})();

const { createMiddlewareContext } = require("../shared/config");
const { createApp } = require("./app");
const { startStatusPolling } = require("../shared/lib/status-cache");
const { startMcpWatchdog } = require("../shared/lib/middleware-process");
const { startLocalWatcher } = require("./local-watch");

const ctx = createMiddlewareContext();
const app = createApp(ctx);

app.listen(ctx.port, ctx.host, () => {
  startStatusPolling(ctx);
  startMcpWatchdog();
  startLocalWatcher();
  console.log(`[agent-middleware] v${ctx.version} listening on http://${ctx.host}:${ctx.port}`);
  console.log(`[agent-middleware] dashboard: http://127.0.0.1:${ctx.port}/dashboard`);
});
