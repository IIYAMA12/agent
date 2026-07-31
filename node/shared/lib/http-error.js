function httpError(message, { status = 400, code, hint, body } = {}) {
  const error = new Error(message);
  error.status = status;
  if (code) error.code = code;
  if (hint) error.hint = hint;
  if (body) error.body = body;
  return error;
}

module.exports = { httpError };
