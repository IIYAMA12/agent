const { getCredentials } = require("../shared/credentials");
const { createMtaClient } = require("../shared/config");

async function main() {
  const creds = getCredentials();
  console.log("credentials source:", creds.source);
  console.log("username:", creds.user || "(missing)");
  console.log("password length:", creds.password ? creds.password.length : 0);

  if (!creds.user || !creds.password) {
    process.exit(1);
  }

  const client = createMtaClient();

  try {
    const ping = await client.ping();
    console.log("ping ok:", JSON.stringify(ping));
  } catch (error) {
    console.error("ping failed:", error.status, error.message);
    console.error("body:", JSON.stringify(error.body));
    process.exit(1);
  }
}

main();
