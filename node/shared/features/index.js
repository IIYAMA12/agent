const fs = require("fs");
const path = require("path");
const { FeatureRegistry } = require("./registry");
const { registerTeleportFeatures } = require("./teleport");
const { registerLookFeatures } = require("./look");
const { registerNearbyFeatures } = require("./nearby");
const { registerEvalFeatures } = require("./eval");
const { registerElementFeatures } = require("./elements");
const { registerSystemFeatures } = require("./system");
const { registerGuiFeatures } = require("./gui");
const { registerDebugFeatures } = require("./debug");
const { registerHealthFeatures } = require("./health");
const { registerScreenFeatures } = require("./screen");
const { registerResourceFeatures } = require("./resources");
const { registerModelFeatures } = require("./models");
const { registerBoundingFeatures } = require("./bounding");

const registry = new FeatureRegistry();
const localFeatureIds = new Set();
const LOCAL_FEATURES_DIR = path.join(__dirname, "../../local/features");
const NODE_LOCAL_DIR = path.resolve(path.join(__dirname, "../../local"));

registerTeleportFeatures(registry);
registerLookFeatures(registry);
registerNearbyFeatures(registry);
registerEvalFeatures(registry);
registerElementFeatures(registry);
registerSystemFeatures(registry);
registerGuiFeatures(registry);
registerDebugFeatures(registry);
registerHealthFeatures(registry);
registerScreenFeatures(registry);
registerResourceFeatures(registry);
registerModelFeatures(registry);
registerBoundingFeatures(registry);
{
  const initial = loadLocalFeatures(registry);
  if (initial.errors.length) {
    console.error("[agent] local features:", initial.errors.join("; "));
  }
}

function clearNodeLocalCache() {
  const prefix = NODE_LOCAL_DIR + path.sep;
  for (const key of Object.keys(require.cache)) {
    const resolved = path.resolve(key);
    if (resolved === NODE_LOCAL_DIR || resolved.startsWith(prefix)) {
      delete require.cache[key];
    }
  }
}

function loadLocalFeatures(registry) {
  const before = new Set(registry.list().map((feature) => feature.id));
  if (!fs.existsSync(LOCAL_FEATURES_DIR)) return [];
  const errors = [];
  for (const name of fs.readdirSync(LOCAL_FEATURES_DIR)) {
    if (!name.endsWith(".js") || name.startsWith("_")) continue;
    try {
      const mod = require(path.join(LOCAL_FEATURES_DIR, name));
      if (typeof mod.register === "function") mod.register(registry);
    } catch (error) {
      errors.push(`${name}: ${error.message || error}`);
    }
  }
  const added = [];
  for (const feature of registry.list()) {
    if (!before.has(feature.id)) {
      localFeatureIds.add(feature.id);
      added.push(feature.id);
    }
  }
  return { ids: added, errors };
}

function reloadLocalFeatures() {
  for (const id of localFeatureIds) registry.unregister(id);
  localFeatureIds.clear();
  clearNodeLocalCache();
  const result = loadLocalFeatures(registry);
  if (result.errors.length) {
    const error = new Error(result.errors.join("; "));
    error.ids = result.ids;
    throw error;
  }
  return result.ids;
}

function listFeatures() {
  return registry.list();
}

function getFeature(id) {
  return registry.get(id);
}

function runFeature(id, mta, params) {
  return registry.run(id, mta, params);
}

module.exports = { listFeatures, getFeature, runFeature, registry, reloadLocalFeatures };
