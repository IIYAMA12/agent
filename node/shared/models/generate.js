"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { ensureModelsLayout, getModelsRoot, isModelFolderName } = require("./paths");
const { resolveTextureFile } = require("./import");
const { decodeImageToBgra, encodeBgraToPng, resizeBgraNearest, solidBgra } = require("./png");
const { buildGeometry } = require("./geometry");
const { buildTxd } = require("./txd-builder");
const { buildDff } = require("./dff-builder");
const { buildCol } = require("./col-builder");
const { findLocalShape } = require("./local-shapes");

const DEFAULT_TEXTURE_SIZE = 256;
const DEFAULT_MODEL_ID = 1851;

/** Filesystem-safe export stamp from a Date (UTC). e.g. 2026-08-21_195032 */
function exportDateStamp(date = new Date()) {
  const iso = date.toISOString();
  return iso.slice(0, 19).replace("T", "_").replace(/:/g, "");
}

function resolveModelFileNames(dir, meta) {
  const legacy = {
    dff: "model.dff",
    txd: "model.txd",
    col: "model.col",
    texture: "texture.png",
  };
  const named = meta?.files || {};
  const files = { meta: path.join(dir, "meta.json") };
  for (const key of ["dff", "txd", "col", "texture"]) {
    if (key === "col" && meta?.col === false) continue;
    const rel = named[key] || legacy[key];
    if (!rel) continue;
    let full = path.join(dir, rel);
    if (!fs.existsSync(full) && named[key] && fs.existsSync(path.join(dir, legacy[key]))) {
      full = path.join(dir, legacy[key]);
    }
    files[key] = full;
  }
  return files;
}

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

function resolveTextureSet(options = {}) {
  const requested = Number(options.textureSize) || DEFAULT_TEXTURE_SIZE;
  const size = nextPowerOfTwo(Math.max(4, requested));
  const textureRef = resolveTextureFile(options);

  if (textureRef) {
    const imageBuf = fs.readFileSync(textureRef.absolutePath);
    const decoded = decodeImageToBgra(imageBuf, textureRef.absolutePath);
    const pixels = resizeBgraNearest(decoded.pixels, decoded.width, decoded.height, size);
    const textureName =
      path.basename(textureRef.label, path.extname(textureRef.label)).replace(/[^a-zA-Z0-9_]/g, "_").slice(0, 31) ||
      "texture";
    return {
      textures: [
        {
          name: textureName,
          pixels,
          size,
          hasAlpha: decoded.format === "png",
          clamp: Boolean(options.clamp),
        },
      ],
      primaryName: textureName,
      sourceTexture: { ...textureRef, format: decoded.format },
    };
  }

  const color = parseColor(options.color);
  return {
    textures: [
      {
        name: "texture",
        pixels: solidBgra(size, color),
        size,
        hasAlpha: color.a < 255,
        clamp: Boolean(options.clamp),
      },
    ],
    primaryName: "texture",
    sourceTexture: null,
    solidColor: color,
  };
}

function wantsCol(options, includeCol) {
  if (options.col === true) return true;
  if (options.col === false) return false;
  return includeCol !== false;
}

/**
 * Write one mesh plus its texture (and optional extra DFF parts) into a dated folder.
 * @param {object} spec
 */
