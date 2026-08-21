const express = require("express");
const { registerRoutes } = require("./routes");

function createApp(ctx) {
  const app = express();
  // Model test payloads carry gzip+base64 DFF/TXD/COL (can exceed default 100kb)
  app.use(express.json({ limit: "8mb" }));
  registerRoutes(app, ctx);
  return app;
}

module.exports = { createApp };
