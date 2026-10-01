const luaparse = require("luaparse");
const { httpError } = require("./http-error");

const EXPRESSION_PREFIX = "return ";
const PARSE_OPTIONS = { luaVersion: "5.1" };

function tryParse(source) {
  try {
    luaparse.parse(source, PARSE_OPTIONS);
    return null;
  } catch (error) {
    return error;
  }
}

function parserDetail(error) {
  return String(error.message || error).replace(/^\[[0-9]+:[0-9]+\]\s*/, "");
}

/** Map an error from `return ` + code back onto the caller's source. */
function mapExpressionError(error) {
  if (!error || error.line == null || error.column == null) {
    return null;
  }
  if (error.line > 1) {
    return { line: error.line, column: error.column, detail: parserDetail(error) };
  }
  if (error.column < EXPRESSION_PREFIX.length) {
    return null;
  }
  return {
    line: 1,
    column: error.column - EXPRESSION_PREFIX.length,
    detail: parserDetail(error),
  };
}

function locatedFrom(error) {
  return {
    line: error.line || 1,
    column: error.column || 0,
    detail: parserDetail(error),
  };
}

/**
 * Pick the diagnostic that points at the caller's code.
 * A chunk error on the first character is usually "not a statement" (`40 +`);
 * the expression parse then names the real break.
 */
function chooseLocation(rawError, expressionError) {
  const raw = locatedFrom(rawError);
  const rawAtStart = raw.line === 1 && raw.column === 0;
  const mapped = mapExpressionError(expressionError);
  if (rawAtStart && mapped) {
    return mapped;
  }
  return raw;
}

function formatSyntaxError(code, located) {
  const lines = String(code).split(/\r?\n/);
  const lineNumber = Math.max(1, located.line || 1);
  const sourceLine = lines[lineNumber - 1] ?? "";
  const columnIndex = Math.max(0, located.column || 0);
  const caretAt = Math.min(columnIndex, sourceLine.length);
  const displayColumn = caretAt + 1;
  const detail = located.detail || "syntax error";

  const shown = windowLine(sourceLine, caretAt);
  const message = [
    `Lua syntax error at line ${lineNumber}, column ${displayColumn}: ${detail}`,
    shown.text,
    `${" ".repeat(shown.caret)}^`,
  ].join("\n");

  return httpError(message, {
    status: 400,
    code: "LUA_SYNTAX",
    body: {
      line: lineNumber,
      column: displayColumn,
      snippet: shown.text,
    },
  });
}

function windowLine(line, caretAt) {
  const max = 120;
  if (line.length <= max) {
    return { text: line, caret: caretAt };
  }
  const start = Math.max(0, caretAt - 40);
  const end = Math.min(line.length, start + max);
  const prefix = start > 0 ? "…" : "";
  const suffix = end < line.length ? "…" : "";
  return {
    text: prefix + line.slice(start, end) + suffix,
    caret: caretAt - start + prefix.length,
  };
}

/**
 * Accept a Lua 5.1 expression (`40 + 2`) or chunk (`return 40 + 2`, `local a = 5`).
 * Throws LUA_SYNTAX with line, column, and the broken line when both parses fail.
 */
function assertLuaEvalCode(code) {
  const expressionError = tryParse(EXPRESSION_PREFIX + code);
  if (!expressionError) {
    return;
  }
  const rawError = tryParse(code);
  if (!rawError) {
    return;
  }
  throw formatSyntaxError(code, chooseLocation(rawError, expressionError));
}

module.exports = { assertLuaEvalCode };
