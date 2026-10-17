const { pollAsyncJob } = require("../lib/mta-async");

function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = "BOUNDING_BAD_REQUEST";
  return error;
}

function unwrapPolled(polled) {
  if (polled && polled.result !== undefined) return polled.result;
  return polled;
}

function registerBoundingFeatures(registry) {
  registry.register("bounding.scan", {
    description:
      "Catalog stock getElementBoundingBox values for object, vehicle, and ped models. Client-only: each model is spawned locally and must stream in or it is recorded as failed. Writes data/bounding-defaults.json and does not replace a default already stored, so a later engineReplaceModel cannot poison the stock record. force:true rewrites defaults but still skips models this client has replaced via models.test. action start returns { id, status:\"pending\", scanned, total, ... }. Poll with { action:\"status\", id } until status is \"complete\" (a full catalog can take several minutes). action stop ends the job. Does not write the custom/modded record — use bounding.fetch after a model mod.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      action: { optional: true },
      id: { optional: true },
      types: { optional: true },
      elementType: { optional: true },
      batch: { optional: true },
      force: { optional: true },
    },
    async run(mta, params) {
      const { player, ...options } = params;
      const action = options.action || "start";
      if ((action === "status" || action === "stop") && !options.id) {
        throw badRequest(`id is required for bounding.scan ${action}`);
      }
      return mta.invoke("boundingScan", [player || null, options]);
    },
  });

  registry.register("bounding.get", {
    description:
      "Look up the stored bounding box for a model. Returns { default, custom, differsFromDefault } when elementType is object, vehicle, or ped. differsFromDefault is true only when both records exist and the raw min/max differ. Pass model (and optional elementType), or agentId / mtaHandle to resolve the element's model on the client. This does not call getElementBoundingBox and does not require the element to be streamed in. Use bounding.fetch for a live read after someone mods the model.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      model: { optional: true },
      elementType: { optional: true },
      agentId: { optional: true },
      id: { optional: true },
      mtaHandle: { optional: true },
    },
    async run(mta, params) {
      const { player, ...options } = params;
      const started = await mta.invoke("boundingGet", [player || null, options]);
      if (started && started.id && started.status === "pending") {
        const polled = await pollAsyncJob(
          async () => started,
          (requestId) => mta.invoke("boundingGetResult", [requestId]),
          { timeoutMs: 15000, intervalMs: 200 }
        );
        return unwrapPolled(polled);
      }
      return started;
    },
  });

  registry.register("bounding.fetch", {
    description:
      "Custom live getElementBoundingBox read. Client-only. An existing element (agentId, id, or mtaHandle) must already be streamed in; otherwise the result is { error:\"notStreamedIn\", default, custom } and the stock default record is left unchanged. A model id with no element spawns a temporary local element, waits until it streams in, then stores the box in data/bounding-custom.json only — it does not write defaults. Use this after models.test or any engineReplaceModel, because a modded model can change the box. Raw min/max are model-space, relative to the element.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      agentId: { optional: true },
      id: { optional: true },
      mtaHandle: { optional: true },
      model: { optional: true },
      elementType: { optional: true },
    },
    async run(mta, params) {
      const { player, ...options } = params;
      try {
        const polled = await pollAsyncJob(
          () => mta.invoke("boundingFetch", [player || null, options]),
          (requestId) => mta.invoke("boundingFetchResult", [requestId]),
          { timeoutMs: 20000, intervalMs: 200 }
        );
        return unwrapPolled(polled);
      } catch (error) {
        if (error && error.body && error.body.error === "notStreamedIn") {
          return error.body;
        }
        throw error;
      }
    },
  });

  registry.register("bounding.draw", {
    description:
      "Draw a bounding-box wireframe on the client. action start|stop|list. Target an agentId / mtaHandle, or set nearby:true (optional elementType, model, maxDistance, limit) for streamed elements near the player. Prefers a live getElementBoundingBox when the element is streamed in, otherwise the custom record, then the stock default. Drawing applies the editor half-center shift (min+max)*0.25 and uses dxDrawLine3D so the box stays visible when a corner leaves the screen. Verify with screen.capture. stop with no id clears every box.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      action: { optional: true },
      agentId: { optional: true },
      id: { optional: true },
      mtaHandle: { optional: true },
      model: { optional: true },
      elementType: { optional: true },
      type: { optional: true },
      nearby: { optional: true },
      maxDistance: { optional: true },
      limit: { optional: true },
      r: { optional: true },
      g: { optional: true },
      b: { optional: true },
      a: { optional: true },
    },
    async run(mta, params) {
      const { player, ...options } = params;
      const polled = await pollAsyncJob(
        () => mta.invoke("boundingDraw", [player || null, options]),
        (requestId) => mta.invoke("boundingDrawResult", [requestId]),
        { timeoutMs: 15000, intervalMs: 200 }
      );
      return unwrapPolled(polled);
    },
  });
}

module.exports = { registerBoundingFeatures };
