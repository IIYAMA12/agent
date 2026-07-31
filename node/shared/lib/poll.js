function normalizeAsyncPollResult(result) {
  const status = result?.status;

  if (status === "pending") {
    return null;
  }
  if (status === "complete") {
    return result;
  }
  if (status === "error" || status === "failed") {
    const error = new Error(result?.error || "Async query failed");
    error.code = "ASYNC_QUERY_FAILED";
    error.body = result;
    throw error;
  }

  // MtaClient.invoke() unwraps { ok, status, result } and returns only `result`.
  if (status === undefined && result !== undefined) {
    return { status: "complete", result };
  }

  return null;
}

async function pollUntilComplete(fetchResult, options = {}) {
  const intervalMs = options.intervalMs || 100;
  const timeoutMs = options.timeoutMs || 8000;
  const start = Date.now();

  while (Date.now() - start < timeoutMs) {
    const result = await fetchResult();
    const normalized = normalizeAsyncPollResult(result);
    if (normalized) {
      return normalized;
    }

    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  const error = new Error("Async query timed out");
  error.status = 504;
  error.code = "ASYNC_TIMEOUT";
  throw error;
}

module.exports = { pollUntilComplete };
