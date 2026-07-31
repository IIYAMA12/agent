async function getLookTarget(mta, params) {
  const { player, type = "vehicle", maxDistance = 300, ...options } = params;
  return mta.lookTarget({
    player,
    type,
    maxDistance,
    ...options,
  });
}

function registerLookFeatures(registry) {
  registry.register("look.target", {
    description: "What the player is currently looking at (auto-polls async result)",
    params: { player: { optional: true }, serial: { optional: true }, type: { optional: true }, maxDistance: { optional: true }, autoTrack: { optional: true } },
    run: getLookTarget,
  });
}

module.exports = { registerLookFeatures, getLookTarget };
