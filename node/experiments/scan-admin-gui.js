require("../shared/load-env").loadEnv();
const { MtaClient } = require("../shared/mta-client");

async function main() {
  const player = process.argv[2] || "IIYAMA";
  const windowTitle = process.argv[3] || process.env.GUI_SCAN_TITLE || undefined;
  const mta = new MtaClient({
    host: process.env.MTA_HOST,
    port: process.env.MTA_PORT,
    user: process.env.MTA_USER,
    password: process.env.MTA_PASS,
    resource: process.env.MTA_RESOURCE,
  });

  const response = await mta.guiScanComplete(player, {
    windowTitle,
    openOnly: process.argv.includes("--all") ? false : true,
    trees: !process.argv.includes("--no-trees"),
    includeAllElements: process.argv.includes("--all-elements"),
    flat: process.argv.includes("--flat"),
  });

  console.log(JSON.stringify(response.result || response, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  if (error.body) console.error(JSON.stringify(error.body, null, 2));
  process.exit(1);
});
