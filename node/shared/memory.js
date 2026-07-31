const fs = require("fs");
const path = require("path");
const Database = require("better-sqlite3");

class MemoryStore {
  constructor(dbPath) {
    this.cache = new Map();
    this.dbPath = dbPath;
    this.db = null;
    this.initDb();
  }

  initDb() {
    const dir = path.dirname(this.dbPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    this.db = new Database(this.dbPath);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS memory (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    `);
  }

  get(key) {
    if (this.cache.has(key)) {
      return this.cache.get(key);
    }

    const row = this.db.prepare("SELECT value FROM memory WHERE key = ?").get(key);
    if (!row) {
      return null;
    }

    const value = JSON.parse(row.value);
    this.cache.set(key, value);
    return value;
  }

  set(key, value) {
    this.cache.set(key, value);
    this.db
      .prepare("INSERT OR REPLACE INTO memory (key, value, updated_at) VALUES (?, ?, ?)")
      .run(key, JSON.stringify(value), Date.now());
    return value;
  }

  delete(key) {
    this.cache.delete(key);
    this.db.prepare("DELETE FROM memory WHERE key = ?").run(key);
  }

  list(prefix = "") {
    const keys = new Set();

    for (const key of this.cache.keys()) {
      if (!prefix || key.startsWith(prefix)) {
        keys.add(key);
      }
    }

    const rows = prefix
      ? this.db.prepare("SELECT key FROM memory WHERE key LIKE ? ORDER BY key ASC").all(`${prefix}%`)
      : this.db.prepare("SELECT key FROM memory ORDER BY key ASC").all();

    for (const row of rows) {
      keys.add(row.key);
    }

    return Array.from(keys).sort();
  }
}

module.exports = { MemoryStore };
