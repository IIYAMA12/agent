const path = require("path");

const { loadEnv } = require("./load-env");
loadEnv();

const { MtaClient } = require("./mta-client");
const { MemoryStore } = require("./memory");
const { getCredentials } = require("./credentials");

const VERSION = "1.1.0";

function createMtaClient(overrides = {}) {
  const creds = getCredentials();
  return new MtaClient({
    host: process.env.MTA_HOST || "127.0.0.1",
    port: Number(process.env.MTA_PORT || 22005),
    user: creds.user,
    password: creds.password,
    resource: process.env.MTA_RESOURCE || "agent",
    ...overrides,
  });
}

function createMiddlewareContext() {
  const creds = getCredentials();
  return {
    version: VERSION,
    creds,
    mta: createMtaClient(),
    memory: new MemoryStore(process.env.MEMORY_DB || path.join(__dirname, "../data/memory.db")),
    host: process.env.MIDDLEWARE_HOST || "127.0.0.1",
    port: Number(process.env.MIDDLEWARE_PORT || 3847),
  };
}

module.exports = { VERSION, createMiddlewareContext, createMtaClient };
