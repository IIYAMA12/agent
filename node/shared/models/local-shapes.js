"use strict";

const fs = require("fs");
const path = require("path");

const LOCAL_DIR = path.join(__dirname, "../../local/models");

/** @type {Array<{ shapes: string[], generate?: Function, test?: Function }>|null} */
let modules = null;

function loadModules() {
  if (modules) return modules;
  modules = [];
  if (!fs.existsSync(LOCAL_DIR)) return modules;
  for (const name of fs.readdirSync(LOCAL_DIR)) {
    if (!name.endsWith(".js") || name.startsWith("_")) continue;
    const mod = require(path.join(LOCAL_DIR, name));
    if (mod && Array.isArray(mod.shapes)) modules.push(mod);
  }
  return modules;
}

function clearNodeLocalCache() {
  const root = path.resolve(path.join(__dirname, "../../local"));
  const prefix = root + path.sep;
  for (const key of Object.keys(require.cache)) {
    const resolved = path.resolve(key);
    if (resolved === root || resolved.startsWith(prefix)) {
      delete require.cache[key];
    }
  }
}

function reloadLocalShapes() {
  modules = null;
  clearNodeLocalCache();
}

function findLocalShape(shape) {
  const key = String(shape || "").toLowerCase();
  if (!key) return null;
  for (const mod of loadModules()) {
    if (mod.shapes.some((entry) => String(entry).toLowerCase() === key)) return mod;
  }
  return null;
}

module.exports = { findLocalShape, reloadLocalShapes };
