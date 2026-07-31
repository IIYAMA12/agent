# AGENTS.md — Instructions for AI Agents

**Read this file first.** When this is a **new Cursor workspace**, a **new agent session**, or the user asks to get the project running — **guide them step-by-step through the playbook below**. Confirm each step before moving on.

User-facing overview: [README.md](README.md)

---

## Agent playbook — guide the user in order

Use this checklist interactively. Say what step you are on, what the user must do, and how to verify success.

### Phase 0 — Prerequisites

| Requirement | How to check |
|---|---|
| MTA:SA dedicated server **1.6.0+** | `meta.xml` → `<min_mta_version>` |
| Node.js **18+** (for middleware/MCP) | `node --version` |
| Resource at `<deathmatch>/resources/agent/` | Folder contains `meta.xml`, `server/` |
| MTA server process **running** | HTTP port responds (default **22005**) |

Ask the user for: MTA install path, in-game player name (for later steps), and whether they use **Cursor**, **Claude Desktop**, **VS Code**, or **HTTP/scripts only**.

---

### Phase 1 — MTA resource (game server)

**Step 1 — Start the resource**

Ask the user to run in the **MTA server console** (you cannot run this yourself):

```
start agent
```

Verify: no Lua errors in `mods/deathmatch/logs/server.log`.

**Step 2 — Grant ACL (first run only)**

```
aclrequest allow agent all
restart agent
```

Without this, `loadstring` eval and ACL auto-install will fail.

**Step 3 — Credentials (manual account)**

The agent does **not** create MTA accounts. You must:

1. In the **MTA server console**: `addaccount <username> <password>`
2. Ensure `node/.env` exists (auto-created from `.env.example` on first start if missing) and set `MTA_USER` / `MTA_PASS` (quote passwords that contain `#`)
3. Delete `data/lock-install` and `restart agent` if the installer must re-add the user after changing `MTA_USER`

**Step 4 — Verify direct MTA HTTP**

