function registerCameraFeatures(registry) {
  const { pollAsyncJob } = require("../lib/mta-async");
  const playerParams = {
    player: { optional: true },
    serial: { optional: true },
  };

  function run(exportName) {
    return (mta, params) => {
      const { player, ...options } = params;
      return mta.invoke(exportName, [player, options]);
    };
  }

  registry.register("camera.fade", {
    description:
      "Fade the player camera in or out (fadeCamera). Server fades must alternate: fade out, then fade in. fadeIn true restores the view; false fades to red, green, and blue.",
    params: {
      ...playerParams,
      fadeIn: { required: true },
      time: { optional: true },
      red: { optional: true },
      green: { optional: true },
      blue: { optional: true },
    },
    run: run("cameraFade"),
  });

  registry.register("camera.interior.get", {
    description: "Read the interior the player camera is rendering (getCameraInterior).",
    params: { ...playerParams },
    run: run("cameraGetInterior"),
  });

  registry.register("camera.interior.set", {
    description:
      "Set the interior the player camera renders (setCameraInterior). Use with camera.matrix.set when the fixed view is in another interior.",
    params: {
      ...playerParams,
      interior: { required: true },
    },
    run: run("cameraSetInterior"),
  });

  registry.register("camera.matrix.get", {
    description:
      "Read the live player camera matrix from the client (getCameraMatrix): position, look-at, roll, and fov. The server copy is only synced every few seconds.",
    params: { ...playerParams },
    run: async (mta, params) => {
      const { player, pollOptions, ...options } = params;
      const done = await pollAsyncJob(
        () => mta.invoke("cameraGetMatrix", [player, options]),
        (id) => mta.invoke("cameraGetMatrixResult", [id]),
        { timeoutMs: 8000, intervalMs: 100, ...(pollOptions || {}) }
      );
      if (done && done.status === "complete" && done.result) {
        return done.result;
      }
      return done;
    },
  });

  registry.register("camera.matrix.set", {
    description:
      "Fix the player camera at x, y, z looking toward lookAtX, lookAtY, lookAtZ (setCameraMatrix). Detaches the camera until camera.target.set restores it. Optional interior also calls setCameraInterior.",
    params: {
      ...playerParams,
      x: { required: true },
      y: { required: true },
      z: { required: true },
      lookAtX: { optional: true },
      lookAtY: { optional: true },
      lookAtZ: { optional: true },
      roll: { optional: true },
      fov: { optional: true },
      interior: { optional: true },
    },
    run: run("cameraSetMatrix"),
  });

  registry.register("camera.target.get", {
    description:
      "Read the element the player camera is following (getCameraTarget). fixed is true when the camera was placed with setCameraMatrix.",
    params: { ...playerParams },
    run: run("cameraGetTarget"),
  });

  registry.register("camera.target.set", {
    description:
      "Point the player camera at a player, ped, or vehicle (setCameraTarget). Omit the target or pass reset true to follow the player again.",
    params: {
      ...playerParams,
      reset: { optional: true },
      agentId: { optional: true },
      target: { optional: true },
      targetPlayer: { optional: true },
    },
    run: run("cameraSetTarget"),
  });
}

module.exports = { registerCameraFeatures };
