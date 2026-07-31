const { createMtaClient } = require("../shared/mta-client");

async function main() {
  const mta = createMtaClient();
  const player = process.env.AGENT_PLAYER || "IIYAMA";

  console.log("1. status (server, should be inactive)");
  const status = await mta.debugEventsComplete(null, { action: "status", side: "server" });
  console.log(JSON.stringify(status.result || status, null, 2));

  console.log("\n2. start (server)");
  const started = await mta.debugEventsComplete(null, {
    action: "start",
    side: "server",
    events: ["onPlayerJoin"],
  });
  console.log(JSON.stringify(started.result || started, null, 2));

  console.log("\n3. stop (server)");
  const stopped = await mta.debugEventsComplete(null, { action: "stop", side: "server" });
  console.log(JSON.stringify(stopped.result || stopped, null, 2));

  console.log("\n4. client start + list + stop");
  const clientStarted = await mta.debugEventsComplete(player, {
    action: "start",
    side: "client",
  });
  console.log("started:", JSON.stringify(clientStarted.result || clientStarted, null, 2));

  const listed = await mta.debugEventsComplete(player, {
    action: "list",
    side: "client",
    limit: 5,
  });
  console.log("list count:", listed.result?.count ?? listed.result?.entries?.length);

  const clientStopped = await mta.debugEventsComplete(player, { action: "stop", side: "client" });
  console.log("stopped:", JSON.stringify(clientStopped.result || clientStopped, null, 2));

  console.log("\nOK");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
