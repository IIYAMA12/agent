function isRestartAllowed() {
  return process.env.ALLOW_RESTART === "1";
}

function assertRestartAllowed() {
  if (!isRestartAllowed()) {
    const error = new Error(
      "Restart disabled — set ALLOW_RESTART=1 in node/.env to allow agent/middleware auto-restart"
    );
    error.code = "RESTART_DISABLED";
    error.hint = "Set ALLOW_RESTART=1 in node/.env, then reload MCP in Cursor";
    throw error;
  }
}

module.exports = { isRestartAllowed, assertRestartAllowed };
