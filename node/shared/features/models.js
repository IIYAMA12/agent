"use strict";

const zlib = require("zlib");
const { httpError } = require("../lib/http-error");
const { pollAsyncJob } = require("../lib/mta-async");
const {
  generateModel,
  listModels,
  getModel,
  deleteModel,
  readModelBuffers,
  listImportFiles,
  ensureModelsLayout,
  DEFAULT_MODEL_ID,
} = require("../models");

function toBase64Gzip(buf) {
  return zlib.gzipSync(buf).toString("base64");
}

function registerModelFeatures(registry) {
  registry.register("models.generate", {
    description:
      "Generate a simple DFF/TXD/COL model (box/plane/prism) with optional DXT1 texture. Drop PNG/JPG in models/import/ and pass textureFile, or use texturePath / solid color.",
    params: {
      shape: { optional: true },
      sizeX: { optional: true },
      sizeY: { optional: true },
      sizeZ: { optional: true },
      width: { optional: true },
      depth: { optional: true },
      height: { optional: true },
      radius: { optional: true },
      sides: { optional: true },
      color: { optional: true },
      textureFile: { optional: true },
      texturePath: { optional: true },
      textureSize: { optional: true },
      compression: { optional: true },
      modelId: { optional: true },
      name: { optional: true },
      clamp: { optional: true },
    },
    run: async (_mta, params) => {
      ensureModelsLayout();
      try {
        return generateModel(params || {});
      } catch (error) {
        throw httpError(error.message || String(error), { status: 400, code: "MODEL_GENERATE_FAILED" });
      }
    },
  });

  registry.register("models.import.list", {
    description: "List PNG/JPG files in models/import/ drop folder (use names as textureFile for models.generate)",
    params: { recursive: { optional: true } },
    run: async (_mta, params) => listImportFiles({ recursive: params.recursive !== false }),
  });

  registry.register("models.list", {
    description: "List generated model builds under models/<uuid>/",
    params: {},
    run: async () => ({ models: listModels() }),
  });

  registry.register("models.get", {
    description: "Get meta and file sizes for a generated model by UUID",
    params: { id: { required: true } },
    run: async (_mta, params) => {
      if (!params.id) throw httpError("id is required", { status: 400 });
      try {
        return getModel(String(params.id));
      } catch (error) {
        throw httpError(error.message || String(error), { status: 404, code: "MODEL_NOT_FOUND" });
      }
    },
  });

  registry.register("models.delete", {
    description: "Delete a generated model UUID folder",
    params: { id: { required: true } },
    run: async (_mta, params) => {
      if (!params.id) throw httpError("id is required", { status: 400 });
      try {
        return deleteModel(String(params.id));
      } catch (error) {
        throw httpError(error.message || String(error), { status: 404, code: "MODEL_NOT_FOUND" });
      }
    },
  });

  registry.register("models.test", {
    description:
      "Apply a generated model replace in-game (engineLoad/Replace) and spawn a preview object near the player",
    params: {
      id: { required: true },
      player: { optional: true },
      serial: { optional: true },
      modelId: { optional: true },
      offsetDistance: { optional: true },
      offsetZ: { optional: true },
    },
    run: async (mta, params) => {
      if (!params.id) throw httpError("id is required", { status: 400 });
      let buffers;
      try {
        buffers = readModelBuffers(String(params.id));
      } catch (error) {
        throw httpError(error.message || String(error), { status: 404, code: "MODEL_NOT_FOUND" });
      }

      const modelId = Number(params.modelId) || buffers.meta.modelId || DEFAULT_MODEL_ID;
      const payload = {
        id: buffers.id,
        modelId,
        dff: toBase64Gzip(buffers.dff),
        txd: toBase64Gzip(buffers.txd),
        col: toBase64Gzip(buffers.col),
        compressed: "gzip",
        encoding: "base64",
        offsetDistance: params.offsetDistance != null ? Number(params.offsetDistance) : 3,
        offsetZ: params.offsetZ != null ? Number(params.offsetZ) : 0,
        serial: params.serial,
      };

      return pollAsyncJob(
        () => mta.invoke("modelReplaceTest", [params.player || null, payload]),
        (jobId) => mta.invoke("modelReplaceTestResult", [jobId]),
        { timeoutMs: 30000, intervalMs: 250 }
      );
    },
  });

  registry.register("models.restore", {
    description: "Restore stock model and destroy the in-game preview from models.test",
    params: {
      player: { optional: true },
      serial: { optional: true },
      modelId: { optional: true },
    },
    run: async (mta, params) => {
      const payload = {
        modelId: params.modelId != null ? Number(params.modelId) : undefined,
        serial: params.serial,
      };
      return pollAsyncJob(
        () => mta.invoke("modelRestore", [params.player || null, payload]),
        (jobId) => mta.invoke("modelReplaceTestResult", [jobId]),
        { timeoutMs: 15000, intervalMs: 250 }
      );
    },
  });
}

module.exports = { registerModelFeatures };
