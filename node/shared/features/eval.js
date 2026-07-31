const { httpError } = require("../lib/http-error");
const { normalizeClientEvalResult } = require("../lib/client-eval");

function registerEvalFeatures(registry) {
  registry.register("eval.server", {
    description:
      "Run Lua on the MTA server via loadstring (middleware HTTP/MCP; requires ALLOW_HTTP_EVAL=1 in node/.env)",
    params: { code: { required: true } },
    run: async (mta, params) => {
      if (process.env.ALLOW_HTTP_EVAL !== "1") {
        throw httpError(
          "Server eval disabled — set ALLOW_HTTP_EVAL=1 in node/.env (does not affect MTA /agent/call/eval)",
          {
            status: 403,
            code: "EVAL_DISABLED",
            hint: "ALLOW_HTTP_EVAL only gates middleware/MCP. Direct MTA HTTP eval still works, or use typed feature endpoints.",
          }
        );
      }
      if (!params.code || typeof params.code !== "string") {
        throw httpError("code is required", { status: 400 });
      }
      return mta.eval(params.code);
    },
  });

  registry.register("eval.client", {
    description:
      "Run Lua on a specific player's client via loadstring (player or serial required, auto-polls)",
    params: { player: { optional: true }, serial: { optional: true }, code: { required: true } },
    run: async (mta, params) => {
      if (!params.code || typeof params.code !== "string") {
        throw httpError("code is required", { status: 400 });
      }
      if (!params.player && !params.serial) {
        throw httpError("player or serial is required for client eval", {
          status: 400,
          code: "PLAYER_REQUIRED",
        });
      }

      const options = params.serial ? { serial: params.serial } : {};
      const polled = await mta.evalClientComplete(params.code, params.player || null, options);
      return normalizeClientEvalResult(polled, params.player || params.serial);
    },
  });
}

module.exports = { registerEvalFeatures };
