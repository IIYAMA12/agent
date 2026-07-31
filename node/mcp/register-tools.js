const { z } = require("zod");
const { listFeatures } = require("../shared/features");
const { featureIdToMcpTool } = require("../shared/lib/tools-manifest");
const { middlewareRequest } = require("./client");
const { createMtaClient } = require("../shared/config");
const {
  restartMiddleware,
  restartAgentResource,
  restartAgentAndMiddleware,
} = require("../shared/lib/middleware-process");

const paramValue = z.union([z.string(), z.number(), z.boolean()]);

function toolResult(data) {
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

function toolError(error) {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(
          { error: error.message, code: error.code, hint: error.hint, body: error.body },
          null,
          2
        ),
      },
    ],
    isError: true,
  };
}

function paramsToZodShape(params = {}) {
  const shape = {};
  for (const [key, meta] of Object.entries(params)) {
    shape[key] = meta?.required ? paramValue : paramValue.optional();
  }
  shape.player = z.string().optional().describe("MTA player name (auto-resolved if omitted)");
  return shape;
}

function registerTool(server, name, description, shape, handler, registeredTools) {
  if (registeredTools.has(name)) {
    return false;
  }
  registeredTools.add(name);
  server.tool(name, description, shape, async (args) => {
    try {
      return toolResult(await handler(args));
    } catch (error) {
      return toolError(error);
    }
  });
  return true;
}

function registerMcpTools(server) {
  const registeredTools = new Set();

  registerTool(
    server,
    "mta_health",
    "Check middleware and MTA server health, online players, and available features",
    {},
    () => middlewareRequest("GET", "/health"),
    registeredTools
  );

  registerTool(
    server,
    "mta_list_features",
    "List all registered MTA agent features (teleport, look, nearby, eval, etc.)",
    {},
    async () => {
      try {
        return await middlewareRequest("GET", "/mta/features");
      } catch {
        return listFeatures();
      }
    },
    registeredTools
  );

  registerTool(
    server,
    "mta_run_feature",
    "Run any MTA agent feature by id (e.g. teleport.area, eval.client, look.target)",
    {
      feature: z.string().describe("Feature id, e.g. teleport.area"),
      player: z.string().optional().describe("MTA player name (auto-resolved if omitted)"),
      params: z.record(paramValue).optional().describe("Feature-specific parameters"),
    },
    async ({ feature, player, params = {} }) => {
      const body = { ...params };
      if (player) body.player = player;
      return middlewareRequest("POST", "/mta/do", { feature, ...body });
    },
    registeredTools
  );

  registerTool(
    server,
    "mta_restart_agent",
    "Restart the agent MTA resource (requires ALLOW_RESTART=1 in node/.env)",
    {
      resource: z.string().optional().describe("Resource name (default: agent)"),
      wait: z.boolean().optional().describe("Wait for MTA ping after restart (default: true)"),
    },
    async ({ resource, wait = true }) => {
      const mta = createMtaClient();
      return restartAgentResource(mta, { resource, wait });
    },
    registeredTools
  );

  registerTool(
    server,
    "mta_restart_middleware",
    "Restart the Node middleware HTTP server (requires ALLOW_RESTART=1 in node/.env)",
    {
      wait: z.boolean().optional().describe("Wait until middleware is listening again (default: true)"),
    },
    async ({ wait = true }) => restartMiddleware({ wait }),
    registeredTools
  );

  registerTool(
    server,
    "mta_restart_all",
    "Restart agent MTA resource and Node middleware (requires ALLOW_RESTART=1 in node/.env)",
    {
      resource: z.string().optional().describe("Resource name (default: agent)"),
      wait: z.boolean().optional().describe("Wait for both to become ready (default: true)"),
    },
    async ({ resource, wait = true }) => {
      const mta = createMtaClient();
      return restartAgentAndMiddleware(mta, { resource, wait });
    },
    registeredTools
  );

  for (const feature of listFeatures()) {
    registerTool(
      server,
      featureIdToMcpTool(feature.id),
      feature.description,
      paramsToZodShape(feature.params),
      (args) => middlewareRequest("POST", `/mta/features/${feature.id}`, args),
      registeredTools
    );
  }
}

module.exports = { registerMcpTools };
