const { success, failure, asyncRoute } = require("../../shared/lib/respond");
const { withPlayer } = require("../../shared/lib/player-session");
const { buildToolsManifest } = require("../../shared/lib/tools-manifest");
const { listFeatures, runFeature } = require("../../shared/features");
const { httpError } = require("../../shared/lib/http-error");

async function runFeatureRoute(ctx, req, res, featureId) {
  const body = req.body || {};
  const { player: explicitPlayer, serial: explicitSerial, ...options } = body;
  let resolvedRef;

  const result = await withPlayer(ctx, explicitPlayer, async (player, serial, ref) => {
    resolvedRef = ref;
    return runFeature(featureId, ctx.mta, {
      player,
      serial,
      ...options,
    });
  }, explicitSerial);

  success(res, result, {
    feature: featureId,
    player: resolvedRef?.player || null,
    serial: resolvedRef?.serial || null,
  });
}

function registerFeatureRoutes(app, ctx) {
  app.get("/mta/tools.json", (_req, res) => {
    success(res, buildToolsManifest());
  });

  app.get("/mta/features", (_req, res) => {
    success(res, listFeatures());
  });

  app.get("/mta/features/:id", (req, res) => {
    const feature = listFeatures().find((entry) => entry.id === req.params.id);
    if (!feature) {
      return failure(res, { message: `Unknown feature: ${req.params.id}`, code: "FEATURE_NOT_FOUND" }, 404);
    }
    success(res, feature);
  });

  app.post(
    "/mta/features/:id",
    asyncRoute(async (req, res) => {
      await runFeatureRoute(ctx, req, res, req.params.id);
    })
  );

  app.post(
    "/mta/do",
    asyncRoute(async (req, res) => {
      const featureId = req.body?.feature || req.body?.id;
      if (!featureId) {
        throw httpError("feature is required", { status: 400, code: "FEATURE_REQUIRED" });
      }
      await runFeatureRoute(ctx, req, res, featureId);
    })
  );
}

module.exports = { registerFeatureRoutes, runFeatureRoute };
