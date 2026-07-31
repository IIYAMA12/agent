function registerDebugFeatures(registry) {
  const { pollAsyncJob } = require("../lib/mta-async");

  async function runDebugList(mta, params) {
    const { player, pollOptions, ...options } = params;
    const side = options.side || "server";

    if (side === "server") {
      return mta.invoke("debugLogList", [player, options]);
    }

    return pollAsyncJob(
      () => mta.invoke("debugLogList", [player, options]),
      (id) => mta.invoke("debugLogResult", [id]),
      { timeoutMs: 20000, intervalMs: 250, ...(pollOptions || {}) }
    );
  }

  function needsEventHookPoll(action, side) {
    if (side === "server") {
      return false;
    }
    return action === "list" || action === "status" || action === "start" || action === "stop" || action === "clear";
  }

  async function runDebugEvents(mta, params) {
    const { player, pollOptions, action, ...options } = params;
    const resolvedAction = action || "list";
    const side = options.side || "server";
    const payload = { action: resolvedAction, ...options };

    if (!needsEventHookPoll(resolvedAction, side)) {
      return mta.invoke("debugEvents", [player, payload]);
    }

    return pollAsyncJob(
      () => mta.invoke("debugEvents", [player, payload]),
      (id) => mta.invoke("debugEventsResult", [id]),
      { timeoutMs: 20000, intervalMs: 250, ...(pollOptions || {}) }
    );
  }

  registry.register("debug.list", {
    description:
      "Fetch recent MTA debug messages (onDebugMessage server / onClientDebugMessage client). Last 500 entries with anti-dupe.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      side: { optional: true },
      minLevel: { optional: true },
      limit: { optional: true },
      sinceSeq: { optional: true },
      sinceTick: { optional: true },
      dedupe: { optional: true },
      pollOptions: { optional: true },
    },
    run: runDebugList,
  });

  registry.register("debug.events", {
    description:
      "On-demand MTA event tracing via addDebugHook (preEvent — fires once when an event is triggered). Start before reproducing a bug, list captured events, then stop. Filter with events: [\"onPlayerJoin\"]. Hooks are not installed until action=start.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      action: { optional: true },
      side: { optional: true },
      events: { optional: true },
      nameList: { optional: true },
      event: { optional: true },
      eventName: { optional: true },
      hookType: { optional: true },
      resource: { optional: true },
      limit: { optional: true },
      sinceSeq: { optional: true },
      sinceTick: { optional: true },
      dedupe: { optional: true },
      pollOptions: { optional: true },
    },
    run: runDebugEvents,
  });
}

module.exports = { registerDebugFeatures };
