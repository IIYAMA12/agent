const { success, asyncRoute, failure } = require("../../shared/lib/respond");
const {
  getStatusSnapshot,
  refreshStatus,
  fetchPerformanceCategory,
  DEFAULT_POLL_MS,
} = require("../../shared/lib/status-cache");

function renderDashboardHtml(ctx) {
  const port = ctx.port;
  const host = ctx.host === "0.0.0.0" ? "127.0.0.1" : ctx.host;
  const baseUrl = `http://${host}:${port}`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>MTA Agent — Status</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0f1117;
      --panel: #171a22;
      --border: #2a2f3a;
      --text: #e6e9ef;
      --muted: #9aa3b2;
      --accent: #4c8bf5;
      --ok: #3ecf8e;
      --bad: #f07178;
      --warn: #e6b450;
      font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
    }
    .wrap {
      max-width: 100%;
      margin: 0 auto;
      padding: 24px 20px 40px;
    }
    .wrap-inner {
      max-width: 1400px;
      margin: 0 auto;
    }
    header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 20px;
    }
    h1 {
      margin: 0;
      font-size: 1.35rem;
      font-weight: 600;
    }
    .meta {
      color: var(--muted);
      font-size: 0.85rem;
    }
    .badges {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-bottom: 20px;
    }
    .badge {
      padding: 4px 10px;
      border-radius: 999px;
      font-size: 0.8rem;
      border: 1px solid var(--border);
      background: var(--panel);
    }
    .badge.ok { color: var(--ok); border-color: rgba(62, 207, 142, 0.35); }
    .badge.bad { color: var(--bad); border-color: rgba(240, 113, 120, 0.35); }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
      gap: 12px;
      margin-bottom: 20px;
    }
    .stat {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 14px 16px;
    }
    .stat .label {
      color: var(--muted);
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      margin-bottom: 6px;
    }
    .stat .value {
      font-size: 1.5rem;
      font-weight: 600;
      line-height: 1.1;
    }
    .stat .sub {
      color: var(--muted);
      font-size: 0.8rem;
      margin-top: 4px;
    }
    section {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 16px;
      margin-bottom: 16px;
    }
    section h2 {
      margin: 0 0 12px;
      font-size: 0.95rem;
      font-weight: 600;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.875rem;
    }
    th, td {
      text-align: left;
      padding: 8px 6px;
      border-bottom: 1px solid var(--border);
    }
    th { color: var(--muted); font-weight: 500; }
    tr:last-child td { border-bottom: none; }
    .empty {
      color: var(--muted);
      font-size: 0.875rem;
    }
    .errors {
      color: var(--bad);
      font-size: 0.85rem;
      white-space: pre-wrap;
    }
    footer {
      margin-top: 24px;
      color: var(--muted);
      font-size: 0.8rem;
      line-height: 1.5;
    }
    footer a { color: var(--accent); text-decoration: none; }
    footer a:hover { text-decoration: underline; }
    .cpu-bar {
      height: 6px;
      background: var(--border);
      border-radius: 3px;
      overflow: hidden;
      margin-top: 8px;
    }
    th.num, td.num { text-align: right; font-variant-numeric: tabular-nums; }
    .perf-bar {
      height: 6px;
      background: var(--border);
      border-radius: 3px;
      overflow: hidden;
      min-width: 80px;
    }
    .perf-bar > span {
      display: block;
      height: 100%;
      background: var(--accent);
    }
    .section-note {
      color: var(--muted);
      font-size: 0.8rem;
      margin: -4px 0 12px;
    }
    .perf-controls {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
      margin-bottom: 12px;
    }
    .perf-controls label {
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 0.85rem;
      color: var(--muted);
    }
    .perf-controls select,
    .perf-controls input {
      background: var(--bg);
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 6px 10px;
      font-size: 0.85rem;
    }
    .perf-controls input { min-width: 180px; }
    .perf-banner {
      background: #1a1d26;
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 8px 12px;
      font-size: 0.85rem;
      margin-bottom: 10px;
      color: var(--muted);
    }
    .perf-scroll {
      overflow-x: auto;
      border: 1px solid var(--border);
      border-radius: 8px;
    }
    .perf-table {
      width: max-content;
      min-width: 100%;
      font-size: 0.8rem;
    }
    .perf-table th, .perf-table td {
      white-space: nowrap;
      padding: 6px 10px;
    }
    .perf-table tbody tr:hover {
      background: rgba(255, 255, 255, 0.03);
    }
    .perf-table tr.totals td {
      font-weight: 600;
      border-top: 1px solid var(--border);
    }
    .tabs {
      display: flex;
      gap: 4px;
      margin: 18px 0 4px;
      border-bottom: 1px solid var(--border);
    }
    .tab {
      background: transparent;
      color: var(--muted);
      border: 1px solid transparent;
      border-bottom: none;
      border-radius: 6px 6px 0 0;
      padding: 8px 16px;
      font-size: 0.9rem;
      cursor: pointer;
    }
    .tab:hover { color: var(--text); }
    .tab.active {
      color: var(--text);
      background: var(--panel);
      border-color: var(--border);
    }
    .tab-panel { display: none; }
    .tab-panel.active { display: block; }
    .res-controls {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
      margin-bottom: 12px;
    }
    .res-controls input {
      background: var(--bg);
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 6px 10px;
      font-size: 0.85rem;
      min-width: 220px;
    }
    .res-scroll {
      max-height: 60vh;
      overflow: auto;
      border: 1px solid var(--border);
      border-radius: 8px;
    }
    .res-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.85rem;
    }
    .res-table th, .res-table td {
      text-align: left;
      padding: 8px 12px;
      border-bottom: 1px solid var(--border);
      white-space: nowrap;
    }
    .res-table th {
      position: sticky;
      top: 0;
      background: #1a1d26;
      z-index: 1;
    }
    .res-table tbody tr:hover { background: #1a1d26; }
    .res-table td.actions { display: flex; gap: 6px; }
    .state-pill {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 10px;
      font-size: 0.72rem;
      text-transform: capitalize;
      border: 1px solid var(--border);
    }
    .state-running { color: var(--ok); border-color: var(--ok); }
    .state-loaded { color: var(--muted); }
    .state-starting, .state-stopping { color: #e0b341; border-color: #e0b341; }
    .state-failed, .state-failed-to-load { color: var(--bad); border-color: var(--bad); }
    .btn {
      background: var(--bg);
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 4px 10px;
      font-size: 0.78rem;
      cursor: pointer;
    }
    .btn:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
    .btn:disabled { opacity: 0.4; cursor: not-allowed; }
    .btn.start:hover:not(:disabled) { border-color: var(--ok); color: var(--ok); }
    .btn.stop:hover:not(:disabled) { border-color: var(--bad); color: var(--bad); }
    .res-msg { font-size: 0.85rem; min-height: 1.2em; }
    .res-msg.ok { color: var(--ok); }
    .res-msg.bad { color: var(--bad); }
  </style>
</head>
<body>
  <div class="wrap">
  <div class="wrap-inner">
    <header>
      <h1>MTA Agent Status</h1>
      <div class="meta" id="updated">Loading…</div>
    </header>
    <div class="badges" id="badges"></div>
    <div class="grid" id="stats"></div>
    <nav class="tabs">
      <button class="tab active" data-tab="overview">Overview</button>
      <button class="tab" data-tab="resources">Resources</button>
    </nav>
    <div id="tab-overview" class="tab-panel active">
    <section>
      <h2>Players online</h2>
      <div id="players"></div>
    </section>
    <section>
      <h2>Resource summary</h2>
      <div id="resources"></div>
    </section>
    <section>
      <h2>Performance Browser</h2>
      <div class="perf-controls">
        <label>Category
          <select id="perf-category"></select>
        </label>
        <label>Filter
          <input id="perf-filter" type="text" placeholder="matches any column…" />
        </label>
      </div>
      <div class="perf-banner" id="perf-banner">Performance stats for: server</div>
      <div class="perf-scroll" id="perf-table-wrap">
        <div class="empty">Loading performance data…</div>
      </div>
    </section>
    <section id="cpu-section" hidden>
      <h2>CPU threads</h2>
      <div id="cpu"></div>
    </section>
    <section id="errors-section" hidden>
      <h2>Errors</h2>
      <div class="errors" id="errors"></div>
    </section>
    </div>
    <div id="tab-resources" class="tab-panel">
    <section>
      <h2>All resources</h2>
      <div class="res-controls">
        <input id="res-filter" type="text" placeholder="filter by name or state…" />
        <button class="btn" id="res-refresh">Refresh</button>
        <span class="meta" id="res-count"></span>
      </div>
      <div class="res-msg" id="res-msg"></div>
      <div class="res-scroll">
        <table class="res-table">
          <thead><tr><th>Resource</th><th>State</th><th>Actions</th></tr></thead>
          <tbody id="res-tbody"><tr><td colspan="3" class="empty">Loading…</td></tr></tbody>
        </table>
      </div>
    </section>
    </div>
    <footer>
      Auto-refreshes every ${Math.round(DEFAULT_POLL_MS / 1000)}s from cached middleware poll.
      JSON: <a href="${baseUrl}/api/status">${baseUrl}/api/status</a>
      · MCP resource: <code>mta://server/status</code>
    </footer>
  </div>
  </div>
  <script>
    const API = "${baseUrl}/api/status";
    const PERF_API = "${baseUrl}/api/status/performance";
    var perfState = {
      category: localStorage.getItem("mta-perf-category") || "Lua timing",
      filter: localStorage.getItem("mta-perf-filter") || "",
      tables: {},
      filteredCache: {},
      categories: [],
      filterTimer: null,
      loading: false,
      perfGen: 0,
    };
    var FILTERED_CACHE_MAX = 50;

    function badge(label, ok) {
      const el = document.createElement("span");
      el.className = "badge " + (ok ? "ok" : "bad");
      el.textContent = label + (ok ? " ✓" : " ✗");
      return el;
    }

    function stat(label, value, sub) {
      return '<div class="stat"><div class="label">' + label + '</div><div class="value">' + value + '</div>' +
        (sub ? '<div class="sub">' + sub + '</div>' : '') + '</div>';
    }

    function renderPlayers(players) {
      const box = document.getElementById("players");
      if (!players.length) {
        box.innerHTML = '<div class="empty">No players online</div>';
        return;
      }
      const rows = players.map(function (p) {
        return '<tr><td>' + esc(p.name) + '</td><td><code>' + esc(p.serial || "—") + '</code></td><td>' +
          (p.ping != null ? p.ping + " ms" : "—") + '</td></tr>';
      }).join("");
      box.innerHTML = '<table><thead><tr><th>Name</th><th>Serial</th><th>Ping</th></tr></thead><tbody>' +
        rows + '</tbody></table>';
    }

    function isNumericColumn(col) {
      return /^(5s|60s|300s)\.(cpu|time|calls|avg|max)$/.test(col) ||
        /^(change|current|max|refs|Timers|Elements|XMLFiles|OpenFiles|DB Queries|DB Connections)$/.test(col);
    }

    function cellValue(value) {
      if (value == null || value === "") return "—";
      return String(value);
    }

    function rowLabel(row, columns) {
      if (!row || !columns || !columns.length) return "";
      var nameCol = columns.find(function (col) {
        return /^name$/i.test(col) || /resource name/i.test(col);
      });
      if (nameCol && row[nameCol] != null && row[nameCol] !== "") {
        return String(row[nameCol]);
      }
      var first = columns[0];
      return first != null && row[first] != null ? String(row[first]) : "";
    }

    function rowMatchesFilter(row, columns, filter) {
      if (!filter) return true;
      var needle = filter.toLowerCase();
      for (var i = 0; i < columns.length; i++) {
        var col = columns[i];
        var value = row[col];
        if (value != null && String(value).toLowerCase().indexOf(needle) !== -1) {
          return true;
        }
      }
      return false;
    }

    function isTotalsRow(row, columns) {
      var label = rowLabel(row, columns).toLowerCase();
      return label.indexOf("totals") !== -1 || label.indexOf("vm totals") !== -1 ||
        label.indexOf("lib totals") !== -1 || label === " top";
    }

    function renderPerfTable(table) {
      const wrap = document.getElementById("perf-table-wrap");
      const banner = document.getElementById("perf-banner");
      const filter = (perfState.filter || "").trim();
      const filterKey = filter.toLowerCase();
      const category = perfState.category || "Lua timing";

      banner.textContent = "Performance stats for: server · " + category +
        (filter ? " · filter: " + filter : "") +
        (table ? " · " + (table.rowCount != null ? table.rowCount : (table.rows || []).length) + " rows" : "");

      if (!table || !table.columns || !table.columns.length) {
        wrap.innerHTML = '<div class="empty" style="padding:12px">No data for this category</div>';
        return;
      }

      var rows = table.rows || [];
      if (filterKey && !table.serverFiltered) {
        rows = rows.filter(function (row) {
          return rowMatchesFilter(row, table.columns, filterKey);
        });
      }

      var head = table.columns.map(function (col) {
        var cls = isNumericColumn(col) ? ' class="num"' : "";
        return "<th" + cls + ">" + esc(col) + "</th>";
      }).join("");

      var body = rows.map(function (row) {
        var trClass = isTotalsRow(row, table.columns) ? ' class="totals"' : "";
        var cells = table.columns.map(function (col) {
          var cls = isNumericColumn(col) ? ' class="num"' : "";
          return "<td" + cls + ">" + esc(cellValue(row[col])) + "</td>";
        }).join("");
        return "<tr" + trClass + ">" + cells + "</tr>";
      }).join("");

      if (!body) {
        wrap.innerHTML = '<div class="empty" style="padding:12px">No rows match filter</div>';
        return;
      }

      wrap.innerHTML = '<table class="perf-table"><thead><tr>' + head + '</tr></thead><tbody>' +
        body + '</tbody></table>';
    }

    function syncPerfControls() {
      var catSelect = document.getElementById("perf-category");
      var filterInput = document.getElementById("perf-filter");
      if (catSelect && perfState.categories.length) {
        catSelect.innerHTML = perfState.categories.map(function (c) {
          var sel = c === perfState.category ? " selected" : "";
          return '<option value="' + esc(c) + '"' + sel + ">" + esc(c) + "</option>";
        }).join("");
      }
      if (filterInput && filterInput.value !== perfState.filter) {
        filterInput.value = perfState.filter;
      }
    }

    async function ensurePerfTable(category, filter) {
      var filterText = (filter || "").trim();
      var cacheKey = category + "|" + filterText.toLowerCase();

      if (!filterText && perfState.tables[category]) {
        return perfState.tables[category];
      }
      if (perfState.filteredCache[cacheKey]) {
        return perfState.filteredCache[cacheKey];
      }

      var url = PERF_API + "?category=" + encodeURIComponent(category);
      if (filterText) {
        url += "&filter=" + encodeURIComponent(filterText);
      }
      var res = await fetch(url);
      var body = await res.json();
      if (!res.ok || body.ok === false) {
        throw new Error(body.error || "Failed to load performance data");
      }
      var payload = body.data || body.result || body;
      var table = {
        columns: payload.columns || [],
        rows: payload.rows || [],
        rowCount: payload.rowCount != null ? payload.rowCount : (payload.rows || []).length,
        serverFiltered: Boolean(filterText),
      };

      if (filterText) {
        var cacheKeys = Object.keys(perfState.filteredCache);
        if (cacheKeys.length >= FILTERED_CACHE_MAX) {
          delete perfState.filteredCache[cacheKeys[0]];
        }
        perfState.filteredCache[cacheKey] = table;
      } else {
        perfState.tables[category] = table;
      }
      return table;
    }

    async function refreshPerfView() {
      var gen = ++perfState.perfGen;
      try {
        var table = await ensurePerfTable(perfState.category, perfState.filter);
        if (gen !== perfState.perfGen) return; // a newer request superseded this one
        renderPerfTable(table);
      } catch (e) {
        if (gen !== perfState.perfGen) return;
        document.getElementById("perf-table-wrap").innerHTML =
          '<div class="empty" style="padding:12px">Failed to load: ' + esc(e.message) + "</div>";
      }
    }

    function schedulePerfRefresh(immediate) {
      if (perfState.filterTimer) {
        clearTimeout(perfState.filterTimer);
        perfState.filterTimer = null;
      }
      var filterText = (perfState.filter || "").trim();
      if (immediate || !filterText) {
        refreshPerfView();
        return;
      }
      var cached = perfState.tables[perfState.category];
      if (cached) {
        renderPerfTable(cached);
      }
      perfState.filterTimer = setTimeout(function () {
        perfState.filterTimer = null;
        refreshPerfView();
      }, 300);
    }

    function bindPerfControls() {
      var catSelect = document.getElementById("perf-category");
      var filterInput = document.getElementById("perf-filter");
      if (catSelect && !catSelect.dataset.bound) {
        catSelect.dataset.bound = "1";
        catSelect.addEventListener("change", function () {
          perfState.category = catSelect.value;
          localStorage.setItem("mta-perf-category", perfState.category);
          schedulePerfRefresh(true);
        });
      }
      if (filterInput && !filterInput.dataset.bound) {
        filterInput.dataset.bound = "1";
        filterInput.addEventListener("input", function () {
          perfState.filter = filterInput.value;
          localStorage.setItem("mta-perf-filter", perfState.filter);
          schedulePerfRefresh(false);
        });
      }
    }

    function ingestPerformance(data) {
      if (!data || !data.performance) return;
      perfState.categories = data.performance.categories || perfState.categories;
      var polled = data.performance.polled || [];
      var tables = data.performance.tables || {};
      polled.forEach(function (cat) {
        if (tables[cat]) perfState.tables[cat] = tables[cat];
      });
      perfState.filteredCache = {};
      if (perfState.categories.indexOf(perfState.category) === -1 && perfState.categories.length) {
        perfState.category = perfState.categories[0];
      }
      syncPerfControls();
      bindPerfControls();
      schedulePerfRefresh(true);
    }

    function renderResources(r) {
      const box = document.getElementById("resources");
      if (!r || !r.total) {
        box.innerHTML = '<div class="empty">Unavailable</div>';
        return;
      }
      box.innerHTML = '<div class="grid">' +
        stat("Running", r.running, "of " + (r.catalogTotal || r.total) + " total") +
        stat("Loaded", r.loaded, "not running") +
        stat("Starting", r.starting) +
        stat("Stopping", r.stopping) +
        stat("Failed", r.failed || 0) +
        '</div>';
    }

    function renderCpu(cpu) {
      const section = document.getElementById("cpu-section");
      const box = document.getElementById("cpu");
      if (!cpu || !cpu.threads || !cpu.threads.length) {
        section.hidden = true;
        return;
      }
      section.hidden = false;
      box.innerHTML = cpu.threads.map(function (t) {
        var pct = Math.min(100, (t.percent || 0) + (t.systemPercent || 0));
        return '<div style="margin-bottom:12px"><div style="display:flex;justify-content:space-between;font-size:0.85rem">' +
          '<span>' + esc(t.name) + '</span><span>' + pct.toFixed(1) + '%</span></div>' +
          '<div class="cpu-bar"><span style="width:' + pct + '%"></span></div></div>';
      }).join("");
    }

    function esc(s) {
      return String(s == null ? "" : s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
    }

    function render(data) {
      document.getElementById("updated").textContent = "Updated " + new Date(data.updatedAt).toLocaleString();

      const badges = document.getElementById("badges");
      badges.innerHTML = "";
      badges.appendChild(badge("Middleware", data.middleware && data.middleware.ok));
      const mtaOk = data.mta && (data.mta.ok === true || data.mta.resource === "agent");
      badges.appendChild(badge("MTA agent", mtaOk));

      const mem = data.health && data.health.memory;
      const cpu = data.health && data.health.cpu;
      var fpsLabel = "—";
      if (cpu && cpu.serverFps != null) {
        if (typeof cpu.serverFps === "object") {
          fpsLabel = cpu.serverFps.actual != null ? String(cpu.serverFps.actual) : (cpu.serverFps.raw || "—");
        } else {
          fpsLabel = String(cpu.serverFps);
        }
      }
      const luaTotal = cpu && cpu.lua && cpu.lua.total5sPercent;
      document.getElementById("stats").innerHTML =
        stat("Players", (data.players && data.players.count) || 0) +
        stat("RAM", mem && mem.residentMiB != null ? mem.residentMiB + " MiB" : "—", mem && mem.virtualMiB != null ? "virtual " + mem.virtualMiB + " MiB" : "") +
        stat("CPU", cpu && cpu.totalPercent != null ? cpu.totalPercent + "%" : "—", fpsLabel !== "—" ? "server FPS " + fpsLabel : "") +
        stat("Lua CPU", luaTotal != null ? luaTotal + "%" : "—", "5s total across resources");

      renderPlayers((data.players && data.players.online) || []);
      renderResources(data.resources);
      ingestPerformance(data);
      renderCpu(cpu);

      const errSection = document.getElementById("errors-section");
      const errs = data.errors || [];
      if (errs.length) {
        errSection.hidden = false;
        document.getElementById("errors").textContent = errs.map(function (e) {
          return (e.scope || "error") + ": " + e.message;
        }).join("\\n");
      } else {
        errSection.hidden = true;
      }
    }

    async function load() {
      try {
        const res = await fetch(API);
        const body = await res.json();
        if (!res.ok || (body && body.ok === false)) {
          document.getElementById("updated").textContent =
            "Failed to load: " + ((body && body.error) || ("HTTP " + res.status));
          return;
        }
        render(body.data || body);
      } catch (e) {
        document.getElementById("updated").textContent = "Failed to load: " + e.message;
      }
    }

    var RES_API = "${baseUrl}/api/status/resources";
    var STATE_ORDER = { running: 0, starting: 1, stopping: 2, loaded: 3, "failed to load": 4 };
    var resState = { all: [], filter: "", loaded: false, busy: {} };

    function stateClass(state) {
      return "state-" + String(state || "unknown").replace(/[^a-z0-9]+/gi, "-").toLowerCase();
    }

    function setResMsg(text, kind) {
      var el = document.getElementById("res-msg");
      if (!el) return;
      el.textContent = text || "";
      el.className = "res-msg" + (kind ? " " + kind : "");
    }

    function renderResList() {
      var tbody = document.getElementById("res-tbody");
      if (!tbody) return;
      var filter = (resState.filter || "").trim().toLowerCase();
      var rows = resState.all.filter(function (r) {
        if (!filter) return true;
        return (r.name || "").toLowerCase().indexOf(filter) !== -1 ||
          (r.state || "").toLowerCase().indexOf(filter) !== -1;
      });

      document.getElementById("res-count").textContent =
        rows.length + " of " + resState.all.length + " resources";

      if (!rows.length) {
        tbody.innerHTML = '<tr><td colspan="3" class="empty">' +
          (resState.loaded ? "No matching resources" : "Loading…") + '</td></tr>';
        return;
      }

      tbody.innerHTML = rows.map(function (r) {
        var running = r.state === "running";
        var isAgent = r.name === "agent";
        var busy = resState.busy[r.name];
        var dis = busy ? " disabled" : "";
        var startBtn = '<button class="btn start" data-action="start" data-res="' + esc(r.name) + '"' + (running || busy ? " disabled" : "") + '>Start</button>';
        var stopBtn = '<button class="btn stop" data-action="stop" data-res="' + esc(r.name) + '"' + ((!running || isAgent || busy) ? " disabled" : "") + '>Stop</button>';
        var restartBtn = '<button class="btn" data-action="restart" data-res="' + esc(r.name) + '"' + dis + '>Restart</button>';
        return '<tr><td>' + esc(r.name) + '</td>' +
          '<td><span class="state-pill ' + stateClass(r.state) + '">' + esc(r.state || "unknown") + '</span></td>' +
          '<td class="actions">' + startBtn + stopBtn + restartBtn + '</td></tr>';
      }).join("");
    }

    function sortResources(list) {
      return list.slice().sort(function (a, b) {
        var oa = STATE_ORDER[a.state] != null ? STATE_ORDER[a.state] : 99;
        var ob = STATE_ORDER[b.state] != null ? STATE_ORDER[b.state] : 99;
        if (oa !== ob) return oa - ob;
        return (a.name || "").localeCompare(b.name || "");
      });
    }

    async function loadResources() {
      try {
        var res = await fetch(RES_API);
        var body = await res.json();
        if (!res.ok || (body && body.ok === false)) {
          setResMsg("Failed to load resources: " + ((body && body.error) || ("HTTP " + res.status)), "bad");
          return;
        }
        var payload = body.data || body;
        resState.all = sortResources(payload.resources || []);
        resState.loaded = true;
        renderResList();
      } catch (e) {
        setResMsg("Failed to load resources: " + e.message, "bad");
      }
    }

    async function controlResource(action, resource) {
      resState.busy[resource] = true;
      renderResList();
      setResMsg(action + "ing " + resource + "…");
      try {
        var res = await fetch(RES_API + "/control", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: action, resource: resource }),
        });
        var body = await res.json();
        if (!res.ok || (body && body.ok === false)) {
          setResMsg((body && body.error) || ("Failed to " + action + " " + resource), "bad");
        } else {
          setResMsg(resource + ": " + action + " ok", "ok");
        }
      } catch (e) {
        setResMsg("Failed to " + action + " " + resource + ": " + e.message, "bad");
      } finally {
        delete resState.busy[resource];
        await loadResources();
        load();
      }
    }

    function bindResourceControls() {
      var tbody = document.getElementById("res-tbody");
      if (tbody && !tbody.dataset.bound) {
        tbody.dataset.bound = "1";
        tbody.addEventListener("click", function (e) {
          var btn = e.target.closest("button[data-action]");
          if (!btn || btn.disabled) return;
          controlResource(btn.dataset.action, btn.dataset.res);
        });
      }
      var filterInput = document.getElementById("res-filter");
      if (filterInput && !filterInput.dataset.bound) {
        filterInput.dataset.bound = "1";
        filterInput.addEventListener("input", function () {
          resState.filter = filterInput.value;
          renderResList();
        });
      }
      var refreshBtn = document.getElementById("res-refresh");
      if (refreshBtn && !refreshBtn.dataset.bound) {
        refreshBtn.dataset.bound = "1";
        refreshBtn.addEventListener("click", loadResources);
      }
    }

    function bindTabs() {
      var tabs = document.querySelectorAll(".tab");
      tabs.forEach(function (tab) {
        tab.addEventListener("click", function () {
          var name = tab.dataset.tab;
          tabs.forEach(function (t) { t.classList.toggle("active", t === tab); });
          document.querySelectorAll(".tab-panel").forEach(function (p) {
            p.classList.toggle("active", p.id === "tab-" + name);
          });
          if (name === "resources") {
            loadResources();
          }
        });
      });
    }

    bindTabs();
    bindResourceControls();
    load();
    setInterval(load, ${DEFAULT_POLL_MS});
  </script>
