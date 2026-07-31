const { createMtaClient } = require("../shared/config");

async function main() {
  const mta = createMtaClient();
  const player = process.argv[2] || process.env.AGENT_PLAYER || "IIYAMA";
  const result = await mta.lookTarget({ player, type: "vehicle", debugLog: true });

  console.log(JSON.stringify(result, null, 2));

  const target = result.lookingAt;
  if (target) {
    const name = target.name || target.id;
    console.log(`\n>>> Looking at: ${name} (model ${target.model}) via ${result.method}`);
  } else {
    console.log("\n>>> No target in crosshair");
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
