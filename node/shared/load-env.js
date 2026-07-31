const fs = require("fs");
const path = require("path");

const NODE_ROOT = path.join(__dirname, "..");

const ENV_FILE = ".env";

let loaded = false;

/**
 * @param {string} content
 * @returns {Record<string, string>}
 */
function parseEnvContent(content) {
  /** @type {Record<string, string>} */
  const out = {};
  const lines = String(content || "").split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    let value = trimmed.slice(eq + 1).trim();
    const q = value[0];
    if ((q === '"' || q === "'") && value.endsWith(q) && value.length >= 2) {
      value = value.slice(1, -1);
      if (q === '"') {
        value = value.replace(/\\"/g, '"').replace(/\\\\/g, "\\");
      }
    }
    out[key] = value;
  }
  return out;
}

/**
 * Create missing node/.env from .env.example.
 * @returns {{ created: string[] }}
 */
function ensureEnvPlaceholders() {
  const created = [];
  const envPath = path.join(NODE_ROOT, ENV_FILE);
  const examplePath = path.join(NODE_ROOT, ".env.example");

  if (!fs.existsSync(envPath) && fs.existsSync(examplePath)) {
    fs.copyFileSync(examplePath, envPath);
    created.push(ENV_FILE);
  }

  return { created };
}

/**
 * Ensure .env exists, then load it once. Safe to call repeatedly.
 * @returns {{ loaded: string[], created: string[], nodeRoot: string }}
 */
function loadEnv() {
  const { created } = ensureEnvPlaceholders();
  const loadedFiles = [];
  const filePath = path.join(NODE_ROOT, ENV_FILE);

  if (fs.existsSync(filePath)) {
    const vars = parseEnvContent(fs.readFileSync(filePath, "utf8"));
    for (const key of Object.keys(vars)) {
      process.env[key] = vars[key];
    }
    loadedFiles.push(ENV_FILE);
  }

  loaded = true;
  return { loaded: loadedFiles, created, nodeRoot: NODE_ROOT };
}

function ensureEnvLoaded() {
  if (!loaded) {
    loadEnv();
  }
}

module.exports = {
  loadEnv,
  ensureEnvLoaded,
  ensureEnvPlaceholders,
  NODE_ROOT,
  ENV_FILES: [ENV_FILE],
};
