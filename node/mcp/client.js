const DEFAULT_URL = process.env.MIDDLEWARE_URL || "http://127.0.0.1:3847";
const { ensureMiddlewareRunning, registerMcpMiddlewareUse } = require("../shared/lib/middleware-process");

async function middlewareRequest(method, path, body, retried = false) {
  const url = `${DEFAULT_URL.replace(/\/$/, "")}${path}`;
  let response;
  try {
    response = await fetch(url, {
      method,
      headers: body !== undefined ? { "Content-Type": "application/json" } : undefined,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (fetchError) {
    if (!retried) {
      try {
        const ensureResult = await ensureMiddlewareRunning();
        registerMcpMiddlewareUse(ensureResult);
      } catch {
        // Fall through to unreachable error below.
      }
      return middlewareRequest(method, path, body, true);
    }
    const error = new Error(`Middleware unreachable at ${DEFAULT_URL}: ${fetchError.message}`);
    error.code = "MIDDLEWARE_UNREACHABLE";
    error.hint = "Start manually: cd node && npm start";
    throw error;
  }

  let data;
  try {
    data = await response.json();
  } catch {
    const text = await response.text();
    const error = new Error(`Middleware returned non-JSON (${response.status}): ${text}`);
    error.code = "MIDDLEWARE_ERROR";
    error.status = response.status;
    throw error;
  }

  if (!response.ok || data.ok === false) {
    const error = new Error(data.error || `Middleware request failed (${response.status})`);
    error.code = data.code || "MIDDLEWARE_ERROR";
    error.hint = data.hint;
    error.body = data.body;
    error.status = response.status;
    throw error;
  }

  return data.data !== undefined ? data.data : data.result !== undefined ? data.result : data;
}

module.exports = { middlewareRequest, DEFAULT_URL };
