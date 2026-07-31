const { assertRestartAllowed, isRestartAllowed } = require("../lib/restart-policy");
const {
  getMiddlewareStatus,
  restartMiddleware,
  restartAgentResource,
  restartAgentAndMiddleware,
} = require("../lib/middleware-process");

function registerSystemFeatures(registry) {
  registry.register("agent.restart", {
    description: "Restart the agent MTA resource (requires ALLOW_RESTART=1 in node/.env)",
    params: {
      resource: { optional: true },
      wait: { optional: true },
    },
    run: (mta, params = {}) =>
      restartAgentResource(mta, {
        resource: params.resource,
        wait: params.wait !== false,
      }),
  });

  registry.register("middleware.restart", {
    description: "Restart the Node middleware HTTP server (requires ALLOW_RESTART=1)",
    params: {
      wait: { optional: true },
    },
    run: async (_mta, params = {}) =>
      restartMiddleware({
        wait: params.wait !== false,
      }),
  });

  registry.register("system.restart", {
    description: "Restart agent MTA resource and Node middleware (requires ALLOW_RESTART=1)",
    params: {
      resource: { optional: true },
      wait: { optional: true },
    },
    run: (mta, params = {}) =>
      restartAgentAndMiddleware(mta, {
        resource: params.resource,
        wait: params.wait !== false,
      }),
  });

  registry.register("system.status", {
    description: "Middleware listen status and whether auto-restart is enabled",
    params: {},
    run: async () => ({
      restartAllowed: isRestartAllowed(),
      middleware: await getMiddlewareStatus(),
    }),
  });
}

module.exports = { registerSystemFeatures, assertRestartAllowed };
