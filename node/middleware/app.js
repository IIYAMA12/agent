const express = require("express");
const { registerRoutes } = require("./routes");

function createApp(ctx) {
  const app = express();
  app.use(express.json({ limit: "1mb" }));
  registerRoutes(app, ctx);
  return app;
}

module.exports = { createApp };
