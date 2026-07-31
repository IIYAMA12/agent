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
const { registerResourceFeatures } = require("./resources");

const registry = new FeatureRegistry();

registerTeleportFeatures(registry);
registerLookFeatures(registry);
registerNearbyFeatures(registry);
registerEvalFeatures(registry);
registerElementFeatures(registry);
registerSystemFeatures(registry);
registerGuiFeatures(registry);
registerDebugFeatures(registry);
registerHealthFeatures(registry);
registerResourceFeatures(registry);

function listFeatures() {
  return registry.list();
}

function getFeature(id) {
  return registry.get(id);
}

function runFeature(id, mta, params) {
  return registry.run(id, mta, params);
}

module.exports = { listFeatures, getFeature, runFeature, registry };
