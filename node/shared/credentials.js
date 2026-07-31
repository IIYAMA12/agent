const { ensureEnvLoaded } = require("./load-env");

function trim(value) {
  return typeof value === "string" ? value.trim() : "";
}

function getCredentials() {
  ensureEnvLoaded();

  const user = trim(process.env.MTA_USER);
  const password = trim(process.env.MTA_PASS);
  const sources = [];
  if (user) sources.push("MTA_USER");
  if (password) sources.push("MTA_PASS");

  return {
    user,
    password,
    source: sources.length ? ".env" : "missing",
  };
}

module.exports = { getCredentials, trim };
