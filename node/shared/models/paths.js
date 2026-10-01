"use strict";

const fs = require("fs");
const path = require("path");

/** Agent resource root (parent of node/) */
function getAgentRoot() {
  return path.resolve(__dirname, "..", "..", "..");
}

function getModelsRoot() {
  return path.join(getAgentRoot(), "models");
}

function getImportRoot() {
  return path.join(getModelsRoot(), "import");
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function ensureModelsLayout() {
  const modelsRoot = ensureDir(getModelsRoot());
  const importRoot = ensureDir(getImportRoot());
  const importKeep = path.join(importRoot, ".gitkeep");
  if (!fs.existsSync(importKeep)) {
    fs.writeFileSync(importKeep, "");
  }
  const modelsKeep = path.join(modelsRoot, ".gitkeep");
  if (!fs.existsSync(modelsKeep)) {
    fs.writeFileSync(modelsKeep, "");
  }
  return { modelsRoot, importRoot };
}

function isUuidFolderName(name) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(name);
}

/** UTC stamp + UUID, e.g. 2026-08-21_195032_<uuid> (also accepts legacy uuid-only folders) */
function isModelFolderName(name) {
  if (isUuidFolderName(name)) return true;
  const m = String(name || "").match(/^(\d{4}-\d{2}-\d{2}_\d{6})_(.+)$/);
  return Boolean(m && isUuidFolderName(m[2]));
}

module.exports = {
  getAgentRoot,
  getModelsRoot,
  getImportRoot,
  ensureDir,
  ensureModelsLayout,
  isUuidFolderName,
  isModelFolderName,
};
