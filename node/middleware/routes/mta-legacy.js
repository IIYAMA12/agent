const { success, asyncRoute } = require("../../shared/lib/respond");
const { withPlayerFromBody } = require("../../shared/lib/player-session");
const { httpError } = require("../../shared/lib/http-error");
const { createMtaClient } = require("../../shared/config");

function registerMtaLegacyRoutes(app, ctx) {
  app.post(
    "/mta/call",
    asyncRoute(async (req, res) => {
      const { resource, function: functionName, args } = req.body || {};
      if (!resource || !functionName) {
        throw httpError("resource and function are required", { status: 400 });
      }

      const client = createMtaClient({ resource });
      const result = await client.invoke(functionName, Array.isArray(args) ? args : []);
      success(res, result);
    })
  );

  app.post(
    "/mta/eval",
    asyncRoute(async (req, res) => {
      if (process.env.ALLOW_HTTP_EVAL !== "1") {
        throw httpError(
          "Server eval disabled — set ALLOW_HTTP_EVAL=1 in node/.env (does not affect MTA /agent/call/eval)",
          {
            status: 403,
            code: "EVAL_DISABLED",
            hint: "ALLOW_HTTP_EVAL only gates middleware HTTP/MCP. Direct MTA HTTP eval still works, or use /mta/features/:id.",
          }
        );
      }
      const { code } = req.body || {};
      if (!code || typeof code !== "string") {
        throw httpError("code is required", { status: 400 });
      }
      success(res, await ctx.mta.eval(code));
    })
  );

  app.post(
    "/mta/eval/client",
    asyncRoute(async (req, res) => {
      const body = req.body || {};
      if (!body.code || typeof body.code !== "string") {
        throw httpError("code is required", { status: 400 });
      }
      await withPlayerFromBody(ctx, body, async (player) => {
        const evalOptions = body.serial ? { serial: body.serial } : {};
        const result =
          body.wait === true || body.sync === true
            ? await ctx.mta.evalClientComplete(body.code, player, evalOptions)
            : await ctx.mta.evalClient(body.code, player, evalOptions);
        success(res, result, { player, serial: body.serial || null });
      });
    })
  );

  app.get(
    "/mta/eval/client/:id",
    asyncRoute(async (req, res) => {
      success(res, await ctx.mta.evalClientResult(req.params.id));
    })
  );

  app.get(
    "/mta/nearby",
    asyncRoute(async (req, res) => {
      await withPlayerFromBody(ctx, req.query, async (player) => {
        success(
          res,
          await ctx.mta.findNearby({
            ...req.query,
            player,
          })
        );
      });
    })
  );

  app.post(
    "/mta/nearby",
    asyncRoute(async (req, res) => {
      const body = req.body || {};
      await withPlayerFromBody(ctx, body, async (player) => {
        success(res, await ctx.mta.findNearby({ ...body, player }));
      });
    })
  );

  app.post(
    "/mta/visible",
    asyncRoute(async (req, res) => {
      const body = req.body || {};
      await withPlayerFromBody(ctx, body, async (player) => {
        success(res, await ctx.mta.findVisible({ ...body, player }));
      });
    })
  );

  app.get(
    "/mta/visible/:id",
    asyncRoute(async (req, res) => {
      success(res, await ctx.mta.findVisibleResult(req.params.id));
    })
  );

  app.post(
    "/mta/look",
    asyncRoute(async (req, res) => {
      const body = req.body || {};
      await withPlayerFromBody(ctx, body, async (player) => {
        const payload = { ...body, player };
        const result =
          body.wait === true || body.sync === true
            ? await ctx.mta.lookTarget(payload)
            : await ctx.mta.findLookTarget(payload);
        success(res, result);
      });
    })
  );

  app.get(
    "/mta/look/:id",
    asyncRoute(async (req, res) => {
      success(res, await ctx.mta.findLookTargetResult(req.params.id));
    })
  );

  app.post(
    "/mta/teleport/airport",
    asyncRoute(async (req, res) => {
      const body = req.body || {};
      const { airportId, locationId, ...options } = body;
      await withPlayerFromBody(ctx, body, async (player) => {
        success(
          res,
          await ctx.mta.teleportToArea(player, {
            ...options,
            locationId: locationId || airportId,
            category: airportId || locationId ? undefined : "airport",
          })
        );
      });
    })
  );

  app.get(
    "/mta/areas",
    asyncRoute(async (req, res) => {
      success(
        res,
        await ctx.mta.listAreas({
          category: req.query.category,
          region: req.query.region,
          search: req.query.search,
        })
      );
    })
  );

  app.get(
    "/mta/areas/map",
    asyncRoute(async (_req, res) => {
      success(res, await ctx.mta.getAreaMap());
    })
  );

  app.get(
    "/mta/areas/closest",
    asyncRoute(async (req, res) => {
      await withPlayerFromBody(ctx, req.query, async (player) => {
        success(
          res,
          await ctx.mta.findClosestArea(player, {
            ...req.query,
          })
        );
      });
    })
  );

  app.post(
    "/mta/teleport",
    asyncRoute(async (req, res) => {
      const body = req.body || {};
      const {
        targetPlayer,
        toPlayer,
        type,
        elementType,
        elementId,
        locationId,
        category,
        region,
        search: areaSearch,
        ...options
      } = body;

      await withPlayerFromBody(ctx, body, async (player) => {
        const targetName = targetPlayer || toPlayer;
        const elementSearch = options.search || options.name;
        const wantsElement =
          targetName || type || elementType || elementId || options.model || elementSearch;

        const result =
          wantsElement && !locationId && !category && !region && !areaSearch
            ? await ctx.mta.teleportToElement(player, {
                ...options,
                targetPlayer: targetName,
                type: type || elementType,
                elementId,
              })
            : await ctx.mta.teleportToArea(player, {
                ...options,
                locationId,
                category,
                region,
                search: areaSearch,
              });
        success(res, result);
      });
    })
  );

  app.post(
    "/mta/teleport/player",
    asyncRoute(async (req, res) => {
      const body = req.body || {};
      const target = body.targetPlayer || body.toPlayer;
      if (!target) {
        throw httpError("targetPlayer is required", { status: 400 });
      }
      await withPlayerFromBody(ctx, body, async (player) => {
        success(res, await ctx.mta.teleportToPlayer(player, target, body));
      });
    })
  );

  app.post(
    "/mta/teleport/element",
    asyncRoute(async (req, res) => {
      const body = req.body || {};
      await withPlayerFromBody(ctx, body, async (player) => {
        success(res, await ctx.mta.teleportToElement(player, body));
      });
    })
  );
}

module.exports = { registerMtaLegacyRoutes };
