function registerGuiFeatures(registry) {
  const { pollAsyncJob } = require("../lib/mta-async");

  async function runGuiScan(mta, params) {
    const { player, ...options } = params;
    return pollAsyncJob(
      () => mta.invoke("guiScan", [player, options]),
      (id) => mta.invoke("guiScanResult", [id]),
      { timeoutMs: 20000, intervalMs: 250 }
    );
  }

  registry.register("gui.scan", {
    description:
      "Scan client GUI elements (open windows, widget trees via getElementChildren). Use to understand what the player has open.",
    params: {
      player: { optional: true },
      windowTitle: { optional: true },
      title: { optional: true },
      search: { optional: true },
      openOnly: { optional: true },
      visibleOnly: { optional: true },
      maxDepth: { optional: true },
      maxNodes: { optional: true },
      flat: { optional: true },
      trees: { optional: true },
      autoTrack: { optional: true },
      includeAllElements: { optional: true },
    },
    run: runGuiScan,
  });

  registry.register("gui.windows", {
    description: "List open/visible GUI windows on the client (lightweight gui.scan)",
    params: {
      player: { optional: true },
      windowTitle: { optional: true },
      openOnly: { optional: true },
    },
    run: (mta, params) => {
      const { player, windowTitle, openOnly } = params;
      return runGuiScan(mta, {
        player,
        windowTitle,
        openOnly: openOnly !== false,
        trees: false,
        includeAllElements: false,
      });
    },
  });
}

module.exports = { registerGuiFeatures };