</body>
</html>`;
}

function registerStatusRoutes(app, ctx) {
  app.get(
    "/api/status",
    asyncRoute(async (_req, res) => {
      let data = getStatusSnapshot();
      if (!data) {
        data = await refreshStatus(ctx);
      }
      success(res, data);
    })
  );

  app.post(
    "/api/status/refresh",
    asyncRoute(async (_req, res) => {
      const data = await refreshStatus(ctx);
      success(res, data);
    })
  );

  app.get(
    "/api/status/performance",
    asyncRoute(async (req, res) => {
      const category = String(req.query.category || "").trim();
      if (!category) {
        return failure(res, { message: "category query parameter is required", code: "CATEGORY_REQUIRED" }, 400);
      }
      const table = await fetchPerformanceCategory(
        ctx,
        category,
        String(req.query.options || ""),
        String(req.query.filter || "")
      );
      success(res, { category, ...table });
    })
  );

  app.get(
    "/api/status/resources",
    asyncRoute(async (_req, res) => {
      let search = await ctx.mta.resourceSearch({ query: "", limit: 500 });
      let list = search?.resources || [];
      const matchedTotal = search?.matchedTotal ?? list.length;
      if (matchedTotal > list.length) {
        const full = await ctx.mta.resourceSearch({ query: "", limit: matchedTotal });
        if (Array.isArray(full?.resources) && full.resources.length >= list.length) {
          list = full.resources;
        }
      }
      success(res, { resources: list, total: search?.total ?? list.length });
    })
  );

  app.post(
    "/api/status/resources/control",
    asyncRoute(async (req, res) => {
      const action = String(req.body?.action || "").trim();
      const resource = String(req.body?.resource || "").trim();
      if (!resource) {
        return failure(res, { message: "resource is required", code: "RESOURCE_REQUIRED" }, 400);
      }
      if (!["start", "stop", "restart"].includes(action)) {
        return failure(res, { message: 'action must be "start", "stop", or "restart"', code: "BAD_ACTION" }, 400);
      }
      const result = await ctx.mta.resourceControl(action, resource);
      refreshStatus(ctx).catch(() => {});
      success(res, { action, resource, result });
    })
  );

  app.get("/dashboard", (_req, res) => {
    res.type("html").send(renderDashboardHtml(ctx));
  });
}

module.exports = { registerStatusRoutes, renderDashboardHtml };
