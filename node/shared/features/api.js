const { sync, lookup } = require("../lib/mta-api/sync");

function flag(value) {
  return value === true || value === "true" || value === 1 || value === "1";
}

function registerApiFeatures(registry) {
  registry.register("api.sync", {
    description:
      "Fetch the MTA Lua annotations git repo and rebuild the local signature index. Skips the rebuild when the commit is unchanged. force rebuilds anyway.",
    requiresPlayer: false,
    params: {
      force: { optional: true },
    },
    run: (_mta, params = {}) => sync({ force: flag(params.force) }),
  });

  registry.register("api.lookup", {
    description:
      "Look up an MTA function or event from the annotations index. name is required. side filters client, server, or shared. A client or server filter also returns shared overloads. Syncs from GitLab once if the index is missing.",
    requiresPlayer: false,
    params: {
      name: { required: true },
      side: { optional: true },
      limit: { optional: true },
    },
    run: (_mta, params = {}) =>
      lookup({
        name: params.name,
        side: params.side,
        limit: params.limit,
      }),
  });
}

module.exports = { registerApiFeatures };
