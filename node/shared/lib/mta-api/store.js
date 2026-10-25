const fs = require("fs");
const path = require("path");

const DEFAULT_DB_PATH = path.join(__dirname, "../../../data/mta-api.db");
const SIDES = new Set(["client", "server", "shared"]);

let driver;

function sqliteDriver() {
  if (driver) return driver;
  try {
    const Database = require("better-sqlite3");
    const probe = new Database(":memory:");
    probe.close();
    driver = { kind: "better-sqlite3", open: (file, options) => new Database(file, options) };
  } catch (error) {
    const message = error && error.message ? error.message : "";
    const native =
      error &&
      (error.code === "ERR_DLOPEN_FAILED" ||
        message.includes("Could not locate the bindings file") ||
        message.includes("NODE_MODULE_VERSION"));
    if (!native) throw error;
    const { DatabaseSync } = require("node:sqlite");
    driver = {
      kind: "node:sqlite",
      open: (file, options) => new DatabaseSync(file, { readOnly: Boolean(options && options.readonly) }),
    };
  }
  return driver;
}

function openDatabase(file, options) {
  return sqliteDriver().open(file, options);
}

function withTransaction(db, fn) {
  if (typeof db.transaction === "function") {
    db.transaction(fn)();
    return;
  }
  db.exec("BEGIN");
  try {
    fn();
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

function emptySideCounts() {
  return { client: 0, server: 0, shared: 0 };
}

function rebuild(symbols, meta, dbPath = DEFAULT_DB_PATH) {
  const dir = path.dirname(dbPath);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${dbPath}.tmp`;
  fs.rmSync(tmp, { force: true });
  const db = openDatabase(tmp);
  try {
    db.exec("PRAGMA journal_mode = OFF");
    db.exec(`
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE TABLE symbols (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        side TEXT NOT NULL,
        file TEXT NOT NULL,
        line INTEGER NOT NULL,
        wiki TEXT,
        deprecated INTEGER NOT NULL DEFAULT 0,
        description TEXT
      );
      CREATE TABLE overloads (
        id INTEGER PRIMARY KEY,
        symbol_id INTEGER NOT NULL,
        side TEXT NOT NULL,
        label TEXT,
        params_json TEXT NOT NULL,
        returns_text TEXT,
        signature TEXT NOT NULL,
        FOREIGN KEY (symbol_id) REFERENCES symbols(id)
      );
      CREATE INDEX idx_symbols_name ON symbols(name COLLATE NOCASE);
      CREATE INDEX idx_overloads_symbol ON overloads(symbol_id);
    `);
    const insertMeta = db.prepare("INSERT INTO meta (key, value) VALUES (?, ?)");
    const insertSymbol = db.prepare(`
      INSERT INTO symbols (name, kind, side, file, line, wiki, deprecated, description)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const insertOverload = db.prepare(`
      INSERT INTO overloads (symbol_id, side, label, params_json, returns_text, signature)
      VALUES (?, ?, ?, ?, ?, ?)
    `);
    const write = () => {
      for (const [key, value] of Object.entries(meta)) {
        if (value === undefined || value === null) continue;
        insertMeta.run(key, String(value));
      }
      for (const symbol of symbols) {
        const info = insertSymbol.run(
          symbol.name,
          symbol.kind,
          symbol.side,
          symbol.file,
          symbol.line,
          symbol.wiki || null,
          symbol.deprecated ? 1 : 0,
          symbol.description || null
        );
        const symbolId = info.lastInsertRowid;
        for (const overload of symbol.overloads) {
          insertOverload.run(
            symbolId,
            overload.side,
            overload.label || null,
            JSON.stringify(overload.params || []),
            overload.returns || null,
            overload.signature
          );
        }
      }
    };
    withTransaction(db, write);
  } finally {
    db.close();
  }
  fs.rmSync(dbPath, { force: true });
  fs.renameSync(tmp, dbPath);
  return dbPath;
}

function openRead(dbPath = DEFAULT_DB_PATH) {
  if (!fs.existsSync(dbPath)) return null;
  return openDatabase(dbPath, { readonly: true, fileMustExist: true });
}

function readMeta(dbPath, key) {
  const db = openRead(dbPath);
  if (!db) return null;
  try {
    const row = db.prepare("SELECT value FROM meta WHERE key = ?").get(key);
    return row ? row.value : null;
  } finally {
    db.close();
  }
}

function sideCounts(db, table) {
  const counts = emptySideCounts();
  const rows = db.prepare(`SELECT side, COUNT(*) AS n FROM ${table} GROUP BY side`).all();
  for (const row of rows) {
    counts[row.side] = row.n;
  }
  return counts;
}

function summarize(dbPath = DEFAULT_DB_PATH) {
  const db = openRead(dbPath);
  if (!db) return null;
  try {
    const metaRows = db.prepare("SELECT key, value FROM meta").all();
    const meta = Object.fromEntries(metaRows.map((row) => [row.key, row.value]));
    return {
      commit: meta.commit || null,
      fetchedAt: meta.fetchedAt || null,
      sourceUrl: meta.sourceUrl || null,
      counts: sideCounts(db, "overloads"),
      symbols: sideCounts(db, "symbols"),
    };
  } finally {
    db.close();
  }
}

function normalizeSide(side) {
  if (side === undefined || side === null || side === "") return null;
  const value = String(side).trim().toLowerCase();
  if (!SIDES.has(value)) {
    const error = new Error("side must be client, server, or shared");
    error.status = 400;
    error.code = "MTA_API_SIDE";
    throw error;
  }
  return value;
}

function sideClause(side) {
  if (!side) return { sql: "", params: [] };
  if (side === "shared") return { sql: "AND o.side = ?", params: ["shared"] };
  return { sql: "AND (o.side = ? OR o.side = 'shared')", params: [side] };
}

function rowToOverload(row) {
  let params = [];
  try {
    params = JSON.parse(row.params_json);
  } catch {
    params = [];
  }
  return {
    side: row.overload_side,
    label: row.label || null,
    params,
    returns: row.returns_text || null,
    signature: row.signature,
  };
}

function groupMatches(rows) {
  const matches = [];
  const byId = new Map();
  for (const row of rows) {
    let match = byId.get(row.id);
    if (!match) {
      match = {
        name: row.name,
        kind: row.kind,
        side: row.side,
        file: row.file,
        line: row.line,
        wiki: row.wiki || null,
        deprecated: row.deprecated === 1,
        description: row.description || null,
        overloads: [],
      };
      byId.set(row.id, match);
      matches.push(match);
    }
    match.overloads.push(rowToOverload(row));
  }
  return matches;
}

const MATCH_COLUMNS = `
  s.id, s.name, s.kind, s.side, s.file, s.line, s.wiki, s.deprecated, s.description,
  o.side AS overload_side, o.label, o.params_json, o.returns_text, o.signature
`;

function query(dbPath, { name, side, limit } = {}) {
  const wanted = String(name || "").trim();
  if (!wanted) {
    const error = new Error("name is required");
    error.status = 400;
    error.code = "MTA_API_NAME";
    throw error;
  }
  const selectedSide = normalizeSide(side);
  const cap = Number.isFinite(Number(limit)) && Number(limit) > 0
    ? Math.min(Math.floor(Number(limit)), 100)
    : 20;
  const db = openRead(dbPath);
  if (!db) {
    const error = new Error("MTA API index is missing");
    error.status = 404;
    error.code = "MTA_API_MISSING";
    throw error;
  }
  try {
    const filter = sideClause(selectedSide);
    const exactNames = db
      .prepare("SELECT COUNT(*) AS n FROM symbols WHERE name = ? COLLATE NOCASE")
      .get(wanted).n;
    let rows;
    let exact = true;
    if (exactNames > 0) {
      rows = db
        .prepare(
          `SELECT ${MATCH_COLUMNS}
           FROM symbols s
           JOIN overloads o ON o.symbol_id = s.id
           WHERE s.name = ? COLLATE NOCASE
           ${filter.sql}
           ORDER BY s.file, s.line, o.id`
        )
        .all(wanted, ...filter.params);
    } else {
      exact = false;
      const prefix = `${wanted}%`;
      const like = `%${wanted}%`;
      const ids = db
        .prepare(
          `SELECT id FROM symbols
           WHERE name LIKE ? COLLATE NOCASE
           ORDER BY CASE
             WHEN name LIKE ? COLLATE NOCASE THEN 0
             ELSE 1
           END, length(name), name
           LIMIT ?`
        )
        .all(like, prefix, cap);
      if (!ids.length) {
        rows = [];
      } else {
        const placeholders = ids.map(() => "?").join(", ");
        rows = db
          .prepare(
            `SELECT ${MATCH_COLUMNS}
             FROM symbols s
             JOIN overloads o ON o.symbol_id = s.id
             WHERE s.id IN (${placeholders})
             ${filter.sql}
             ORDER BY length(s.name), s.name, s.file, o.id`
          )
          .all(...ids.map((row) => row.id), ...filter.params);
      }
    }
    const matches = groupMatches(rows);
    const result = {
      name: wanted,
      side: selectedSide,
      exact,
      matches,
    };
    if (matches.some((match) => match.name.toLowerCase() === "addeventhandler")) {
      const eventSql = selectedSide === "shared"
        ? "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'event' AND side = 'shared'"
        : selectedSide
          ? "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'event' AND (side = ? OR side = 'shared')"
          : "SELECT COUNT(*) AS n FROM symbols WHERE kind = 'event'";
      const eventParams = selectedSide && selectedSide !== "shared" ? [selectedSide] : [];
      result.eventCount = db.prepare(eventSql).get(...eventParams).n;
    }
    return result;
  } finally {
    db.close();
  }
}

module.exports = {
  DEFAULT_DB_PATH,
  rebuild,
  readMeta,
  summarize,
  query,
};
