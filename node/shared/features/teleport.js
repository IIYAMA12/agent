const { getLookTarget } = require("./look");

function registerTeleportFeatures(registry) {
  registry.register("teleport.player", {
    description: "Teleport to another online player (use same name for self-teleport)",
    params: {
      player: { required: true },
      targetPlayer: { required: true },
      offsetDistance: { optional: true },
    },
    run: async (mta, params) => {
      const { player, targetPlayer, toPlayer, ...options } = params;
      const target = targetPlayer || toPlayer;
      if (!target) {
        const error = new Error("targetPlayer is required");
        error.status = 400;
        throw error;
      }

      if (target === player) {
        options.allowSelf = true;
      }

      return mta.invoke("teleportToPlayer", [player, target, options]);
    },
  });

  registry.register("teleport.area", {
    description: "Teleport to a map area by id, category, region, or search (e.g. pizza, airport)",
    params: {
      player: { required: true },
      locationId: { optional: true },
      category: { optional: true },
      region: { optional: true },
      search: { optional: true },
    },
    run: async (mta, params) => {
      const { player, locationId, airportId, ...options } = params;
      return mta.invoke("teleportToArea", [
        player,
        {
          ...options,
          locationId: locationId || airportId,
        },
      ]);
    },
  });

  registry.register("teleport.element", {
    description: "Teleport to closest matching element (vehicle, ped, etc.)",
    params: {
      player: { required: true },
      type: { optional: true },
      model: { optional: true },
      search: { optional: true },
      maxDistance: { optional: true },
    },
    run: async (mta, params) => {
      const { player, type, elementType, search, name, ...options } = params;
      return mta.invoke("teleportToElement", [
        player,
        {
          ...options,
          type: type || elementType,
          search: search || name,
        },
      ]);
    },
  });

  registry.register("teleport.lookTarget", {
    description: "Teleport beside whatever the player is currently looking at",
    params: { player: { required: true }, type: { optional: true } },
    run: async (mta, params) => {
      const look = await getLookTarget(mta, params);
      const target = look.lookingAt;
      if (!target?.position) {
        const error = new Error("Nothing in view to teleport to");
        error.status = 404;
        error.body = look;
        throw error;
      }

      const pos = target.position;
      const offset = params.offsetDistance || 2.5;
      return mta.invoke("teleportToPosition", [
        params.player,
        pos.x + offset,
        pos.y,
        pos.z + 0.3,
        {
          interior: target.interior,
          dimension: target.dimension,
          serial: params.serial,
        },
      ]);
    },
  });
}

module.exports = { registerTeleportFeatures };
