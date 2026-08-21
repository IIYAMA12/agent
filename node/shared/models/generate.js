"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { ensureModelsLayout, getModelsRoot, isUuidFolderName } = require("./paths");
const { resolveTextureFile } = require("./import");
const { decodeImageToBgra, encodeBgraToPng, resizeBgraNearest, solidBgra } = require("./png");
const { buildGeometry } = require("./geometry");
const { buildTxd } = require("./txd-builder");
const { buildDff } = require("./dff-builder");
const { buildCol } = require("./col-builder");

const DEFAULT_TEXTURE_SIZE = 256;
const DEFAULT_MODEL_ID = 1851;

function parseColor(color) {
  if (!color) return { r: 180, g: 180, b: 180, a: 255 };
  if (Array.isArray(color)) {
    return { r: color[0] ?? 180, g: color[1] ?? 180, b: color[2] ?? 180, a: color[3] ?? 255 };
  }
  if (typeof color === "object") {
    return {
      r: color.r ?? color.red ?? 180,
      g: color.g ?? color.green ?? 180,
      b: color.b ?? color.blue ?? 180,
      a: color.a ?? color.alpha ?? 255,
    };
  }
  if (typeof color === "string" && color.startsWith("#")) {
    const hex = color.slice(1);
    const full = hex.length === 3 ? hex.split("").map((c) => c + c).join("") : hex;
    const n = parseInt(full.slice(0, 6), 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255, a: 255 };
  }
  return { r: 180, g: 180, b: 180, a: 255 };
}

function nextPowerOfTwo(n) {
  let p = 4;
  while (p < n) p *= 2;
  return Math.min(1024, p);
}

function resolvePixels(options) {
  const requested = Number(options.textureSize) || DEFAULT_TEXTURE_SIZE;
  const size = nextPowerOfTwo(Math.max(4, requested));
  const textureRef = resolveTextureFile(options);

  if (textureRef) {
    const imageBuf = fs.readFileSync(textureRef.absolutePath);
    const decoded = decodeImageToBgra(imageBuf, textureRef.absolutePath);
    const pixels = resizeBgraNearest(decoded.pixels, decoded.width, decoded.height, size);
    return {
      pixels,
      size,
      hasAlpha: decoded.format === "png",
      sourceTexture: { ...textureRef, format: decoded.format },
      textureName: path.basename(textureRef.label, path.extname(textureRef.label)).replace(/[^a-zA-Z0-9_]/g, "_").slice(0, 31) || "texture",
    };
  }

  const color = parseColor(options.color);
  return {
    pixels: solidBgra(size, color),
    size,
    hasAlpha: color.a < 255,
    sourceTexture: null,
    textureName: "texture",
    solidColor: color,
  };
}

/**
 * Generate DFF/TXD/COL into models/<uuid>/
 * @param {object} options
 */
