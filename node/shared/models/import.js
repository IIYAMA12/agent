"use strict";

const fs = require("fs");
const path = require("path");
const { ensureModelsLayout, getImportRoot, getAgentRoot } = require("./paths");

const IMAGE_EXT = new Set([".png", ".PNG", ".jpg", ".JPG", ".jpeg", ".JPEG"]);

function assertNoTraversal(rel) {
  const normalized = path.normalize(rel).replace(/\\/g, "/");
  if (normalized.startsWith("..") || normalized.includes("/../") || path.isAbsolute(normalized)) {
    throw new Error("textureFile must be relative to models/import (no .. or absolute paths)");
  }
  return normalized;
}

/**
 * List files under models/import
 * @param {{ recursive?: boolean }} [options]
 */
function listImportFiles(options = {}) {
  const { importRoot } = ensureModelsLayout();
  const recursive = options.recursive !== false;
  const results = [];

  function walk(dir, prefix) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.name === ".gitkeep") continue;
      const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (recursive) walk(full, rel);
        continue;
      }
      if (!IMAGE_EXT.has(path.extname(entry.name))) continue;
      const stat = fs.statSync(full);
      results.push({
        name: rel.replace(/\\/g, "/"),
        path: full,
        size: stat.size,
        mtime: stat.mtime.toISOString(),
      });
    }
  }

  walk(importRoot, "");
  results.sort((a, b) => a.name.localeCompare(b.name));
  return { importRoot, files: results };
}

/**
 * Resolve texture source from textureFile (under import/) or texturePath (explicit).
 * @param {{ textureFile?: string, texturePath?: string }} options
 * @returns {{ absolutePath: string, source: string, label: string }|null}
 */
function resolveTextureFile(options = {}) {
  ensureModelsLayout();

  if (options.textureFile) {
    const rel = assertNoTraversal(String(options.textureFile));
    const absolutePath = path.join(getImportRoot(), rel);
    if (!fs.existsSync(absolutePath) || !fs.statSync(absolutePath).isFile()) {
      throw new Error(`textureFile not found in models/import: ${rel}`);
    }
    return { absolutePath, source: "import", label: rel };
  }

  if (options.texturePath) {
    let absolutePath = String(options.texturePath);
    if (!path.isAbsolute(absolutePath)) {
      absolutePath = path.resolve(getAgentRoot(), absolutePath);
    }
    absolutePath = path.normalize(absolutePath);
    if (!fs.existsSync(absolutePath) || !fs.statSync(absolutePath).isFile()) {
      throw new Error(`texturePath not found: ${absolutePath}`);
    }
    return {
      absolutePath,
      source: "path",
      label: absolutePath,
    };
  }

  return null;
}

module.exports = {
  listImportFiles,
  resolveTextureFile,
};
