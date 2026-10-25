const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { parseTree } = require("./parse");
const { rebuild, readMeta, summarize, query, DEFAULT_DB_PATH } = require("./store");

const SOURCE_URL = "https://gitlab.com/IIYAMA12/mta-annotations-for-lua-language-server.git";
const BRANCH = "main";
const DEFAULT_CLONE_PATH = path.join(__dirname, "../../../data/mta-annotations");

let chain = Promise.resolve();

function gitError(args, error) {
  if (error.code === "ENOENT") {
    const missing = new Error("git was not found on PATH");
    missing.status = 500;
    missing.code = "MTA_API_GIT";
    return missing;
  }
  const stderr = error.stderr ? String(error.stderr).trim() : "";
  const wrapped = new Error(`git ${args.join(" ")} failed: ${stderr || error.message}`);
  wrapped.status = 500;
  wrapped.code = "MTA_API_GIT";
  return wrapped;
}

function git(args, cwd) {
  try {
    return execFileSync("git", args, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    }).trim();
  } catch (error) {
    throw gitError(args, error);
  }
}

function ensureClone(dir) {
  const gitDir = path.join(dir, ".git");
  if (!fs.existsSync(gitDir)) {
    if (fs.existsSync(dir) && fs.readdirSync(dir).length > 0) {
      const error = new Error(`Annotations path exists and is not a git clone: ${dir}`);
      error.status = 500;
      error.code = "MTA_API_GIT";
      throw error;
    }
    fs.mkdirSync(path.dirname(dir), { recursive: true });
    git(["clone", "--depth", "1", "--branch", BRANCH, SOURCE_URL, dir]);
    return;
  }
  git(["fetch", "--depth", "1", "origin", BRANCH], dir);
  git(["reset", "--hard", `origin/${BRANCH}`], dir);
}

function doSync({ force = false, clonePath = DEFAULT_CLONE_PATH, dbPath = DEFAULT_DB_PATH } = {}) {
  ensureClone(clonePath);
  const commit = git(["rev-parse", "HEAD"], clonePath);
  const previous = readMeta(dbPath, "commit");
  if (!force && previous && previous === commit && fs.existsSync(dbPath)) {
    return { rebuilt: false, ...summarize(dbPath) };
  }
  const { symbols } = parseTree(clonePath);
  const fetchedAt = new Date().toISOString();
  rebuild(
    symbols,
    {
      sourceUrl: SOURCE_URL,
      commit,
      fetchedAt,
    },
    dbPath
  );
  return { rebuilt: true, ...summarize(dbPath) };
}

function sync(options = {}) {
  const run = chain.then(() => doSync(options));
  chain = run.then(
    () => {},
    () => {}
  );
  return run;
}

async function lookup(options = {}) {
  const dbPath = options.dbPath || DEFAULT_DB_PATH;
  if (!fs.existsSync(dbPath)) {
    await sync({ clonePath: options.clonePath, dbPath });
  }
  return query(dbPath, options);
}

module.exports = {
  SOURCE_URL,
  BRANCH,
  DEFAULT_CLONE_PATH,
  sync,
  lookup,
};
