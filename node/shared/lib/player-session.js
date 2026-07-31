const {
  resolvePlayerRef,
  withPlayerOptions,
} = require("./resolve-player");

async function getOnlinePlayers(mta) {
  try {
    const state = await mta.getServerState();
    return state?.playerDetails || (state?.players || []).map((name) => ({ name }));
  } catch {
    return [];
  }
}

async function getDefaultPlayerHint(ctx) {
  if (process.env.AGENT_PLAYER_SERIAL) return process.env.AGENT_PLAYER_SERIAL;
  if (process.env.AGENT_PLAYER) return process.env.AGENT_PLAYER;
  const sessionSerial = ctx.memory.get("session.defaultPlayerSerial");
  if (sessionSerial) return sessionSerial;
  const session = ctx.memory.get("session.defaultPlayer");
  if (session) return session;
  const players = await getOnlinePlayers(ctx.mta);
  return players.length === 1 ? players[0].name || players[0] : null;
}

async function resolveSessionPlayer(ctx, explicitPlayer, explicitSerial) {
  const ref = await resolvePlayerRef(ctx.mta, ctx.memory, explicitPlayer, explicitSerial);
  if (ref.serial) {
    ctx.memory.set("session.defaultPlayerSerial", ref.serial);
  }
  if (ref.player) {
    ctx.memory.set("session.defaultPlayer", ref.player);
  }
  return ref;
}

async function withPlayer(ctx, explicitPlayer, handler, explicitSerial) {
  const ref = await resolveSessionPlayer(ctx, explicitPlayer, explicitSerial);
  return handler(ref.player, ref.serial, ref);
}

function applyPlayerRef(params = {}, ref) {
  const { player, serial, ...options } = params;
  return {
    player: ref?.player || player || null,
    ...withPlayerOptions(ref, options),
  };
}

async function withPlayerFromBody(ctx, body, handler) {
  const payload = body || {};
  return withPlayer(ctx, payload.player, handler, payload.serial);
}

module.exports = {
  getOnlinePlayers,
  getDefaultPlayerHint,
  resolveSessionPlayer,
  withPlayer,
  withPlayerFromBody,
  applyPlayerRef,
};
