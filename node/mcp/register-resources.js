const { middlewareRequest } = require("./client");

const STATUS_URI = "mta://server/status";

function registerMcpResources(server) {
  server.registerResource(
    "server-status",
    STATUS_URI,
    {
      title: "MTA Server Status",
      description:
        "Cached snapshot: MTA reachability, online players, resource counts, server memory/CPU/network. Refreshed by middleware every few seconds.",
      mimeType: "application/json",
    },
    async () => {
      let snapshot;
      try {
        snapshot = await middlewareRequest("GET", "/api/status");
      } catch (error) {
        snapshot = {
          updatedAt: new Date().toISOString(),
          mta: { ok: false },
          errors: [{ scope: "mcp", message: error.message }],
        };
      }

      return {
        contents: [
          {
            uri: STATUS_URI,
            mimeType: "application/json",
            text: JSON.stringify(snapshot, null, 2),
          },
        ],
      };
    }
  );
}

module.exports = { registerMcpResources, STATUS_URI };
