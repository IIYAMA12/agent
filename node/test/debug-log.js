require("../shared/load-env").loadEnv();
const { MtaClient } = require("../shared/mta-client");

async function main() {
  const mta = new MtaClient({
    host: process.env.MTA_HOST,
    port: process.env.MTA_PORT,
    user: process.env.MTA_USER,
    password: process.env.MTA_PASS,
    resource: process.env.MTA_RESOURCE,
  });

  const player = process.argv[2] || "IIYAMA";

  try {
    await mta.eval('outputDebugString("agent test error", 1)');
    await mta.eval('outputDebugString("agent test error", 1)');
    await mta.eval('outputDebugString("agent test error", 1)');
  } catch (error) {
    console.log("eval note:", error.message);
  }

  const server = await mta.debugLogList(null, { side: "server", limit: 10 });
  console.log("server:", JSON.stringify(server, null, 2));

  try {
    const client = await mta.debugLogComplete(player, { side: "client", limit: 10 });
    console.log("client:", JSON.stringify(client, null, 2));
  } catch (error) {
    console.log("client fetch:", error.message);
    if (error.body) console.log(JSON.stringify(error.body, null, 2));
  }

  try {
    const all = await mta.debugLogComplete(player, { side: "all", limit: 10 });
    console.log("all:", JSON.stringify(all, null, 2));
  } catch (error) {
    console.log("all fetch:", error.message);
    if (error.body) console.log(JSON.stringify(error.body, null, 2));
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
