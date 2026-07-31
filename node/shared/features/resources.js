function registerResourceFeatures(registry) {
  registry.register("resources.search", {
    description:
      "Search MTA resources by name substring (fast alternative to getServerState). Returns name + state, sorted by relevance. Use before start/stop/restart to find the exact resource name.",
    params: {
      query: { optional: true },
      q: { optional: true },
      name: { optional: true },
      state: { optional: true },
      limit: { optional: true },
      exact: { optional: true },
    },
    run: (mta, params = {}) => mta.invoke("resourceSearch", [params]),
  });

  registry.register("resources.control", {
    description:
      "Start, stop, or restart an MTA resource by name. Prefer resources.search first when the exact name is unknown.",
    params: {
      action: { optional: false },
      resource: { optional: false },
    },
    run: (mta, params = {}) => {
      const action = params.action;
      const resource = params.resource;
      if (!action || !resource) {
        return Promise.reject(new Error("action and resource are required"));
      }

      const exportName =
        action === "start"
          ? "resourceStart"
          : action === "stop"
            ? "resourceStop"
            : action === "restart"
              ? "resourceRestart"
              : null;

      if (!exportName) {
        return Promise.reject(new Error('action must be "start", "stop", or "restart"'));
      }

      return mta.invoke(exportName, [resource]);
    },
  });
}

module.exports = { registerResourceFeatures };
