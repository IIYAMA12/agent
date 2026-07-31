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

  console.log("Server health:");
  const server = await mta.healthComplete(null, { side: "server" });
  console.log(JSON.stringify(server.result || server, null, 2));

  console.log("\nClient health:");
  const client = await mta.healthComplete(player, { side: "client" });
  console.log(JSON.stringify(client.result || client, null, 2));

  console.log("\nAll health:");
  const all = await mta.healthComplete(player, { side: "all" });
  console.log(JSON.stringify(all.result || all, null, 2));

  console.log("\nOK");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
