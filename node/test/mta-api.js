const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { parseTree } = require("../shared/lib/mta-api/parse");
const { rebuild, query } = require("../shared/lib/mta-api/store");

const root = path.join(__dirname, "fixtures/mta-annotations");
const { symbols } = parseTree(root);

function find(name) {
  return symbols.filter((symbol) => symbol.name === name);
}

function overload(symbol, side) {
  return symbol.overloads.find((item) => item.side === side);
}

const vehicles = find("createVehicle");
assert.equal(vehicles.length, 1);
assert.equal(vehicles[0].side, "shared");
assert.equal(vehicles[0].kind, "function");
assert.equal(vehicles[0].wiki, "https://wiki.multitheftauto.com/wiki/CreateVehicle");
assert.deepEqual(
  vehicles[0].overloads.map((item) => item.side).sort(),
  ["client", "server"]
);
const serverVehicle = overload(vehicles[0], "server");
assert.equal(serverVehicle.label, "createVehicle_server");
assert.equal(serverVehicle.params[0].name, "model");
assert.equal(serverVehicle.params[0].type, "vehicleId");
assert.equal(serverVehicle.params[4].name, "rx");
assert.equal(serverVehicle.params[4].optional, true);
assert.equal(overload(vehicles[0], "client").params.length, 4);

const position = find("getElementPosition")[0];
assert.equal(position.side, "shared");
assert.equal(position.overloads.length, 1);
assert.equal(position.overloads[0].side, "shared");
assert.deepEqual(position.overloads[0].params, [
  { name: "theElement", type: "element", optional: false },
]);
assert.equal(position.overloads[0].returns, "x: number, y: number, z: number");
assert.equal(position.description, "three floats indicating the position");

const fade = find("fadeCamera")[0];
assert.equal(overload(fade, "server").params[0].name, "thePlayer");
assert.equal(overload(fade, "server").params[2].name, "timeToFade");
assert.equal(overload(fade, "server").params[2].optional, true);
assert.equal(overload(fade, "client").params[0].name, "fadeIn");
assert.equal(overload(fade, "client").params.some((param) => param.name === "thePlayer"), false);

const chat = find("outputChatBox")[0];
assert.equal(chat.side, "client");
assert.equal(chat.file, "__client_definitions.lua");
assert.equal(chat.overloads[0].side, "client");
assert.equal(chat.overloads[0].params[1].optional, true);

const account = find("addAccount")[0];
assert.equal(account.side, "server");
assert.equal(account.file, "__server_definitions.lua");
assert.equal(account.deprecated, true);
assert.equal(account.overloads[0].side, "server");
assert.equal(account.overloads[0].returns, "account | false");

const render = find("onClientRender")[0];
assert.equal(render.kind, "event");
assert.equal(render.side, "client");
assert.equal(render.file, "addEventHandler/__client_definitions_addEventHandler.lua");
assert.equal(render.overloads[0].params[0].name, "eventName");
assert.equal(render.overloads[0].params[0].type, '"onClientRender"');

const draw = find("dxDrawText")[0];
assert.equal(draw.side, "client");
assert.equal(draw.file, "__dx_definitions.lua");
assert.equal(draw.overloads[0].side, "client");

const big = find("tooBig")[0];
assert.equal(big.overloads.length, 1);
assert.match(big.description, /Unexpanded union of 13/);
assert.equal(big.overloads[0].params.length, 0);

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mta-api-"));
const dbPath = path.join(dir, "mta-api.db");
rebuild(symbols, { commit: "abc", sourceUrl: "test", fetchedAt: "2026-01-01T00:00:00.000Z" }, dbPath);

const clientVehicles = query(dbPath, { name: "createVehicle", side: "client" });
assert.equal(clientVehicles.exact, true);
assert.deepEqual(
  clientVehicles.matches[0].overloads.map((item) => item.side).sort(),
  ["client"]
);

const serverPosition = query(dbPath, { name: "getElementPosition", side: "server" });
assert.equal(serverPosition.matches[0].overloads[0].side, "shared");

const hidden = query(dbPath, { name: "addAccount", side: "client" });
assert.equal(hidden.exact, true);
assert.equal(hidden.matches.length, 0);

const fuzzy = query(dbPath, { name: "dxDraw" });
assert.equal(fuzzy.exact, false);
assert.equal(fuzzy.matches[0].name, "dxDrawText");

assert.throws(() => query(dbPath, { name: "createVehicle", side: "both" }), {
  code: "MTA_API_SIDE",
});

console.log("mta-api tests ok");
