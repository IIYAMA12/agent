class PlayerRequiredError extends Error {
  constructor(playersOnline = []) {
    const details = Array.isArray(playersOnline) ? playersOnline : [];
    const names = details.map((entry) =>
      typeof entry === "string" ? entry : entry?.name
    ).filter(Boolean);
    super(
      names.length > 0
        ? `player or serial is required (${names.length} online: ${names.join(", ")})`
        : "player or serial is required (no players online)"
    );
    this.name = "PlayerRequiredError";
    this.status = 400;
    this.code = "PLAYER_REQUIRED";
    this.playersOnline = names;
    this.playerDetails = details;
    this.hint =
      "Set player or serial in the request body, AGENT_PLAYER_SERIAL / AGENT_PLAYER in .env, or session.defaultPlayerSerial / session.defaultPlayer in memory";
  }
}

function trim(value) {
  return typeof value === "string" ? value.trim() : "";
}

function isPlayerSerial(value) {
  const text = trim(value).toLowerCase();
  return text.length === 32 && /^[0-9a-f]+$/.test(text);
}

function pickSerial(explicitSerial, memory) {
  const serial =
    trim(explicitSerial) ||
    trim(process.env.AGENT_PLAYER_SERIAL) ||
    trim(memory?.get("session.defaultPlayerSerial"));
  return isPlayerSerial(serial) ? serial.toLowerCase() : null;
}

function pickName(explicitPlayer, memory) {
  return (
    trim(explicitPlayer) ||
    trim(process.env.AGENT_PLAYER) ||
    trim(memory?.get("session.defaultPlayer")) ||
    null
  );
}

async function resolvePlayerRef(mta, memory, explicitPlayer, explicitSerial) {
  const serial = pickSerial(explicitSerial, memory);
  if (serial) {
    return { player: null, serial };
  }

  const name = pickName(explicitPlayer, memory);
  if (name) {
    if (isPlayerSerial(name)) {
      return { player: null, serial: name.toLowerCase() };
    }
    return { player: name, serial: null };
  }

  // A failed getServerState (MTA down, auth error, etc.) propagates as-is
  // instead of being masked as "no players online". Only a successful state
  // with zero or multiple players yields PLAYER_REQUIRED.
  const state = await mta.invoke("getServerState", []);
  const details = state?.playerDetails || (state?.players || []).map((entry) =>
    typeof entry === "string" ? { name: entry } : entry
  );

  if (details.length === 1) {
    return {
      player: details[0].name,
      serial: details[0].serial || null,
    };
  }

  throw new PlayerRequiredError(details);
}

async function resolvePlayer(mta, memory, explicitPlayer, explicitSerial) {
  const ref = await resolvePlayerRef(mta, memory, explicitPlayer, explicitSerial);
  if (ref.serial) {
    const resolved = await mta.invoke("resolvePlayer", [null, { serial: ref.serial }]);
    return resolved?.name || resolved?.player?.name;
  }
  return ref.player;
}

function withPlayerOptions(playerRef, options = {}) {
  const next = { ...options };
  if (playerRef?.serial) {
    next.serial = playerRef.serial;
  }
  return next;
}

module.exports = {
  resolvePlayer,
  resolvePlayerRef,
  withPlayerOptions,
  PlayerRequiredError,
  isPlayerSerial,
};
