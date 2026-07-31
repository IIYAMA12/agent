function registerHealthFeatures(registry) {
  const { pollAsyncJob } = require("../lib/mta-async");

  async function runHealthGet(mta, params) {
    const { player, pollOptions, ...options } = params;
    const side = options.side || "server";

    if (side === "server") {
      return mta.invoke("healthGet", [player, options]);
    }

    return pollAsyncJob(
      () => mta.invoke("healthGet", [player, options]),
      (id) => mta.invoke("healthResult", [id]),
      { timeoutMs: 20000, intervalMs: 250, ...(pollOptions || {}) }
    );
  }

  registry.register("health.get", {
    description:
      "MTA process health: memory (getProcessMemoryStats), CPU % (Server info threads + Lua timing), network (getNetworkStats, summarized getNetworkUsageData), optional getPerformanceStats category, client-only isTransferBoxActive and dxGetStatus. Use side: server | client | all.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      side: { optional: true },
      networkUsage: { optional: true },
      networkUsageLimit: { optional: true },
      includeCpu: { optional: true },
      includeLuaCpu: { optional: true },
      luaCpuLimit: { optional: true },
      performanceCategory: { optional: true },
      performanceCategories: { optional: true },
      performanceOptions: { optional: true },
      performanceFilter: { optional: true },
      listPerformanceCategories: { optional: true },
      pollOptions: { optional: true },
    },
    run: runHealthGet,
  });
}

module.exports = { registerHealthFeatures };
