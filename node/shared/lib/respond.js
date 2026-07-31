function success(res, data, extra = {}, status = 200) {
  res.status(status).json({
    ok: true,
    data,
    result: data,
    ...extra,
  });
}

function failure(res, error, status, extra = {}) {
  const code = status || error.status || 500;
  res.status(code).json({
    ok: false,
    error: error.message || String(error),
    code: error.code || undefined,
    hint: error.hint || undefined,
    body: error.body || undefined,
    playersOnline: error.playersOnline || undefined,
    ...extra,
  });
}

function sendError(error) {
  const err = error instanceof Error ? error : new Error(String(error));
  err.status = err.status || 500;
  return err;
}

function asyncRoute(handler) {
  return async (req, res) => {
    try {
      await handler(req, res);
    } catch (error) {
      failure(res, sendError(error));
    }
  };
}

module.exports = { success, failure, sendError, asyncRoute };