function generateModel(options = {}) {
  ensureModelsLayout();
  const id = crypto.randomUUID();
  const outDir = path.join(getModelsRoot(), id);
  fs.mkdirSync(outDir, { recursive: true });

  const compression = options.compression === "none" ? "none" : "dxt1";
  const modelId = Number(options.modelId) || DEFAULT_MODEL_ID;
  const tex = resolvePixels(options);
  const vertexColor = options.vertexColor
    ? [
        options.vertexColor[0] ?? 255,
        options.vertexColor[1] ?? 255,
        options.vertexColor[2] ?? 255,
      ]
    : [255, 255, 255];

  const { quads, boxes } = buildGeometry({
    shape: options.shape || "box",
    sizeX: options.sizeX ?? options.width ?? 1,
    sizeY: options.sizeY ?? options.depth,
    sizeZ: options.sizeZ ?? options.height ?? 1,
    radius: options.radius,
    sides: options.sides,
    textureName: tex.textureName,
    vertexColor,
  });

  const txd = buildTxd(
    [
      {
        name: tex.textureName,
        pixels: tex.pixels,
        size: tex.size,
        hasAlpha: tex.hasAlpha,
        clamp: Boolean(options.clamp),
      },
    ],
    { compression }
  );
  const dff = buildDff(quads);
  const col = buildCol(boxes, { modelId, name: options.name || "agentmdl" });

  const dffPath = path.join(outDir, "model.dff");
  const txdPath = path.join(outDir, "model.txd");
  const colPath = path.join(outDir, "model.col");
  const pngPath = path.join(outDir, "texture.png");
  const metaPath = path.join(outDir, "meta.json");

  fs.writeFileSync(dffPath, dff.data);
  fs.writeFileSync(txdPath, txd.data);
  fs.writeFileSync(colPath, col.data);
  fs.writeFileSync(pngPath, encodeBgraToPng(tex.pixels, tex.size, tex.size));

  const meta = {
    id,
    createdAt: new Date().toISOString(),
    shape: options.shape || "box",
    sizeX: options.sizeX ?? options.width ?? 1,
    sizeY: options.sizeY ?? options.depth ?? options.sizeX ?? 1,
    sizeZ: options.sizeZ ?? options.height ?? 1,
    sides: options.sides || null,
    compression,
    textureSize: tex.size,
    textureName: tex.textureName,
    sourceTexture: tex.sourceTexture
      ? {
          source: tex.sourceTexture.source,
          label: tex.sourceTexture.label,
          format: tex.sourceTexture.format || null,
        }
      : tex.solidColor
        ? { source: "solid", color: tex.solidColor }
        : null,
    modelId,
    files: {
      dff: "model.dff",
      txd: "model.txd",
      col: "model.col",
      texture: "texture.png",
    },
    build: {
      dff: dff.info,
      txd: txd.info,
      col: col.info,
    },
  };
  fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));

  return {
    id,
    path: outDir,
    files: {
      dff: dffPath,
      txd: txdPath,
      col: colPath,
      texture: pngPath,
      meta: metaPath,
    },
    meta,
  };
}

function listModels() {
  ensureModelsLayout();
  const root = getModelsRoot();
  const entries = [];
  for (const name of fs.readdirSync(root)) {
    if (!isUuidFolderName(name)) continue;
    const dir = path.join(root, name);
    if (!fs.statSync(dir).isDirectory()) continue;
    const metaPath = path.join(dir, "meta.json");
    let meta = null;
    if (fs.existsSync(metaPath)) {
      try {
        meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
      } catch {
        meta = null;
      }
    }
    entries.push({ id: name, path: dir, meta });
  }
  entries.sort((a, b) => String(b.meta?.createdAt || "").localeCompare(String(a.meta?.createdAt || "")));
  return entries;
}

function getModel(id) {
  if (!isUuidFolderName(id)) {
    throw new Error("invalid model id");
  }
  const dir = path.join(getModelsRoot(), id);
  if (!fs.existsSync(dir)) {
    throw new Error(`model not found: ${id}`);
  }
  const metaPath = path.join(dir, "meta.json");
  const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
  const files = {
    dff: path.join(dir, "model.dff"),
    txd: path.join(dir, "model.txd"),
    col: path.join(dir, "model.col"),
    texture: path.join(dir, "texture.png"),
    meta: metaPath,
  };
  const sizes = {};
  for (const [key, filePath] of Object.entries(files)) {
    if (fs.existsSync(filePath)) sizes[key] = fs.statSync(filePath).size;
  }
  return { id, path: dir, meta, files, sizes };
}

function deleteModel(id) {
  const model = getModel(id);
  fs.rmSync(model.path, { recursive: true, force: true });
  return { id, deleted: true };
}

function readModelBuffers(id) {
  const model = getModel(id);
  return {
    id,
    meta: model.meta,
    dff: fs.readFileSync(model.files.dff),
    txd: fs.readFileSync(model.files.txd),
    col: fs.readFileSync(model.files.col),
  };
}

module.exports = {
  generateModel,
  listModels,
  getModel,
  deleteModel,
  readModelBuffers,
  DEFAULT_MODEL_ID,
};
