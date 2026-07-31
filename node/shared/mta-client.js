const { trim } = require("./credentials");
const { pollAsyncJob } = require("./lib/mta-async");
const { pollUntilComplete } = require("./lib/poll");

class MtaError extends Error {
  constructor(message, status = 500, body = null, code = null, hint = null) {
    super(message);
    this.name = "MtaError";
    this.status = status;
    this.body = body;
    this.code = code;
    this.hint = hint;
  }
}

class MtaClient {
  constructor(options = {}) {
    this.host = trim(options.host) || "127.0.0.1";
    this.port = Number(options.port || 22005);
    this.user = trim(options.user);
    this.password = trim(options.password);
    this.resource = trim(options.resource) || "agent";
  }

  ensureAuth() {
    if (!this.user || !this.password) {
      throw new MtaError(
        "MTA credentials missing — set MTA_USER and MTA_PASS in node/.env",
        401,
        null,
        "AUTH_MISSING"
      );
    }
  }

  get baseUrl() {
    return `http://${this.host}:${this.port}/${this.resource}`;
  }

  get authHeader() {
    const token = Buffer.from(`${this.user}:${this.password}`).toString("base64");
    return `Basic ${token}`;
  }

  async call(functionName, args = []) {
    this.ensureAuth();
    const response = await fetch(`${this.baseUrl}/call/${functionName}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: this.authHeader,
      },
      body: JSON.stringify(args),
    });

    const text = await response.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }

    if (!response.ok) {
      throw new MtaError(`MTA call failed (${response.status})`, response.status, data);
    }

    if (Array.isArray(data)) {
      return data[0];
    }

    return data;
  }

  async invoke(functionName, args = []) {
    const data = await this.call(functionName, args);

    if (typeof data === "string") {
      if (data.toLowerCase().includes("not found")) {
        throw new MtaError(
          `Export "${functionName}" not available — run "restart agent" on the MTA server`,
          503,
          data,
          "EXPORT_MISSING",
          "restart agent"
        );
      }
      throw new MtaError(data, 500, data, "MTA_ERROR");
    }

    if (data && typeof data === "object" && data.ok === false) {
      throw new MtaError(data.error || "MTA call failed", 400, data, "MTA_CALL_FAILED");
    }

    if (data && typeof data === "object" && data.ok === true) {
      return data.result !== undefined ? data.result : data;
    }

    return data;
  }

  invokePlayer(exportName, player, options = {}) {
    return this.invoke(exportName, [player, options]);
  }

  async pollExport(startExport, resultExport, body, pollOptions = {}) {
    const { player, ...options } = body;
    return pollAsyncJob(
      () => this.invoke(startExport, [player, options]),
      (id) => this.invoke(resultExport, [id]),
      pollOptions
    );
  }

  ping() {
    return this.invoke("ping", []);
  }

  getServerState() {
    return this.invoke("getServerState", []);
  }

  resourceSearch(options = {}) {
    return this.invoke("resourceSearch", [options]);
  }

  resourceStart(resource) {
    return this.invoke("resourceStart", [resource]);
  }

  resourceStop(resource) {
    return this.invoke("resourceStop", [resource]);
  }

  resourceRestart(resource) {
    return this.invoke("resourceRestart", [resource]);
  }

  resourceControl(action, resource) {
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
    return this.invoke(exportName, [resource]);
  }

  resolvePlayer(identifier, options = {}) {
    return this.invoke("resolvePlayer", [identifier, options]);
  }

  eval(code) {
    return this.invoke("eval", [code]);
  }

  evalClient(code, player, options = {}) {
    return this.invoke("evalClient", [code, player, options]);
  }

  evalClientResult(id) {
    return this.invoke("evalClientResult", [id]);
  }

  evalClientComplete(code, player, options = {}, pollOptions = {}) {
    return pollAsyncJob(
      () => this.evalClient(code, player, options),
      (id) => this.evalClientResult(id),
      pollOptions
    );
  }

  findNearby(options = {}) {
    const { player, ...queryOptions } = options;
    return this.invoke("findNearby", [player, queryOptions]);
  }

  findVisible(body = {}) {
    const { player, ...options } = body;
    return this.invoke("findVisible", [player, options]);
  }

  findVisibleResult(id) {
    return this.invoke("findVisibleResult", [id]);
  }

  visible(body = {}, pollOptions = {}) {
    return this.pollExport("findVisible", "findVisibleResult", body, pollOptions);
  }

  findLookTarget(body = {}) {
    const { player, ...options } = body;
    return this.invoke("findLookTarget", [player, options]);
  }

  findLookTargetResult(id) {
    return this.invoke("findLookTargetResult", [id]);
  }

  async lookTarget(body = {}, pollOptions = {}) {
    const polled = await this.pollExport("findLookTarget", "findLookTargetResult", body, pollOptions);
    // pollUntilComplete wraps the semantic payload under `.result` when invoke()
    // has already unwrapped the server envelope; fall back to the object itself.
    const result = polled?.result ?? polled ?? {};
    return {
      player: body.player,
      lookingAt: result.lookingAt || null,
      method: result.method,
      camera: result.camera,
      stats: result.stats,
    };
  }

  elementResult(id) {
    return this.invoke("elementResult", [id]);
  }

  // Client-side element ops resolve asynchronously (the MTA HTTP export returns
  // { status: "pending", id } and the client reply arrives later). Server-side
  // ops respond inline (no "pending" status), so only poll when told to.
  async elementOp(startExport, args, pollOptions = {}) {
    const started = await this.invoke(startExport, args);
    if (!started || typeof started !== "object" || started.status !== "pending" || !started.id) {
      return started;
    }

    const polled = await pollUntilComplete(() => this.elementResult(started.id), {
      timeoutMs: 20000,
      intervalMs: 250,
      ...pollOptions,
    });
    return polled && polled.result !== undefined ? polled.result : polled;
  }

  elementTrack(player, options = {}) {
    return this.elementOp("elementTrack", [player, options]);
  }

  elementGet(id, options = {}) {
    return this.elementOp("elementGet", [id, options]);
  }

  elementList(options = {}) {
    return this.invoke("elementList", [options]);
  }

  elementRelease(id, options = {}) {
    return this.elementOp("elementRelease", [id, options]);
  }

  elementModify(id, options = {}) {
    return this.elementOp("elementModify", [id, options]);
  }

  elementResolve(id, options = {}) {
    return this.elementOp("elementResolve", [id, options]);
  }

  elementWalk(options = {}) {
    return this.elementOp("elementWalk", [options]);
  }

  guiScan(player, options = {}) {
    return this.invoke("guiScan", [player, options]);
  }

  guiScanResult(id) {
    return this.invoke("guiScanResult", [id]);
  }

  guiScanComplete(player, options = {}, pollOptions = {}) {
    const { pollAsyncJob } = require("./lib/mta-async");
    return pollAsyncJob(
      () => this.guiScan(player, options),
      (id) => this.guiScanResult(id),
      { timeoutMs: 20000, intervalMs: 250, ...pollOptions }
    );
  }

  debugLogList(player, options = {}) {
    return this.invoke("debugLogList", [player, options]);
  }

  debugLogResult(id) {
    return this.invoke("debugLogResult", [id]);
  }

  debugLogComplete(player, options = {}, pollOptions = {}) {
    const { pollAsyncJob } = require("./lib/mta-async");
    const side = options.side || "server";

    if (side === "server") {
      return this.debugLogList(player, options);
    }

    return pollAsyncJob(
      () => this.debugLogList(player, options),
      (id) => this.debugLogResult(id),
      { timeoutMs: 20000, intervalMs: 250, ...pollOptions }
    );
  }

  debugEvents(player, options = {}) {
    return this.invoke("debugEvents", [player, options]);
  }

  debugEventsResult(id) {
    return this.invoke("debugEventsResult", [id]);
  }

  debugEventsComplete(player, options = {}, pollOptions = {}) {
    const { pollAsyncJob } = require("./lib/mta-async");
    const action = options.action || "list";
    const side = options.side || "server";
    const needsPoll =
      side !== "server" &&
      (action === "list" ||
        action === "status" ||
        action === "start" ||
        action === "stop" ||
        action === "clear");

    if (!needsPoll) {
      return this.debugEvents(player, options);
    }

    return pollAsyncJob(
      () => this.debugEvents(player, options),
      (id) => this.debugEventsResult(id),
      { timeoutMs: 20000, intervalMs: 250, ...pollOptions }
    );
  }

  healthGet(player, options = {}) {
    return this.invoke("healthGet", [player, options]);
  }

  healthResult(id) {
    return this.invoke("healthResult", [id]);
  }

  healthComplete(player, options = {}, pollOptions = {}) {
    const { pollAsyncJob } = require("./lib/mta-async");
    const side = options.side || "server";

    if (side === "server") {
      return this.healthGet(player, options);
    }

    return pollAsyncJob(
      () => this.healthGet(player, options),
      (id) => this.healthResult(id),
      { timeoutMs: 20000, intervalMs: 250, ...pollOptions }
    );
  }

  teleportToClosestAirport(player, options = {}) {
    return this.invoke("teleportToClosestAirport", [player, options]);
  }

  getAreaMap() {
    return this.invoke("getAreaMap", []);
  }

  listAreas(options = {}) {
    return this.invoke("listAreas", [options]);
  }

  findClosestArea(player, options = {}) {
    return this.invoke("findClosestArea", [player, options]);
  }

  teleportToArea(player, options = {}) {
    return this.invoke("teleportToArea", [player, options]);
  }

  teleportToElement(player, options = {}) {
    return this.invoke("teleportToElement", [player, options]);
  }

  teleportToPlayer(player, targetPlayer, options = {}) {
    return this.invoke("teleportToPlayer", [player, targetPlayer, options]);
  }

  teleportToPosition(player, x, y, z, options = {}) {
    return this.invoke("teleportToPosition", [player, x, y, z, options]);
  }
}

module.exports = { MtaClient, MtaError };