function writeMeshModel(spec) {
  ensureModelsLayout();
  const options = spec.options || {};
  const createdAt = new Date();
  const stamp = exportDateStamp(createdAt);
  const uuid = crypto.randomUUID();
  const id = `${stamp}_${uuid}`;
  const outDir = path.join(getModelsRoot(), id);
  fs.mkdirSync(outDir, { recursive: true });

  const compression = options.compression === "none" ? "none" : "dxt1";
  const modelId = Number(options.modelId) || DEFAULT_MODEL_ID;
  const includeCol = wantsCol(options, spec.includeCol);
  const texSet = spec.texSet;
  const geometry = spec.geometry;

  const txd = buildTxd(texSet.textures, { compression });
  const dff = buildDff(geometry.quads);
  const col = includeCol ? buildCol(geometry.boxes || [], { modelId, name: options.name || "agentmdl" }) : null;

  const extraBuilt = {};
  const extra = spec.extra || {};
  for (const [key, part] of Object.entries(extra)) {
    if (!part) continue;
    extraBuilt[key] = Buffer.isBuffer(part) ? { data: part, info: null } : buildDff(part.quads);
  }

  const fileNames = {
    dff: "model.dff",
    txd: "model.txd",
    texture: "texture.png",
  };
  if (includeCol) fileNames.col = "model.col";
  const extraNames = spec.extraNames || {};
  for (const key of Object.keys(extraBuilt)) {
    fileNames[key] = extraNames[key] || `${key}.dff`;
  }

  const dffPath = path.join(outDir, fileNames.dff);
  const txdPath = path.join(outDir, fileNames.txd);
  const colPath = includeCol ? path.join(outDir, fileNames.col) : null;
  const texturePath = path.join(outDir, fileNames.texture);
  const metaPath = path.join(outDir, "meta.json");

  fs.writeFileSync(dffPath, dff.data);
  fs.writeFileSync(txdPath, txd.data);
  if (col) fs.writeFileSync(colPath, col.data);
  for (const [key, built] of Object.entries(extraBuilt)) {
    fs.writeFileSync(path.join(outDir, fileNames[key]), built.data);
  }

  const primaryTex = texSet.textures[0];
  fs.writeFileSync(texturePath, encodeBgraToPng(primaryTex.pixels, primaryTex.size, primaryTex.size));

  const meta = {
    id,
    uuid,
    createdAt: createdAt.toISOString(),
    exportDate: stamp,
    shape: options.shape || "box",
    sizeX: options.sizeX ?? options.width ?? 1,
    sizeY: options.sizeY ?? options.depth ?? options.sizeX ?? 1,
    sizeZ: options.sizeZ ?? options.height ?? 1,
    diameter: options.diameter ?? null,
    radius: options.radius ?? null,
    sides: options.sides || null,
    segments: geometry.segments ?? options.segments ?? options.points ?? null,
    rings: geometry.rings ?? options.rings ?? options.bands ?? null,
    compression,
    textureSize: primaryTex.size,
    textureName: texSet.primaryName,
    textures: texSet.textures.map((tex) => ({
      name: tex.name,
      size: tex.size,
      clamp: Boolean(tex.clamp),
    })),
    sourceTexture: texSet.sourceTexture
      ? texSet.sourceTexture.source === "procedural"
        ? texSet.sourceTexture
        : {
            source: texSet.sourceTexture.source,
            label: texSet.sourceTexture.label,
            format: texSet.sourceTexture.format || null,
          }
      : texSet.solidColor
        ? { source: "solid", color: texSet.solidColor }
        : null,
    modelId,
    col: includeCol,
    files: fileNames,
    build: {
      dff: dff.info,
      txd: txd.info,
      col: col ? col.info : null,
      ...Object.fromEntries(Object.entries(extraBuilt).map(([key, built]) => [key, built.info])),
    },
    ...(spec.meta || {}),
  };
  fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));

  const files = {
    dff: dffPath,
    txd: txdPath,
    texture: texturePath,
    meta: metaPath,
  };
  if (colPath) files.col = colPath;
  for (const key of Object.keys(extraBuilt)) {
    files[key] = path.join(outDir, fileNames[key]);
  }

  return { id, path: outDir, files, meta };
}

/**
 * Generate DFF/TXD/COL into models/<YYYY-MM-DD_HHMMSS>_<uuid>/
 * @param {object} options
 */
function generateModel(options = {}) {
  const shape = String(options.shape || "box").toLowerCase();
  const local = findLocalShape(shape);
  if (local && typeof local.generate === "function") {
    return local.generate(options);
  }

  const texSet = resolveTextureSet(options);
  const vertexColor = options.vertexColor
    ? [options.vertexColor[0] ?? 255, options.vertexColor[1] ?? 255, options.vertexColor[2] ?? 255]
    : [255, 255, 255];

  const geometry = buildGeometry({
    shape,
    sizeX: options.sizeX ?? options.width ?? 1,
    sizeY: options.sizeY ?? options.depth,
    sizeZ: options.sizeZ ?? options.height ?? 1,
    diameter: options.diameter,
    radius: options.radius,
    sides: options.sides,
    segments: options.segments ?? options.points,
    rings: options.rings ?? options.bands,
    points: options.points,
    textureName: texSet.primaryName,
    vertexColor,
  });

  return writeMeshModel({
    options: { ...options, shape },
    texSet,
    geometry,
    includeCol: true,
  });
}

function listModels() {
  ensureModelsLayout();
  const root = getModelsRoot();
  const entries = [];
  for (const name of fs.readdirSync(root)) {
    if (!isModelFolderName(name)) continue;
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
  if (!isModelFolderName(id)) {
    throw new Error("invalid model id");
  }
  const dir = path.join(getModelsRoot(), id);
  if (!fs.existsSync(dir)) {
    throw new Error(`model not found: ${id}`);
  }
  const metaPath = path.join(dir, "meta.json");
  const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
  const files = resolveModelFileNames(dir, meta);
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
  const result = {
    id,
    meta: model.meta,
    dff: fs.readFileSync(model.files.dff),
    txd: fs.readFileSync(model.files.txd),
    col: null,
  };
  if (model.files.col && fs.existsSync(model.files.col)) {
    result.col = fs.readFileSync(model.files.col);
  }
  return result;
}

module.exports = {
  generateModel,
  writeMeshModel,
  parseColor,
  nextPowerOfTwo,
  listModels,
  getModel,
  deleteModel,
  readModelBuffers,
  DEFAULT_MODEL_ID,
};
