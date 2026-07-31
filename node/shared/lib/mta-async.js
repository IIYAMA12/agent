const { pollUntilComplete } = require("./poll");

async function pollAsyncJob(start, getResult, pollOptions = {}) {
  const pending = await start();
  if (!pending?.id) {
    return pending;
  }
  return pollUntilComplete(() => getResult(pending.id), pollOptions);
}

module.exports = { pollAsyncJob };
