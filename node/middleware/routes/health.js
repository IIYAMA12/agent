const { success, failure, asyncRoute } = require("../../shared/lib/respond");
const { getOnlinePlayers, getDefaultPlayerHint } = require("../../shared/lib/player-session");
const { listFeatures } = require("../../shared/features");

function registerHealthRoutes(app, ctx) {
  app.get(
    "/health",
    asyncRoute(async (_req, res) => {
      const features = listFeatures().map((f) => f.id);
      let mtaStatus = { ok: false, error: "unreachable" };
      let playersOnline = [];

      try {
        mtaStatus = await ctx.mta.ping();
        playersOnline = await getOnlinePlayers(ctx.mta);
      } catch (error) {
        mtaStatus = { ok: false, error: error.message, body: error.body || null };
      }

      const defaultPlayer = await getDefaultPlayerHint(ctx);
      const ok = mtaStatus?.ok === true || mtaStatus?.resource === "agent";
      const base = {
        middleware: "running",
        middlewareVersion: ctx.version,
        auth: { user: ctx.creds.user, source: ctx.creds.source },
        features,
        playersOnline,
        defaultPlayer,
        mta: mtaStatus,
      };

      if (ok) {
        return success(res, base);
      }

      failure(res, { message: "MTA unreachable", code: "MTA_UNREACHABLE" }, 503, {
        ...base,
        auth: {
          user: ctx.creds.user || null,
          source: ctx.creds.source,
          configured: Boolean(ctx.creds.user && ctx.creds.password),
        },
      });
    })
  );
}

module.exports = { registerHealthRoutes };
