# MTA Agent Bridge

HTTP bridge resource for AI agents to interact with an MTA:SA server. Supports named HTTP exports, a REST router, `loadstring` eval, and layered memory (in-memory + SQLite). Includes a Node.js middleware for local proxying and session memory.

> **AI agents:** read [AGENTS.md](AGENTS.md) first for installation steps, troubleshooting, and how to connect to this resource.

## Requirements

- MTA:SA **1.6.0+** (router support)
- Node.js **18+** (for middleware only)

## Setup

1. **Create an MTA HTTP account** (server console) — the installer does **not** create accounts:
   ```
   addaccount your_http_user your_password
   ```

2. Edit `node/.env` (auto-created from `.env.example` on first resource/middleware start if missing) and set `MTA_USER` / `MTA_PASS` to match. Quote passwords that contain `#`, e.g. `MTA_PASS="secret#1"`.

3. Start the resource, then grant ACL and restart:
   ```
   start agent
   aclrequest allow agent all
   restart agent
   ```
   After a successful install the resource adds `user.<MTA_USER>` to the `agent` ACL group, denies install-only rights, scrubs dangerous ACL APIs from `_G`, and restarts itself.

4. (Optional) Node middleware:
   ```bash
   cd node
   npm install
   npm start
   ```
   First start creates `node/.env` from `.env.example` if it is missing.

## Authentication

All MTA HTTP calls use Basic Auth against an **existing** MTA account (you create it with `addaccount`). Configure in `node/.env`:

- **User:** `MTA_USER`
- **Pass:** `MTA_PASS`

Do not commit `node/.env`.

## Direct HTTP — Named Exports

Base URL: `http://127.0.0.1:22005/agent/call/<function>`

POST a JSON array of arguments:

```bash
# Ping
curl -u USER:PASS \
  -X POST http://127.0.0.1:22005/agent/call/ping \
  -H "Content-Type: application/json" \
  -d "[]"

# Eval (loadstring)
curl -u USER:PASS \
  -X POST http://127.0.0.1:22005/agent/call/eval \
  -H "Content-Type: application/json" \
  -d "[\"return getMaxPlayers()\"]"

# Memory
curl -u USER:PASS \
  -X POST http://127.0.0.1:22005/agent/call/memorySet \
  -H "Content-Type: application/json" \
  -d "[\"session:foo\", {\"hello\": \"world\"}]"

curl -u USER:PASS \
  -X POST http://127.0.0.1:22005/agent/call/memoryGet \
  -H "Content-Type: application/json" \
  -d "[\"session:foo\"]"
```

## Node Middleware

Base: `http://127.0.0.1:3847`

```bash
curl.exe -s http://127.0.0.1:3847/health
curl.exe -s http://127.0.0.1:3847/mta/features
```

Run features via `POST /mta/do` or `POST /mta/features/:id`. Full feature list and MCP setup: [AGENTS.md](AGENTS.md).

## In-game indications

Virtual look cues and distance markers, drawn on the client with `dxDraw`. Nothing is created in the world: no `createMarker`, blips, or other elements. A cue expires on its own after `timeout` seconds (default **15**), so a set can be fire-and-forget. `timeout: 0` or `ttlMs: 0` keeps it until `indicate.clear`.

Two uses:

- **Look cues** (`kind: "look"`, default) tell the player where to face. On screen, a bracket and label. Off screen, an arrow on the screen edge. A 3D ring is included when `mode` is `both` (the default for `look`) or `3d`.
- **Distance markers** (`kind: "marker"` or `"measure"`) label meters in the world. `marker` is a 3D ring and post at `x, y, z` (or a tracked `agentId`). `measure` is a 3D line between two points; the label is the segment length. `indicate.list` returns those same distances, plus `onScreen` and screen pixels, so a caller can read the number as well as see it in `screen.capture`.

| Feature | Role |
|---|---|
| `indicate.set` | Place or update one cue. Optional `items` JSON string places several. `replace: true` clears first. |
| `indicate.clear` | Remove one `id`, or all with `all: true`. |
| `indicate.list` | Live distances and screen positions. |

```bash
curl.exe -s -X POST http://127.0.0.1:3847/mta/do \
  -H "Content-Type: application/json" \
  -d "{\"feature\":\"indicate.set\",\"kind\":\"look\",\"x\":0,\"y\":0,\"z\":3,\"label\":\"Look here\"}"

curl.exe -s -X POST http://127.0.0.1:3847/mta/do \
  -H "Content-Type: application/json" \
  -d "{\"feature\":\"indicate.set\",\"kind\":\"measure\",\"x\":0,\"y\":0,\"z\":3,\"toX\":10,\"toY\":0,\"toZ\":3}"

curl.exe -s -X POST http://127.0.0.1:3847/mta/do \
  -H "Content-Type: application/json" \
  -d "{\"feature\":\"indicate.list\"}"
```

Direct MTA: `POST /agent/call/indicate` with `[player, options]`, then poll `indicateResult`.

## Manual ACL

If auto-install did not run, merge [acl/agent-acl-snippet.xml](acl/agent-acl-snippet.xml) into `acl.xml` and replace `your_http_user` with your `MTA_USER`.

## Security

`eval` executes arbitrary server-side Lua. Restrict network access to the MTA HTTP port and keep credentials private. The Node middleware binds to `127.0.0.1` only.

## License

Released under the [MIT License](LICENSE). Provided **as is**, without warranty of any kind. Use at your own risk — the authors are not responsible for damages or other liability arising from use of this software.
