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
      "Start, stop, restart, or refresh an MTA resource. Prefer resources.search first when the exact name is unknown. For refresh: omit resource to scan for new/errored resources; set refreshAll=true to check file changes (can lag); pass resource to limit refresh to one resource.",
    params: {
      action: { optional: false },
      resource: { optional: true },
      refreshAll: { optional: true },
    },
    run: (mta, params = {}) => {
      const action = params.action;
      if (!action) {
        return Promise.reject(new Error("action is required"));
      }

      if (action === "refresh") {
        return mta.resourceRefresh({
          resource: params.resource,
          refreshAll: params.refreshAll === true,
        });
      }

      const resource = params.resource;
      if (!resource) {
        return Promise.reject(new Error("resource is required"));
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
        return Promise.reject(
          new Error('action must be "start", "stop", "restart", or "refresh"')
        );
      }

      return mta.invoke(exportName, [resource]);
    },
  });
}

module.exports = { registerResourceFeatures };
