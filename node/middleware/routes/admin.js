const { asyncRoute, success, failure } = require("../../shared/lib/respond");
const { isRestartAllowed } = require("../../shared/lib/restart-policy");
const {
  getMiddlewareStatus,
  restartMiddleware,
  restartAgentResource,
  restartAgentAndMiddleware,
} = require("../../shared/lib/middleware-process");
const { spawn } = require("child_process");
const path = require("path");

function ensureRestartAllowed(res) {
  if (!isRestartAllowed()) {
    failure(
      res,
      {
        message: "Restart disabled — set ALLOW_RESTART=1 in node/.env",
        code: "RESTART_DISABLED",
      },
      403
    );
    return false;
  }
  return true;
}

function registerAdminRoutes(app, ctx) {
  app.get(
    "/admin/status",
    asyncRoute(async (_req, res) => {
      success(res, {
        restartAllowed: isRestartAllowed(),
        middleware: await getMiddlewareStatus(),
      });
    })
  );

  app.post(
    "/admin/restart/middleware",
    asyncRoute(async (_req, res) => {
      if (!ensureRestartAllowed(res)) return;

      const scriptPath = path.join(__dirname, "../../scripts/restart-middleware.js");
      spawn(process.execPath, [scriptPath, "500"], {
        cwd: path.join(__dirname, "../.."),
        detached: true,
        stdio: "ignore",
        env: process.env,
      }).unref();

      success(res, {
        ok: true,
        action: "restart_scheduled",
        message: "Middleware restart scheduled; this process will exit shortly",
      });

      setTimeout(() => process.exit(0), 250);
    })
  );

  app.post(
    "/admin/restart/agent",
    asyncRoute(async (_req, res) => {
      if (!ensureRestartAllowed(res)) return;

      const result = await restartAgentResource(ctx.mta);
      success(res, result);
    })
  );

  app.post(
    "/admin/restart/all",
    asyncRoute(async (_req, res) => {
      if (!ensureRestartAllowed(res)) return;

      const agent = await restartAgentResource(ctx.mta);
      success(res, {
        ok: true,
        agent,
        middleware: {
          action: "restart_scheduled",
          message: "Call POST /admin/restart/middleware or use MCP after agent restart if needed",
        },
      });
    })
  );
}

module.exports = { registerAdminRoutes };
