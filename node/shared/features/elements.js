function registerElementFeatures(registry) {
  registry.register("elements.track", {
    description:
      "Register an element in the agent registry (by mtaHandle or nearest match). Use parentMtaHandle to resolve under a walked map/dynamic root.",
    params: {
      player: { optional: true },
      mtaHandle: { optional: true },
      parentMtaHandle: { optional: true },
      parentElementType: { optional: true },
      type: { optional: true },
      label: { optional: true },
      side: { optional: true },
    },
    run: (mta, params) => mta.elementTrack(params.player, params),
  });

  registry.register("elements.get", {
    description: "Get a tracked element entry by agent id",
    params: {
      id: { required: true },
      player: { optional: true },
      refresh: { optional: true },
    },
    run: (mta, params) =>
      mta.elementGet(params.id, { player: params.player, refresh: params.refresh }),
  });

  registry.register("elements.list", {
    description: "List tracked elements (optionally sync client registry shadows)",
    params: {
      player: { optional: true },
      side: { optional: true },
      elementType: { optional: true },
      localOnly: { optional: true },
      syncClient: { optional: true },
    },
    run: (mta, params) => mta.invoke("elementList", [params]),
  });

  registry.register("elements.release", {
    description: "Remove an element from the registry",
    params: {
      id: { required: true },
      player: { optional: true },
    },
    run: (mta, params) => mta.elementRelease(params.id, { player: params.player }),
  });

  registry.register("elements.modify", {
    description: "Modify tracked element properties (health, position, alpha, etc.)",
    params: {
      id: { required: true },
      player: { optional: true },
      set: { optional: true },
    },
    run: (mta, params) =>
      mta.elementModify(params.id, { player: params.player, set: params.set || params }),
  });

  registry.register("elements.resolve", {
    description: "Resolve agent id to scope and props without modifying",
    params: {
      id: { required: true },
      player: { optional: true },
    },
    run: (mta, params) => mta.elementResolve(params.id, { player: params.player }),
  });

  registry.register("elements.walk", {
    description:
      "Walk the MTA element tree. mode resourceTops: per-resource resourceRoot + dynamicElementRoot + mapRoots (server). autoTrack registers roots as agentIds; autoTrackChildren only with listMapChildren (capped). Large maps stay summary-only.",
    params: {
      player: { optional: true },
      mode: { optional: true },
      resourceName: { optional: true },
      query: { optional: true },
      q: { optional: true },
      state: { optional: true },
      limit: { optional: true },
      runningOnly: { optional: true },
      listMapChildren: { optional: true },
      mapChildLimit: { optional: true },
      autoTrack: { optional: true },
      autoTrackChildren: { optional: true },
      autoTrackChildLimit: { optional: true },
      maxDepth: { optional: true },
      maxNodes: { optional: true },
      flat: { optional: true },
      resourcesOnly: { optional: true },
      side: { optional: true },
    },
    run: (mta, params) => mta.elementWalk(params),
  });
}

module.exports = { registerElementFeatures };
