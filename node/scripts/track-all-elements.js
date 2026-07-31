require("../shared/load-env").loadEnv();
const { MtaClient } = require("../shared/mta-client");

const SERVER_TRACK_CODE = `
local types = {"vehicle","player","ped","object","pickup","marker","blip","colshape","radararea","team","water","weapon"}
local byType = {}
local total = 0
for i = 1, #types do
  local t = types[i]
  local n = 0
  for _, el in ipairs(getElementsByType(t)) do
    if isElement(el) then
      local id = Agent.trackElement(el, { source = "trackAll" })
      if id then
        n = n + 1
        total = total + 1
      end
    end
  end
  byType[t] = n
end
return { side = "server", total = total, byType = byType, startupAt = Agent.registry and Agent.registry.startupAt }
`.trim();

const CLIENT_TRACK_CODE = `
local types = {"vehicle","player","ped","object","pickup","marker","blip","colshape","radararea","team","water","weapon"}
local byType = {}
local total = 0
local localOnly = 0
for i = 1, #types do
  local t = types[i]
  local n = 0
  for _, el in ipairs(getElementsByType(t)) do
    if isElement(el) then
      local id = Agent.trackElement(el, { source = "trackAll" })
      if id then
        n = n + 1
        total = total + 1
        local entry = Agent.getRegistryEntryForElement(el)
        if entry and entry.localOnly then
          localOnly = localOnly + 1
        end
      end
    end
  end
  byType[t] = n
end
return { side = "client", total = total, localOnly = localOnly, byType = byType, startupAt = Agent.registry and Agent.registry.startupAt }
`.trim();

async function main() {
  const mta = new MtaClient({
    host: process.env.MTA_HOST,
    port: process.env.MTA_PORT,
    user: process.env.MTA_USER,
    password: process.env.MTA_PASS,
    resource: process.env.MTA_RESOURCE,
  });

  const player = process.argv[2] || "IIYAMA";

  const serverResult = await mta.call("eval", [SERVER_TRACK_CODE]);
  console.log("Server track:", JSON.stringify(serverResult, null, 2));

  const clientEval = await mta.evalClientComplete(CLIENT_TRACK_CODE, player);
  console.log("Client track:", JSON.stringify(clientEval, null, 2));

  const syncResult = await mta.call("elementList", [{ syncClient: true, player }]);
  console.log("Registry total:", syncResult.elements?.length ?? 0);
  console.log(JSON.stringify(syncResult, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
