require("../shared/load-env").loadEnv();
const { restartMiddleware } = require("../shared/lib/middleware-process");

async function main() {
  const delayMs = Number(process.argv[2] || 300);
  const result = await restartMiddleware({ delayMs, wait: true, requireAllowed: true });
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
