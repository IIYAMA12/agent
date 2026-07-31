const { success, failure } = require("../../shared/lib/respond");

function registerMemoryRoutes(app, ctx) {
  app.get("/memory", (req, res) => {
    const prefix = typeof req.query.prefix === "string" ? req.query.prefix : "";
    success(res, ctx.memory.list(prefix));
  });

  app.get("/memory/:key", (req, res) => {
    success(res, ctx.memory.get(req.params.key), { key: req.params.key });
  });

  app.post("/memory", (req, res) => {
    const { key, value } = req.body || {};
    if (!key || typeof key !== "string") {
      return failure(res, { message: "key is required", code: "KEY_REQUIRED" }, 400);
    }
    ctx.memory.set(key, value);
    success(res, value, { key });
  });

  app.delete("/memory/:key", (req, res) => {
    ctx.memory.delete(req.params.key);
    success(res, null, { key: req.params.key });
  });
}

module.exports = { registerMemoryRoutes };