Run (use `curl.exe` on Windows — not PowerShell's `curl` alias):

```bash
curl.exe -u USER:PASS -X POST http://127.0.0.1:22005/agent/call/ping -H "Content-Type: application/json" -d "[]"
```

Expected: JSON with `"ok": true`, resource `"agent"`.

If this fails, stop and use [Troubleshooting](#troubleshooting) before continuing.

---

### Phase 2 — Node middleware (local bridge)

**Step 5 — Install and configure**

```bash
cd node
npm install
# .env is auto-created on first loadEnv if missing; edit MTA_USER / MTA_PASS
```

Edit `node/.env`:

| Variable | Typical value |
|---|---|
| `MTA_HOST` | `127.0.0.1` (not `localhost`) |
| `MTA_PORT` | `22005` (from `mtaserver.conf` `<httpport>`) |
| `MTA_USER` / `MTA_PASS` | Same as Step 3 |
| `AGENT_PLAYER` | User's in-game name (optional; auto-resolves if alone online) |
| `AGENT_PLAYER_SERIAL` | **Preferred** — 32-char client serial (stable; names can change or collide). Get from `getServerState` → `playerDetails` |
| `ALLOW_HTTP_EVAL` | `0` — middleware HTTP/MCP gate for server `eval` / `eval.server` only (see [ALLOW_HTTP_EVAL section](#allow_http_eval--middleware-http-server-eval-gate) below) |
| `ALLOW_RESTART` | `0` — set `1` to allow MCP/HTTP auto-restart of agent resource + middleware |

**Step 6 — Start middleware (keep running)**

```bash
cd node
npm start
```

Expected console line: `[agent-middleware] v1.1.0 listening on http://127.0.0.1:3847`

**Step 7 — Verify middleware**

```bash
curl.exe -s http://127.0.0.1:3847/health
```

Expected: `"middleware": "running"`, `"mta": { "ok": true }`, `"features": [...]`.

Optional: `npm run test:auth` in `node/` to verify credentials load correctly.

---

### Phase 3 — Connect your AI tool

Pick **one** path based on what the user uses. Middleware (Phase 2) must stay running for all paths except direct MTA HTTP.

#### Cursor (MCP — recommended)

**Primary (global):** `~/.cursor/mcp.json` on this machine — `mta-agent` works in **any** Cursor workspace.

**Local backup:** [`.cursor/mcp.json.local`](.cursor/mcp.json.local) — workspace-relative template; copy to `.cursor/mcp.json` if global config is unavailable.

1. User opens **Cursor Settings → MCP**
2. Confirm server **`mta-agent`** appears (runs `node/mcp/index.js` via stdio)
3. **Reload MCP** after changing global or local config
4. Verify tools: `mta_health`, `mta_run_feature`, `mta_teleport_area`, `mta_eval_client`, etc.

**If MCP is unavailable:** tell the user explicitly before falling back to HTTP. See [`.cursor/rules/mta-agent-mcp.mdc`](.cursor/rules/mta-agent-mcp.mdc).

#### Claude Desktop (MCP)

Add to `%APPDATA%\Claude\claude_desktop_config.json` (adjust path to this resource):

```json
{
  "mcpServers": {
    "mta-agent": {
      "command": "node",
      "args": ["C:/path/to/resources/agent/node/mcp/index.js"],
      "env": {
        "MIDDLEWARE_URL": "http://127.0.0.1:3847"
      }
    }
  }
}
```

Restart Claude Desktop. Same tools as Cursor.

#### VS Code + GitHub Copilot (MCP)

Add to user or workspace MCP settings (see [VS Code MCP docs](https://code.visualstudio.com/docs/agent-customization/mcp-servers)):

```json
{
  "servers": {
    "mta-agent": {
      "type": "stdio",
      "command": "node",
      "args": ["${workspaceFolder}/node/mcp/index.js"],
      "env": { "MIDDLEWARE_URL": "http://127.0.0.1:3847" }
    }
  }
}
```

Reload MCP servers from the command palette.

#### Any other MCP client

Any client that supports **stdio MCP** can run the same server:

- **Command:** `node`
- **Args:** `<absolute-path>/node/mcp/index.js`
- **Env:** `MIDDLEWARE_URL=http://127.0.0.1:3847`
- **Requires:** middleware running (`npm start`)

Tool manifest (for custom integrations): `GET http://127.0.0.1:3847/mta/tools.json`

#### No MCP — HTTP / curl / scripts only

Use middleware REST API at `http://127.0.0.1:3847` (no auth on middleware itself; it forwards MTA auth).

```bash
# List features
curl.exe -s http://127.0.0.1:3847/mta/features

# Run a feature
curl.exe -s -X POST http://127.0.0.1:3847/mta/do \
  -H "Content-Type: application/json" \
  -d "{\"feature\":\"look.target\",\"player\":\"YourName\",\"type\":\"vehicle\"}"
```

Direct MTA HTTP (bypass middleware): `http://127.0.0.1:22005/agent/call/<export>` with Basic Auth — see [Option A](#option-a--direct-mta-http).

---

### Phase 4 — In-game client + first command

**Step 8 — Player must be online**

Client-side features (`eval.client`, `look.target`, `findVisible`, etc.) require:

1. User connected to the server with the **`agent` resource running**
2. Client scripts loaded — after Lua changes, user runs `restart agent` and **reconnects**

**Step 9 — Smoke test (pick one)**

| Tool | Test |
|---|---|
| **MCP** | Call `mta_health` — should show online players + features |
| **MCP** | Call `mta_run_feature` with `{ "feature": "eval.client", "player": "Name", "params": { "code": "outputChatBox(\"Hi\")" } }` |
| **HTTP** | `POST /mta/features/eval.client` with `{ "player", "code" }` |
| **HTTP** | `POST /mta/features/teleport.area` with `{ "player", "search": "pizza" }` |

If client eval fails with "Client not loaded", user needs to reconnect after `restart agent`.

**Step 10 — Optional auto-start**

Add to `mtaserver.conf`:

```xml
<resource src="agent" startup="1" protected="0" />
```

---

### Phase 5 — You are ready

Normal agent loop:

1. **Discover** — `mta_health` / `GET /health` / `getServerState` (includes `playerDetails` with serials)
2. **Inspect** — `look.target`, `nearby.closest`, `gui.scan`, `debug.list`, `elements.list` / `elements.walk`
3. **Act** — `teleport.*`, `elements.track` / `elements.modify`, `eval.client` (client Lua)
4. **Remember** — Node `POST /memory` for session context (`session.defaultPlayerSerial` for stable player identity)

**After code changes:**

| Changed | User action |
|---|---|
| Lua / `meta.xml` | `restart agent` + reconnect client |
| `node/middleware/` or `node/shared/` | Restart `npm start` |
| `node/mcp/` or `.cursor/mcp.json` | Reload MCP in IDE |

---

## Rules — do not access the server terminal

**Never** automate or interact with the MTA Server console window. Specifically:

- Do **not** send keystrokes (e.g. `SendKeys`, `AppActivate`) to the MTA Server process
- Do **not** pipe commands into the server terminal
- Do **not** assume you can run `start`, `restart`, or `aclrequest` yourself

Instead:

- **Ask the user** to run MTA console commands when needed (`start agent`, `restart agent`, `aclrequest allow agent all`)
- **Use HTTP** — direct MTA calls or Node middleware at `http://127.0.0.1:3847`
- **Edit files** in this resource (`.env`, Lua scripts, `meta.xml`)
- **Read logs** at `mods/deathmatch/logs/server.log` (read-only)

After changing Lua or `meta.xml`, tell the user: `restart agent`

---

## What this resource does

The **agent** MTA resource exposes an HTTP API on the game server so an AI agent can:

- Call server-side Lua functions (`eval` via `loadstring`)
- Run client-side Lua asynchronously (`evalClient` + poll by request id)
- Find closest world elements near a player with type-specific props (`findNearby`)
- Query elements visible on a player's screen with debug info (`findVisible`)
- Resolve what a player is looking at via camera + [`isElementOnScreen`](https://wiki.multitheftauto.com/wiki/IsElementOnScreen) (`findLookTarget`)
- **Track and modify game elements** with stable agent IDs (`elementTrack`, `elementList`, `elementWalk`, …)
- **Scan client GUI** (open windows, CEGUI widget trees via `guiScan`)
- **Capture debug logs** from [`onDebugMessage`](https://wiki.multitheftauto.com/wiki/OnDebugMessage) / [`onClientDebugMessage`](https://wiki.multitheftauto.com/wiki/OnClientDebugMessage) (`debugLogList`, last 500, anti-dupe)
- Resolve players by **name or serial** (`resolvePlayer`, `AGENT_PLAYER_SERIAL`)
- Read/write key-value memory (in-memory + SQLite on MTA and Node)
- Query server state (players + serials, resources, map)
- Proxy calls to other MTA resource exports

Optional **Node middleware** (`node/`) proxies MTA HTTP when the agent cannot reach port 22005 directly, and provides a separate local memory store.

```
Agent (you) ──HTTP──► MTA :22005/agent     (direct, preferred)
         └──HTTP──► Node :3847 ──► MTA     (fallback proxy)
```

Docs: [Resource Web Access](https://wiki.multitheftauto.com/wiki/Resource_Web_Access) · [Meta.xml](https://wiki.multitheftauto.com/wiki/Meta.xml)

---

## Before you start — gather context

Ask or infer the following. Do not assume paths or credentials from a different machine.

| Item | Where to find it |
|---|---|
| MTA server root | Usually `.../server/mods/deathmatch/` |
| Resource folder | `resources/agent/` |
| HTTP port | `mtaserver.conf` → `<httpport>` (default **22005**) |
| HTTP credentials | `node/.env` (if middleware set up), or user-provided; see [Credentials](#credentials) |
| MTA version | Must be **1.6.0+** (router export) |
| Node.js | **18+** if using middleware |

Check whether the MTA server process is actually running before debugging HTTP failures.

> **New instance?** Use the [Agent playbook](#agent-playbook--guide-the-user-in-order) above instead of jumping straight to this section.

---

## Installation checklist (legacy — see playbook)

The numbered steps below mirror the playbook for reference. Prefer guiding the user through [Phase 1–4](#agent-playbook--guide-the-user-in-order) interactively.

### 1. Place the resource

Ensure the folder exists at:

```
<deathmatch>/resources/agent/
```

Required files: `meta.xml`, `server/*.lua`, optionally `node/`.

### 2. Start the resource

In the MTA server console (or in-game as admin):

```
start agent
```

If the resource fails to start, read the server log for Lua errors. Common causes: MTA version below 1.6, missing `meta.xml`, script syntax error.

### 3. Grant ACL rights (first run)

On first start the resource requests ACL rights. In server console:

```
aclrequest allow agent all
restart agent
```

Without this, auto-install and `loadstring` eval will not work.

**Permanent rights** (kept): `function.loadstring`, `function.startResource`, `function.stopResource`, `function.restartResource`.

**Install-only rights** (auto-denied after success): ACL create/group helpers, `aclSetRight`, `aclSave`, `updateResourceACLRequest`, `general.ModifyOtherObjects`.

DB (`dbConnect` / `dbExec` / …) is **not** listed in `aclrequest` — those APIs are allowed by default.

### 4. Verify ACL auto-install

The installer (`server/installation_s.lua`) should:

1. Create ACL group `agent` and ACL `Agent`
2. Grant `resource.agent.http` via [`aclSetRight`](https://wiki.multitheftauto.com/wiki/AclSetRight)
3. Add the configured HTTP user to that group
4. Deny install-only aclrequests, scrub dangerous ACL globals from `_G`, write `data/lock-install`
5. `restartResource(getThisResource())` so the next start runs with scrubbed globals

**Check server log** for:

- `[agent] ACL installation completed; install-only rights denied. Restarting resource...` — success
- `[agent] ACL install aborted: Set MTA_USER in node/.env...` — create/fix `.env` first, then restart
- `Missing rights for ACL installation` — run step 3 again
- `Failed to add ... to agent ACL group` — account may not exist; see [Credentials](#credentials)
- `ACL installation already completed` on later starts — install skipped; `_G` scrub still runs

**Manual fallback:** merge [acl/agent-acl-snippet.xml](acl/agent-acl-snippet.xml) into `acl.xml` and adjust the username.

### 5. Configure credentials

See [Credentials](#credentials). Edit `node/.env` (`MTA_USER` / `MTA_PASS`) **before** first ACL install — placeholders are auto-created on resource/middleware start if missing.

Delete `data/lock-install` and restart `agent` if you need the installer to re-run after changing the HTTP user.

### 6. (Optional) Node middleware

```bash
cd node
npm install
# Edit node/.env (auto-created from .env.example if missing) with MTA_HOST, MTA_PORT, MTA_USER, MTA_PASS
npm start
```

Middleware listens on `127.0.0.1:3847` by default. Keep it local-only.

### 7. Verify connectivity

Run checks yourself when possible (use `curl.exe` on Windows — PowerShell aliases `curl` to `Invoke-WebRequest`).

**Direct MTA ping** (replace `USER`, `PASS`, `PORT`):

```bash
curl.exe -u USER:PASS -X POST http://127.0.0.1:PORT/agent/call/ping -H "Content-Type: application/json" -d "[]"
```

Expected: JSON with `"ok": true` and resource name `agent`.

**Eval smoke test:**

```bash
curl.exe -u USER:PASS -X POST http://127.0.0.1:PORT/agent/call/eval -H "Content-Type: application/json" -d "[\"return getMaxPlayers()\"]"
```

**Node health** (no auth on middleware itself):

```bash
curl.exe -s http://127.0.0.1:3847/health
```

Expected: `"middleware": "running"` and MTA ping result if MTA is up.

### 8. (Optional) Auto-start on boot

Add to `mtaserver.conf`:

```xml
<resource src="agent" startup="1" protected="0" />
```

---

## Credentials

HTTP uses **MTA account Basic Auth**. You create the account yourself; ACL install only grants `resource.agent.http` to that user in the `agent` group.

**You must create the account** (server console) — install never runs `addaccount`:

```
addaccount your_http_user your_password
```

Then put the same values in `node/.env` as `MTA_USER` / `MTA_PASS`. Quote passwords that contain `#`.

**Env files:**

| File | Role | Git |
|---|---|---|
| `node/.env.example` | Template (committed) | committed |
| `node/.env` | Operator config — auto-created from `.env.example` if missing | ignored |

Single source of truth: `node/.env`. Loaded by [node/shared/load-env.js](node/shared/load-env.js) and [server/installation_s.lua](server/installation_s.lua).

**First-time checklist:**

1. `addaccount <user> <pass>` in the MTA server console
2. Start `agent` and/or middleware so `node/.env` is created if needed; edit `MTA_USER` / `MTA_PASS`
3. `aclrequest allow agent all` then `restart agent` so install adds `user.<MTA_USER>`
4. Or manually add `user.<name>` to the `agent` group in `acl.xml`

**Security:** Never paste live passwords into chat logs or commit `.env`.

---

## How to communicate with the resource

### Option A — Direct MTA HTTP (preferred)

Base: `http://<host>:<httpport>/agent`

| Style | URL pattern | Body |
|---|---|---|
| Named export | `POST /agent/call/<exportName>` | JSON **array** of arguments |
| REST router | `POST /agent/api/eval` etc. | JSON **object** |

Auth: `Authorization: Basic base64(user:pass)` or `curl -u user:pass`.

**Exports:** `ping`, `eval`, `evalClient`, `evalClientResult`, `findNearby`, `findVisible`, `findVisibleResult`, `findLookTarget`, `findLookTargetResult`, `teleportToClosestAirport`, `getAreaMap`, `listAreas`, `findClosestArea`, `teleportToArea`, `teleportToElement`, `teleportToPlayer`, `elementTrack`, `elementGet`, `elementList`, `elementRelease`, `elementModify`, `elementResolve`, `elementWalk`, `guiScan`, `guiScanResult`, `debugLogList`, `debugLogResult`, `resolvePlayer`, `memoryGet`, `memorySet`, `memoryDelete`, `memoryList`, `callExport`, `getServerState`, `resourceStart`, `resourceStop`, `resourceRestart`

**Router paths:**

| Method | Path | Body / query |
|---|---|---|
| GET | `/api/ping` | — |
| POST | `/api/eval` | `{ "code": "..." }` (server) |
| POST | `/api/eval/client` | `{ "code": "...", "player"?, "serial"? }` → `{ "id", "status": "pending" }` |
| GET | `/api/eval/client/:id` | Poll async client eval result |
| GET/POST | `/api/nearby` | See [findNearby](#findnearby--closest-elements) below |
| POST | `/api/visible` | `{ "player"?, "serial"?, "type"?, "limit"?, ... }` → `{ "id", "status": "pending" }` |
| GET | `/api/visible/:id` | Poll visible-element query |
| POST | `/api/look` | `{ "player"?, "serial"?, "type"?, ... }` → `{ "id", "status": "pending" }` — camera look target |
| GET | `/api/look/:id` | Poll look-target query |
| GET/POST | `/api/gui/scan` | `{ "player"?, "serial"?, "windowTitle"?, "trees"?, ... }` → async `{ "id" }` or sync result |
| GET | `/api/gui/:id` | Poll GUI scan result |
| GET/POST | `/api/debug/logs` | `{ "side"?: "server"\|"client"\|"all", "player"?, "serial"?, "minLevel"?, "limit"? }` — server sync; client/all async |
| GET | `/api/debug/:id` | Poll debug log fetch (client/all) |
| GET/POST | `/api/elements/walk` | Element tree walk (`mode`: `roots`, resource name, `flat`, …) |
| POST | `/api/elements/track` | Register element by handle |
| GET/POST | `/api/elements` | List tracked elements |
| GET | `/api/elements/:id` | Get tracked element |
| GET/POST/DELETE | `/api/memory`, `/api/memory/:key` | see README |
| POST | `/api/call` | `{ "resource", "function", "args": [] }` |
| POST | `/api/resources/start` | `{ "resource": "name" }` |
| POST | `/api/resources/stop` | `{ "resource": "name" }` |
| POST | `/api/resources/restart` | `{ "resource": "name" }` |
| GET | `/api/state` | Players, `playerDetails` (name + serial), resources |

### Option B — Node middleware (fallback)

Base: `http://127.0.0.1:3847`

| Route | Purpose |
|---|---|
| `GET /health` | Liveness + MTA reachability |
| `POST /mta/eval` | `{ "code": "..." }` |
| `POST /mta/eval/client` | Start async client eval → `{ "id" }` |
| `GET /mta/eval/client/:id` | Poll client eval result |
| `GET /mta/nearby` | Closest elements (query params) |
| `POST /mta/nearby` | Closest elements (JSON body) |
| `POST /mta/visible` | Start visible-element query → `{ "id" }` |
| `GET /mta/visible/:id` | Poll visible-element result |
| `POST /mta/look` | Start look-target query → `{ "id" }` |
| `GET /mta/look/:id` | Poll look-target result |
| `POST /mta/call` | `{ "resource", "function", "args": [] }` |
| `GET /mta/areas` | List areas (`?category=&region=&search=`) |
| `GET /mta/areas/map` | Full area map with category/region counts |
| `GET /mta/areas/closest` | Closest area to player (`?player=&category=&region=&locationId=`) |
| `POST /mta/teleport` | Teleport to area or element (auto-detect from body) |
| `POST /mta/teleport/player` | Teleport player to another player |
| `POST /mta/teleport/element` | Teleport player to element (player, vehicle, etc.) |
| `POST /mta/teleport/airport` | Teleport to closest airport (legacy shortcut) |
| `GET /mta/features` | List built-in simple features (teleport, look, nearby) |
| `POST /mta/features/:id` | Run a feature, e.g. `teleport.player`, `teleport.area` |
| `POST /mta/do` | Run feature by body `{ "feature": "teleport.area", ...params }` |
| `GET /mta/tools.json` | Machine-readable tool manifest (features + MCP tool names) |
| `GET/POST/DELETE /memory` | Local agent memory (not MTA) |

Use middleware when direct access to port 22005 fails (firewall, remote dev machine, tool restrictions).

### Option C — MCP (Cursor, Claude Desktop, VS Code, any stdio client)

Architecture:

```
AI tool ──stdio──► node/mcp/index.js ──HTTP──► node/middleware/ (:3847) ──HTTP──► MTA (:22005)
```

**Requires:** middleware running (`cd node && npm start`).

| Entry | Purpose |
|---|---|
| `node/mcp/index.js` | MCP stdio server (`npm run mcp`) |
| `.cursor/mcp.json.local` | Cursor MCP backup (copy to `.cursor/mcp.json` if needed) |
| `GET /mta/tools.json` | Machine-readable tool list for other integrations |

**Cursor setup:** Global `~/.cursor/mcp.json` (primary) or copy [`.cursor/mcp.json.local`](.cursor/mcp.json.local) → `.cursor/mcp.json` — reload MCP in Settings after changes.

**Other MCP clients:** same command/args as Cursor; see [Phase 3](#phase-3--connect-your-ai-tool).

**MCP tools:**

| Tool | Purpose |
|---|---|
| `mta_health` | Middleware + MTA status, online players, feature list |
| `mta_list_features` | All registered features |
| `mta_run_feature` | Run any feature by id + params |
| `mta_restart_agent`, `mta_restart_middleware`, `mta_restart_all` | Restart services (`ALLOW_RESTART=1`) |
| `mta_system_status` | Middleware status + restart policy (feature: `system.status`) |
| `mta_teleport_player`, `mta_eval_client`, `mta_debug_list`, `mta_gui_scan`, … | One tool per feature (auto-generated from `listFeatures()`) |

**Player resolution** (when `player` / `serial` omitted):

1. `serial` in request body
2. `AGENT_PLAYER_SERIAL` in `node/.env`
3. `session.defaultPlayerSerial` in Node memory
4. `player` name in request body
5. `AGENT_PLAYER` in `node/.env`
6. `session.defaultPlayer` in Node memory
7. Sole online player → error with `playerDetails` list if ambiguous

Pass `"serial": "<32-char-hex>"` on any feature or legacy route instead of `"player": "Name"`.

**Response envelope:** `{ ok, data, result }` on success; `{ ok: false, error, code, hint }` on failure.

**Agent rule:** If `mta-agent` MCP is not connected, **tell the user** before using HTTP/curl fallback.

### Simple features (HTTP fallback)

High-level integrations in `node/features/` — one call, no eval, async polling handled automatically.

```bash
# List all features
curl http://127.0.0.1:3847/mta/features

# Teleport to yourself (same as teleport to another player)
curl -X POST http://127.0.0.1:3847/mta/features/teleport.player \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"targetPlayer\":\"IIYAMA\"}"

# Get pizza (area search)
curl -X POST http://127.0.0.1:3847/mta/features/teleport.area \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"search\":\"pizza\"}"

# Closest airport (area category)
curl -X POST http://127.0.0.1:3847/mta/features/teleport.area \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"category\":\"airport\"}"

# What am I looking at? (auto-polls)
curl -X POST http://127.0.0.1:3847/mta/features/look.target \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"type\":\"vehicle\"}"
```

| Feature id | What it does |
|---|---|
| `teleport.player` | To another player (`targetPlayer`; same name = self-teleport) |
| `teleport.area` | To map area (`locationId`, `category`, `region`, `search`) |
| `teleport.element` | To closest element (`type`, `model`, `search`) |
| `teleport.lookTarget` | Beside whatever the player is looking at |
| `look.target` | Camera look target (polls async client query) |
| `nearby.closest` | Closest elements near player |
| `areas.closest` | Closest map area |
| `elements.track` | Register element in agent registry (by `mtaHandle` or nearest) |
| `elements.get` / `elements.list` / `elements.release` / `elements.modify` / `elements.resolve` | Registry CRUD |
| `elements.walk` | Walk element tree from root / resource / flat list |
| `gui.scan` | Client CEGUI scan — open windows, widget trees (async poll) |
| `gui.windows` | Lightweight open-window list |
| `debug.list` | Recent MTA debug messages (server sync; client/all async). Last 500, anti-dupe |
| `eval.server` | Server Lua via loadstring (**middleware HTTP gate:** `ALLOW_HTTP_EVAL=1`) |
| `eval.client` | Client Lua on a player (auto-polls; not gated by `ALLOW_HTTP_EVAL`) |
| `agent.restart` / `middleware.restart` / `system.restart` | Restart services (`ALLOW_RESTART=1`) |
| `system.status` | Middleware listen status + restart policy |

Add new features in `node/shared/features/*.js` via `registry.register(id, { description, params, run })`.

### ALLOW_HTTP_EVAL — middleware HTTP server-eval gate

`ALLOW_HTTP_EVAL` in `node/.env` controls **middleware HTTP / MCP only** (`:3847`) — not the MTA resource HTTP API (`:22005`).

| `ALLOW_HTTP_EVAL` | Effect |
|---|---|
| `0` (default) | Blocks middleware `POST /mta/eval` and MCP `eval.server` / `mta_eval_server` |
| `1` | Allows arbitrary **server-side** Lua via those middleware/MCP paths |

**Not gated:** `eval.client`, typed features (`teleport.*`, `gui.scan`, `debug.list`, `elements.*`, …). Direct MTA HTTP `POST /agent/call/eval` still works if the caller has MTA credentials — use typed features instead of raw server eval when possible.

---

### GUI scan — client windows (`gui.scan`)

Inspect what the player has open (CEGUI under `guiroot`). **Client must be connected** (reconnect after `restart agent`).

```bash
curl -X POST http://127.0.0.1:3847/mta/features/gui.scan \
  -H "Content-Type: application/json" \
  -d "{\"serial\":\"YOUR_SERIAL\",\"openOnly\":true,\"trees\":true}"
```

| Param | Default | Description |
|---|---|---|
| `player` / `serial` | auto | Target client |
| `windowTitle` | — | Filter by window title substring |
| `openOnly` | `true` | Visible/open windows only |
| `trees` | `true` | Include widget tree per window |
| `flat` | `false` | Flat element list instead of trees |

MCP: `mta_gui_scan` or `mta_run_feature` with `"feature": "gui.scan"`.

---

### Debug log fetch (`debug.list`)

Ring buffer of last **500** MTA debug lines ([`onDebugMessage`](https://wiki.multitheftauto.com/wiki/OnDebugMessage) server, [`onClientDebugMessage`](https://wiki.multitheftauto.com/wiki/OnClientDebugMessage) client). Consecutive duplicates collapse into one row with `repeatCount`.

```bash
# Server logs (sync)
curl -X POST http://127.0.0.1:3847/mta/features/debug.list \
  -H "Content-Type: application/json" \
  -d "{\"side\":\"server\",\"minLevel\":1,\"limit\":50}"

# Client logs (async poll — player/serial required)
curl -X POST http://127.0.0.1:3847/mta/do \
  -d "{\"feature\":\"debug.list\",\"serial\":\"YOUR_SERIAL\",\"side\":\"client\"}"
```

| Param | Description |
|---|---|
| `side` | `server` (default, sync), `client`, or `all` (async) |
| `minLevel` | `0` custom, `1` error, `2` warning, `3` info |
| `limit` | Max entries returned |
| `dedupe` | `true` (default) — collapse adjacent identical lines on merge |

MCP: `mta_debug_list`.

---

### Memory — which store to use

| Store | Scope | Persists |
|---|---|---|
| MTA in-memory | Game server session | Until resource restart |
| MTA SQLite `data/memory.db` | Game server | Yes |
| Node `node/data/memory.db` | Dev machine | Yes |

Use **Node memory** for agent session context (conversation state, task checklist). Use **MTA memory** for game-related state the server scripts need.

---

## findNearby — closest elements

Server-side helper in `shared/closest.lua`. Finds elements near a player and returns **type-specific properties**.

**GET** (query params) or **POST** (JSON body):

| Param | Description |
|---|---|
| `player` | Player name (optional; first online player if omitted) |
| `type` | Single type: `vehicle`, `player`, `ped`, `object`, `pickup`, `marker` |
| `types` | Array of types (POST only; overrides `type`) |
| `limit` | Max results, sorted by distance (default `1`) |
| `maxDistance` | Optional range filter |
| `perType` | `true` = closest match **per** type |
| `perTypeLimit` | Max per type when `perType=true` (default `1`) |

**Props returned by element type:**

| Type | Fields |
|---|---|
| `vehicle` | `model`, `name`, `plate`, `health`, `locked`, `engine`, `occupants`, `rotation` |
| `player` | `name`, `health`, `armor`, `ping`, `team`, `weapon`, `inVehicle`, `vehicle` |
| `ped` | `model`, `health`, `inVehicle` |
| `object` | `model`, `rotation` |
| `pickup` | `pickupType`, `amount`, `weapon` |
| `marker` | `markerType`, `size` |

All types include: `elementType`, `id`, `distance`, `position`, `dimension`, `interior`.

**Example:**

```bash
curl.exe -u USER:PASS "http://127.0.0.1:PORT/agent/api/nearby?player=PlayerName&type=vehicle&limit=1"
```

Via middleware:

```bash
curl.exe "http://127.0.0.1:3847/mta/nearby?player=PlayerName&type=vehicle&limit=1"
```

**Client eval note:** `evalClient`, `findVisible`, and `findLookTarget` are async (return an `id`). All require the player to have the `agent` resource loaded client-side (`triggerClientEvent` bridge). Use `findNearby` or server `eval` when client-side queries are unavailable.

**Distance vs look:** `findNearby` sorts by 3D distance from the player — it does **not** know view direction. `findLookTarget` uses `getCameraMatrix`, raycast, and [`isElementOnScreen`](https://wiki.multitheftauto.com/wiki/IsElementOnScreen) to return what the player is actually facing.

---

## findVisible — on-screen elements (client)

Client-side scan via `getVisibleElements` in `client/visible.lua`. Returns elements the player can see, with debug metadata.

**Requires** `agent` loaded on the player's client.

**POST** `/api/visible`:

```json
{
  "player": "PlayerName",
  "type": "vehicle",
  "limit": 25,
  "maxDistance": 200,
  "lineOfSight": true,
  "onlyVisible": true,
  "includeOffScreen": false,
  "debugLog": true
}
```

| Param | Default | Description |
|---|---|---|
| `onlyVisible` | `true` | Only elements with valid screen projection |
| `includeOffScreen` | `false` | Include streamed-in elements not on screen (debug) |
| `lineOfSight` | `false` | Filter by `isLineOfSightClear` from player |
| `debugLog` | `false` | Write each match to client `outputDebugString` (F8) |

Poll with `GET /api/visible/:id` until `status` is `complete`.

**Each element includes** the same type-specific props as `findNearby`, plus:

```json
"debug": {
  "visible": true,
  "onScreen": true,
  "streamedIn": true,
  "alpha": 255,
  "lineOfSight": true,
  "screen": {
    "onScreen": true,
    "normalized": { "x": 0.52, "y": 0.41 },
    "pixels": { "x": 665, "y": 295 }
  }
}
```

**Result payload** also includes `camera`, `viewport`, and `stats` (`scanned`, `streamedIn`, `onScreen`, `visible`, `returned`).

**Example:**

```bash
# Start query
curl.exe -u USER:PASS -X POST http://127.0.0.1:PORT/agent/api/visible \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"PlayerName\",\"type\":\"vehicle\",\"limit\":10,\"debugLog\":true}"

# Poll result
curl.exe -u USER:PASS http://127.0.0.1:PORT/agent/api/visible/fv-123456-1
```

---

## findLookTarget — what the player is looking at (client)

Uses `getLookTarget` in `client/visible.lua`. Combines:

1. **Raycast** — `processLineOfSight` from camera along view vector
2. **Screen-center fallback** — among elements where [`isElementOnScreen`](https://wiki.multitheftauto.com/wiki/IsElementOnScreen) is true, picks the one nearest screen center and within `maxCameraAngle`

Use this instead of `findNearby` when you need to know what the player is facing (e.g. a Beagle in view vs a Bandito behind them).

**Requires** `agent` loaded on the player's client.

**POST** `/api/look`:

```json
{
  "player": "PlayerName",
  "type": "vehicle",
  "maxDistance": 300,
  "screenCenterMax": 0.35,
  "maxCameraAngle": 25,
  "lineOfSight": false,
  "debugLog": true
}
```

| Param | Default | Description |
|---|---|---|
| `maxDistance` | `300` | Max range for raycast / candidates |
| `screenCenterMax` | `0.35` | Max normalized distance from screen center (0–0.5) |
| `maxCameraAngle` | `25` | Max angle (degrees) between camera forward and element |
| `lineOfSight` | `false` | Require clear LOS for screen-center picks |
| `debugLog` | `false` | Log pick to client F8 console |

Poll with `GET /api/look/:id` until `status` is `complete`.

**Result payload:**

```json
{
  "player": "IIYAMA",
  "origin": { "x": 0, "y": 0, "z": 0 },
  "camera": {
    "position": { "x": 0, "y": 0, "z": 0 },
    "lookAt": { "x": 0, "y": 0, "z": 0 },
    "forward": { "x": 0, "y": 0, "z": 0 },
    "viewport": { "width": 1280, "height": 720 }
  },
  "method": "screenCenter",
  "lookingAt": {
    "elementType": "vehicle",
    "id": "Beagle",
    "distance": 42.5,
    "debug": {
      "lookMethod": "screenCenter",
      "onScreen": true,
      "visible": true,
      "screen": { "centerDistance": 0.08 }
    }
  }
}
```

`method` is `"raycast"` when the camera ray hits an element, `"screenCenter"` when chosen from on-screen candidates, or `null` if nothing matched.

**Example:**

```bash
curl.exe -u USER:PASS -X POST http://127.0.0.1:PORT/agent/api/look \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"type\":\"vehicle\",\"debugLog\":true}"

curl.exe -u USER:PASS http://127.0.0.1:PORT/agent/api/look/lk-123456-1
```

Via middleware: `POST /mta/look`, `GET /mta/look/:id`

`findVisible` also includes `lookingAt` and `camera` in its result (same client logic).

---

## Area map — navigation across San Andreas

Built-in map of **170+** notable locations in `shared/locations.lua`. Each area has `id`, `name`, `category`, `region`, coordinates, and spawn rotation.

**Categories:** `airport`, `city`, `district`, `town`, `landmark`, `rural`, `military`, `waterfront`, `hospital`, `paynspray`, `police`, `ammu`, `gang`, `casino`, `service`, `mission`, `transport`, `entertainment`, `commercial`

**Regions:** Los Santos, San Fierro, Las Venturas, Red County, Flint County, Whetstone, Bone County, Tierra Robada

### listAreas / getAreaMap

```bash
# Full map with counts by category and region
curl.exe -u USER:PASS -X POST http://127.0.0.1:PORT/agent/call/getAreaMap -H "Content-Type: application/json" -d "[]"

# Filtered list
curl.exe -u USER:PASS -X POST http://127.0.0.1:PORT/agent/call/listAreas \
  -H "Content-Type: application/json" \
  -d "{\"category\":\"airport\"}"
```

| Filter | Description |
|---|---|
| `locationId` | Exact area id (e.g. `sf_easter_basin`) |
| `category` | One category (e.g. `landmark`, `airport`) |
| `region` | One region (e.g. `San Fierro`) |
| `search` | Substring match on id or name |

Legacy alias: `airportId` works like `locationId`.

### findClosestArea

Find the nearest matching area to a player's current position (does not teleport).

```bash
curl.exe -u USER:PASS -X POST http://127.0.0.1:PORT/agent/call/findClosestArea \
  -H "Content-Type: application/json" \
  -d "[\"IIYAMA\", {\"category\":\"waterfront\"}]"
```

### teleportToArea

Teleports the player (and occupied vehicle by default) to the closest matching area.

```bash
curl.exe -u USER:PASS -X POST http://127.0.0.1:PORT/agent/call/teleportToArea \
  -H "Content-Type: application/json" \
  -d "[\"IIYAMA\", {\"locationId\":\"sf_easter_basin\"}]"
```

| Option | Default | Description |
|---|---|---|
| `locationId` | — | Teleport to this exact area |
| `category` / `region` / `search` | — | Pick closest match when no `locationId` |
| `includeVehicle` | `true` | Move occupied vehicle with player |
| `rotation` | area default | Override spawn heading |
| `interior` / `dimension` | unchanged | Optional world state |

`teleportToClosestAirport` is a shortcut that sets `category: airport` (or uses `airportId` / `locationId`).

**Via middleware:**

```bash
curl http://127.0.0.1:3847/mta/areas/map
curl "http://127.0.0.1:3847/mta/areas?category=landmark&region=San%20Fierro"
curl "http://127.0.0.1:3847/mta/areas/closest?player=IIYAMA&category=airport"
curl -X POST http://127.0.0.1:3847/mta/teleport -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"locationId\":\"lv_strip\"}"
```

### teleportToElement / teleportToPlayer

Teleport a player to another **player** or **world element** (vehicle, ped, object, etc.).

**To another player:**

```bash
curl -X POST http://127.0.0.1:3847/mta/teleport/player \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"targetPlayer\":\"SomePlayer\"}"
```

**To closest matching element** (from the player's current position):

```bash
# Closest vehicle
curl -X POST http://127.0.0.1:3847/mta/teleport/element \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"type\":\"vehicle\"}"

# Closest Beagle (model 511)
curl -X POST http://127.0.0.1:3847/mta/teleport/element \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"type\":\"vehicle\",\"model\":511}"

# Closest vehicle named like "Beagle"
curl -X POST http://127.0.0.1:3847/mta/teleport/element \
  -H "Content-Type: application/json" \
  -d "{\"player\":\"IIYAMA\",\"type\":\"vehicle\",\"search\":\"Beagle\"}"
```

| Option | Default | Description |
|---|---|---|
| `targetPlayer` / `toPlayer` | — | Teleport to this online player |
| `type` / `elementType` | — | Find closest element of this type |
| `model` | — | Filter by element model id |
| `search` / `name` | — | Substring match on player name or vehicle name |
| `elementId` | — | Teleport to element with `setElementID` |
| `maxDistance` | unlimited | Max search radius for element lookup |
| `offsetDistance` | `2.5` | Stand this many meters behind target facing |
| `offset` | — | Explicit `{x,y,z}` offset from target position |
| `includeVehicle` | `true` | Move occupied vehicle with player |
| `matchWorld` | `true` | Copy target interior + dimension |

The player spawns slightly behind the target (not inside them). Interior and dimension follow the target automatically.

---

## Troubleshooting

Use this decision tree when something fails.

```
HTTP connection refused (port 22005)
  → MTA server not running, or wrong httpport in mtaserver.conf

401 / 403 on /agent/...
  → Wrong credentials, or user not in agent ACL group
  → Check `node/.env` has correct `MTA_USER` / `MTA_PASS` (no extra spaces/CRLF)
  → Restart Node middleware after editing `.env`
  → Check acl.xml: group "agent" must contain user.<name>
  → Right resource.agent.http must be true on ACL "Agent"

HTTP: bad login (no username in server log)
  → Authorization header missing or malformed — restart Node middleware
  → Ensure MTA_HOST is `127.0.0.1` (not `localhost`, which may resolve to ::1)
  → Run `npm run test:auth` in `node/` to verify credentials load correctly

HTTP: bad login (wrong password)
  → Password in `.env` does not match the MTA account
  → Ask user to reset: `chgpass <account> newpass` in MTA console, then update `.env`
  → Or generate HTTP pass: `authserial <account> httppass` and append the 7-digit code to the password

404 on /agent/call/...
  → Resource not started: run "start agent"
  → Wrong resource name in URL (must match folder name)

HTTP server file mismatch! (agent) *.lua [Got CRC:... same for every file]
  → Caused by `router="true"` on httpRouter intercepting client script downloads
  → agent resource must NOT use an HTTP router — use `/agent/call/<export>` instead
  → After fix: restart agent, disconnect/reconnect, or clear MTA client cache for the server

eval returns "HTTP only"
  → Call was not made via HTTP export (expected guard)

eval returns loadstring / permission error
  → Run: aclrequest allow agent all
  → Ask user to: restart agent
  → Confirm function.loadstring granted in autoACL_agent

HTTP only (legacy — fixed in resource)
  → Old versions checked the `user` global, which is not set in /call/ exports
  → Update to latest agent resource and ask user to restart agent

ACL install did not run
  → Delete data/lock-install, restart agent
  → Or apply acl/agent-acl-snippet.xml manually

Node /health shows mta fetch failed
  → MTA down, wrong MTA_HOST/PORT in .env, or ACL/auth issue

PowerShell curl fails
  → Use curl.exe explicitly, not curl (Invoke-WebRequest alias)
```

Always read `logs/server.log` and the in-game / server console output after `start agent`.

---

## Agent workflow after install

Once verified, use this loop to help the user:

1. **Discover** — `getServerState` or `GET /api/state` for players, resources, map
2. **Inspect** — `findNearby` for closest elements; `findLookTarget` for camera view; `findVisible` for all on-screen elements; `eval` for custom Lua
3. **Act** — `eval` or `callExport` to invoke existing resource APIs (prefer exports over raw eval when possible)
4. **Remember** — store task context in Node `/memory` or MTA `memorySet`
5. **Verify** — re-query state after changes

Prefer `callExport` over `eval` when the target resource already exposes a function.

---

## Files you may need to edit

| File | When |
|---|---|
| [server/installation_s.lua](server/installation_s.lua) | ACL install; reads `MTA_USER` from `node/.env` |
| [node/.env](node/.env) | MTA host, port, credentials (auto-created placeholder; gitignored) |
| [node/shared/load-env.js](node/shared/load-env.js) | Loads `node/.env` (+ auto-create from `.env.example`) |
| [server/main.lua](server/main.lua) | `Agent.PERSIST_MEMORY` toggle |
| [acl/agent-acl-snippet.xml](acl/agent-acl-snippet.xml) | Manual ACL setup |
| [mtaserver.conf](../../mtaserver.conf) | Auto-start resource (path relative to deathmatch root) |

---

## Security rules for agents

- `eval` is **remote code execution** on the game server. Warn the user before running destructive Lua.
- Do not expose HTTP credentials in public issues, commits, or community posts.
- Do not bind Node middleware to `0.0.0.0` unless the user explicitly needs LAN access and understands the risk.
- Do not disable HTTP auth or ACL checks as a “quick fix”.
- On shared/community servers, recommend a dedicated low-privilege HTTP account, not an admin account.

---

## Quick reference — project layout

```
agent/
├── AGENTS.md              ← you are here (agent onboarding playbook)
├── README.md
├── meta.xml
├── client/                ← eval, visible, bridge, gui_walker, debug_log, element_registry
├── shared/                ← eval, closest, locations, element_registry, element_walker, debug_log, player_resolve
├── server/                ← HTTP exports, teleport, memory, gui_scan, debug_log, element_registry
├── node/
│   ├── middleware/        ← HTTP server (npm start)
│   │   ├── index.js
│   │   ├── app.js
│   │   └── routes/
│   ├── mcp/               ← MCP stdio adapter (npm run mcp)
│   │   ├── index.js
│   │   ├── client.js      ← HTTP client → middleware
│   │   └── register-tools.js
│   ├── shared/            ← used by middleware + MCP
│   │   ├── config.js
│   │   ├── load-env.js    ← loads .env (+ auto-create from .env.example)
│   │   ├── credentials.js
│   │   ├── mta-client.js
│   │   ├── features/
│   │   └── lib/
│   ├── scripts/           ← ops CLI (restart-middleware, track-all-elements)
│   ├── test/              ← smoke tests (test-auth, verify-look, debug-log)
│   ├── experiments/       ← one-off probes (not production)
│   ├── index.js           ← shim → middleware
│   ├── mcp-server.js      ← shim → mcp
│   └── .env.example       ← auto-creates .env if missing (gitignored)
├── .cursor/
│   ├── mcp.json.local     ← Cursor MCP backup (global: ~/.cursor/mcp.json)
│   └── rules/             ← agent reminders (MCP reload, etc.)
└── acl/
    └── agent-acl-snippet.xml
```

When the user asks for help with this resource, **start with the [Agent playbook](#agent-playbook--guide-the-user-in-order)**, verify with `ping` or `GET /health`, then proceed with their task.
