const { registerHealthRoutes } = require("./health");
const { registerFeatureRoutes } = require("./features");
const { registerMemoryRoutes } = require("./memory");
const { registerMtaLegacyRoutes } = require("./mta-legacy");
const { registerAdminRoutes } = require("./admin");
const { registerStatusRoutes } = require("./status");

function registerRoutes(app, ctx) {
  registerHealthRoutes(app, ctx);
  registerStatusRoutes(app, ctx);
  registerFeatureRoutes(app, ctx);
  registerMtaLegacyRoutes(app, ctx);
  registerMemoryRoutes(app, ctx);
  registerAdminRoutes(app, ctx);
}

module.exports = { registerRoutes };
