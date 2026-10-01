"use strict";

const fs = require("fs");
const path = require("path");
const { reloadLocalFeatures } = require("../shared/features");
const { reloadLocalShapes } = require("../shared/models/local-shapes");
const { createMtaClient } = require("../shared/config");

const AGENT_ROOT = path.join(__dirname, "../..");
const CLIENT_DIR = path.join(AGENT_ROOT, "local", "client");
const NODE_LOCAL = path.join(AGENT_ROOT, "node", "local");

function isIgnored(filename) {
  if (!filename) return false;
  return String(filename)
    .split(/[/\\]/)
    .some((part) => part.startsWith("_") || part.startsWith("."));
}

function listClientScripts(dir = CLIENT_DIR, prefix = "local/client") {
  const files = [];
  if (!fs.existsSync(dir)) return files;
  for (const name of fs.readdirSync(dir)) {
    if (name.startsWith("_") || name.startsWith(".")) continue;
    const full = path.join(dir, name);
    const rel = `${prefix}/${name}`.replace(/\\/g, "/");
    if (fs.statSync(full).isDirectory()) {
      files.push(...listClientScripts(full, rel));
    } else if (name.endsWith(".lua")) {
      files.push(rel);
    }
  }
  files.sort();
  return files;
}

function startLocalWatcher(log = console) {
  let timer = null;
  let lua = false;
  let js = false;

  const flush = async () => {
    timer = null;
    const doJs = js;
    const doLua = lua;
    js = false;
    lua = false;

    if (doJs) {
      try {
        reloadLocalShapes();
        const ids = reloadLocalFeatures();
        log.log(`[agent-middleware] reloaded local node modules (${ids.length} features)`);
      } catch (error) {
        log.error("[agent-middleware] local node reload failed:", error.message || error);
      }
    }

    if (doLua) {
      try {
        const files = listClientScripts();
        const result = await createMtaClient().invoke("reloadLocalClient", [{ files }]);
        log.log("[agent-middleware] reloaded local client scripts", JSON.stringify(result));
      } catch (error) {
        log.error("[agent-middleware] local client reload failed:", error.message || error);
      }
    }
  };

  const schedule = (kind, filename) => {
    if (isIgnored(filename)) return;
    if (kind === "js" && filename && !String(filename).endsWith(".js")) return;
    if (kind === "lua" && filename && !String(filename).endsWith(".lua")) return;
    if (kind === "js") js = true;
    if (kind === "lua") lua = true;
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      flush().catch((error) => {
        log.error("[agent-middleware] local reload failed:", error.message || error);
      });
    }, 150);
  };

  const watch = (dir, kind) => {
    if (!fs.existsSync(dir)) return;
    try {
      fs.watch(dir, { recursive: true }, (_event, filename) => schedule(kind, filename));
      log.log(`[agent-middleware] watching ${path.relative(AGENT_ROOT, dir)}`);
    } catch (error) {
      log.error(`[agent-middleware] watch failed for ${dir}:`, error.message || error);
    }
  };

  watch(NODE_LOCAL, "js");
  watch(CLIENT_DIR, "lua");
}

module.exports = { startLocalWatcher, listClientScripts };
