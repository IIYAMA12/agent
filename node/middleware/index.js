const { createMiddlewareContext } = require("../shared/config");
const { createApp } = require("./app");
const { startStatusPolling } = require("../shared/lib/status-cache");
const { startMcpWatchdog } = require("../shared/lib/middleware-process");

const ctx = createMiddlewareContext();
const app = createApp(ctx);

app.listen(ctx.port, ctx.host, () => {
  startStatusPolling(ctx);
  startMcpWatchdog();
  console.log(`[agent-middleware] v${ctx.version} listening on http://${ctx.host}:${ctx.port}`);
  console.log(`[agent-middleware] dashboard: http://127.0.0.1:${ctx.port}/dashboard`);
});
