const { httpError } = require("./http-error");

function normalizeClientEvalResult(polled, player) {
  const entries = polled?.results;
  if (!Array.isArray(entries) || entries.length === 0) {
    return polled;
  }

  if (entries.length === 1) {
    const entry = entries[0];
    if (!entry.ok) {
      throw httpError(entry.error || "Client eval failed", {
        status: 400,
        code: "CLIENT_EVAL_FAILED",
        body: entry,
      });
    }
    return { player: entry.player, result: entry.result };
  }

  return { player, results: entries };
}

module.exports = { normalizeClientEvalResult };
