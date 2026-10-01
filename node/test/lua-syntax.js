const assert = require("assert");
const { assertLuaEvalCode } = require("../shared/lib/lua-syntax");

function accept(code) {
  assert.doesNotThrow(() => assertLuaEvalCode(code), `expected to accept: ${code}`);
}

function reject(code, expected) {
  let caught;
  try {
    assertLuaEvalCode(code);
  } catch (error) {
    caught = error;
  }
  assert.ok(caught, `expected to reject: ${code}`);
  assert.equal(caught.status, 400);
  assert.equal(caught.code, "LUA_SYNTAX");
  assert.equal(caught.body.line, expected.line);
  assert.equal(caught.body.column, expected.column);
  assert.match(caught.message, expected.detail);
  const lines = caught.message.split("\n");
  assert.equal(lines.length, 3, caught.message);
  const caret = lines[2];
  assert.equal(caret.trim(), "^");
  assert.equal(caret.indexOf("^"), expected.column - 1);
}

accept("40 + 2");
accept("return 40 + 2");
accept("local a = 5");
accept("1, 2, 3");

reject("return return 1", {
  line: 1,
  column: 8,
  detail: /unexpected keyword 'return'/,
});

reject("local =", {
  line: 1,
  column: 7,
  detail: /<name> expected near '='/,
});

reject("40 +", {
  line: 1,
  column: 5,
  detail: /<expression> expected near '<eof>'/,
});

reject("local a = 5\nlocal =", {
  line: 2,
  column: 7,
  detail: /<name> expected near '='/,
});

console.log("lua-syntax ok");
