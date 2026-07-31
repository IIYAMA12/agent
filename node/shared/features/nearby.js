function registerNearbyFeatures(registry) {
  registry.register("nearby.closest", {
    description: "Closest elements near the player",
    params: {
      player: { required: true },
      type: { optional: true },
      limit: { optional: true },
      maxDistance: { optional: true },
    },
    run: (mta, params) => {
      const { player, ...options } = params;
      return mta.invokePlayer("findNearby", player, options);
    },
  });

  registry.register("areas.closest", {
    description: "Closest map area to the player",
    params: {
      player: { required: true },
      category: { optional: true },
      region: { optional: true },
      search: { optional: true },
      locationId: { optional: true },
    },
    run: (mta, params) => {
      const { player, ...options } = params;
      return mta.invokePlayer("findClosestArea", player, options);
    },
  });
}

module.exports = { registerNearbyFeatures };
