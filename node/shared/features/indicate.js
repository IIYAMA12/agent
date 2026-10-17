function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.code = "INDICATE_BAD_REQUEST";
  return error;
}

function isAll(value) {
  return value === true || value === 1 || value === "1" || value === "true";
}

function unwrapPolled(polled) {
  if (polled && polled.result !== undefined) return polled.result;
  return polled;
}

async function runIndicate(mta, params, action) {
  const { player, pollOptions, feature: _feature, action: _action, ...options } = params;
  options.action = action;
  if (action === "clear" && !isAll(options.all) && (options.id === undefined || options.id === "")) {
    throw badRequest("id or all is required");
  }
  const polled = await mta.indicateComplete(player, options, pollOptions || {});
  return unwrapPolled(polled);
}

function registerIndicateFeatures(registry) {
  registry.register("indicate.set", {
    description:
      "Draw a virtual look cue or distance marker on the client. No world elements are created (no createMarker). kind: look (default; on-screen bracket or screen-edge arrow, plus a 3D ring when mode includes 3d), marker (3D ring and post), measure (3D line between two points, labeled with the segment length). mode: 2d, 3d, or both (look defaults to both; marker and measure default to 3d). Distance text is drawn whenever the point is on screen. Position is x, y, z or agentId (follows a tracked element). A measure end is toX, toY, toZ or toAgentId. replace:true clears existing cues first. timeout is seconds and defaults to 15, so a set can be fire-and-forget; timeout 0 or ttlMs 0 keeps the cue until indicate.clear. ttlMs is milliseconds and wins when both are set. items may be a JSON array string for a batch. indicate.list returns the same distances, onScreen, screen pixels, and remaining ttlMs.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      id: { optional: true },
      kind: { optional: true },
      mode: { optional: true },
      x: { optional: true },
      y: { optional: true },
      z: { optional: true },
      agentId: { optional: true },
      toX: { optional: true },
      toY: { optional: true },
      toZ: { optional: true },
      toAgentId: { optional: true },
      label: { optional: true },
      color: { optional: true },
      size: { optional: true },
      showDistance: { optional: true },
      timeout: { optional: true },
      ttlMs: { optional: true },
      replace: { optional: true },
      items: { optional: true },
    },
    run: (mta, params) => runIndicate(mta, params, "set"),
  });

  registry.register("indicate.clear", {
    description:
      "Remove virtual indications. Pass id to remove one, or all:true to remove every cue. Does not delete world elements.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      id: { optional: true },
      all: { optional: true },
    },
    run: (mta, params) => runIndicate(mta, params, "clear"),
  });

  registry.register("indicate.list", {
    description:
      "List virtual indications with live distance in meters, onScreen, and screen pixel position. Distances match the labels drawn in game. Measure entries report the segment length as distance and the distance from the player to the midpoint as playerDistance.",
    params: {
      player: { optional: true },
      serial: { optional: true },
    },
    run: (mta, params) => runIndicate(mta, params, "list"),
  });
}

module.exports = { registerIndicateFeatures };
