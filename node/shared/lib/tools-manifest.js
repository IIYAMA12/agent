const { listFeatures } = require("../features");
const { VERSION } = require("../config");

function buildToolsManifest() {
  const features = listFeatures();
  return {
    version: VERSION,
    features: features.map((feature) => ({
      id: feature.id,
      description: feature.description,
      params: feature.params,
      endpoint: `POST /mta/features/${feature.id}`,
      mcpTool: featureIdToMcpTool(feature.id),
    })),
    metaTools: [
      { id: "mta_health", endpoint: "GET /health" },
      { id: "mta_list_features", endpoint: "GET /mta/features" },
      { id: "mta_run_feature", endpoint: "POST /mta/do" },
      { id: "mta_do", endpoint: "POST /mta/do" },
      { id: "mta_restart_agent", endpoint: "MCP local" },
      { id: "mta_restart_middleware", endpoint: "MCP local" },
      { id: "mta_restart_all", endpoint: "MCP local" },
      { id: "mta_system_status", endpoint: "MCP local / GET /admin/status" },
    ],
  };
}

function featureIdToMcpTool(featureId) {
  return `mta_${String(featureId).replace(/\./g, "_")}`;
}

module.exports = { buildToolsManifest, featureIdToMcpTool };
