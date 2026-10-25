const fs = require("fs");
const path = require("path");

const SKIP_DIRS = new Set(["scripts", "images", "node_modules"]);
const MAX_UNION = 12;
const MAX_SIGNATURE = 2000;

function fileSide(filePath) {
  const name = String(filePath).replace(/\\/g, "/");
  if (name.includes("__client_")) return "client";
  if (name.includes("__server_")) return "server";
  if (name.includes("__dx_") || name.includes("__gui_") || name.includes("__engine_")) return "client";
  return "shared";
}

function sideFromLabel(label, fallback) {
  if (label) {
    const client = label.includes("_client");
    const server = label.includes("_server");
    if (client && !server) return "client";
    if (server && !client) return "server";
  }
  return fallback;
}

function splitTopLevel(input, sep) {
  const parts = [];
  let depth = 0;
  let quote = null;
  let start = 0;
  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (quote) {
      if (ch === "\\") {
        i += 1;
        continue;
      }
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (ch === "(" || ch === "{" || ch === "[") depth += 1;
    else if (ch === ")" || ch === "}" || ch === "]") depth -= 1;
    else if (ch === sep && depth === 0) {
      parts.push(input.slice(start, i).trim());
      start = i + 1;
    }
  }
  if (start <= input.length) parts.push(input.slice(start).trim());
  return parts.filter(Boolean);
}

function findMatchingParen(text, openIndex) {
  let depth = 0;
  let quote = null;
  for (let i = openIndex; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      if (ch === "\\") {
        i += 1;
        continue;
      }
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (ch === "(") depth += 1;
    else if (ch === ")") {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function unwrapParens(spec) {
  let text = spec.trim();
  while (text.startsWith("(")) {
    const close = findMatchingParen(text, 0);
    if (close !== text.length - 1) break;
    text = text.slice(1, -1).trim();
  }
  return text;
}

function stripReturns(spec) {
  return spec.replace(/\s+Returns\b[\s\S]*$/, "").trim();
}

function isIdent(text) {
  return /^[A-Za-z_]\w*$/.test(text);
}

function parseFun(spec) {
  const open = spec.indexOf("(");
  if (!spec.startsWith("fun(") || open < 0) return null;
  const close = findMatchingParen(spec, open);
  if (close < 0) return null;
  const paramsRaw = spec.slice(open + 1, close);
  const after = spec.slice(close + 1).trim();
  let returnType = null;
  if (after.startsWith(":")) {
    returnType = stripReturns(after.slice(1).trim()) || null;
  }
  const params = [];
  for (const part of splitTopLevel(paramsRaw, ",")) {
    const named = splitNameType(part);
    if (!named) {
      if (part) params.push({ name: null, type: part, optional: false });
      continue;
    }
    params.push(named);
  }
  return { params, returnType };
}

function splitNameType(part) {
  let depth = 0;
  let quote = null;
  for (let i = 0; i < part.length; i++) {
    const ch = part[i];
    if (quote) {
      if (ch === "\\") {
        i += 1;
        continue;
      }
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (ch === "(" || ch === "{" || ch === "[") depth += 1;
    else if (ch === ")" || ch === "}" || ch === "]") depth -= 1;
    else if (ch === ":" && depth === 0) {
      const rawName = part.slice(0, i).trim();
      const type = part.slice(i + 1).trim();
      if (rawName === "..." || rawName === "...?") {
        return { name: "...", type: type || "any", optional: true };
      }
      const optional = rawName.endsWith("?");
      const name = optional ? rawName.slice(0, -1).trim() : rawName;
      return { name: name || null, type, optional };
    }
  }
  return null;
}

function formatSignature(params, returnType) {
  const rendered = params
    .map((param) => {
      const name = param.name || "_";
      const opt = param.optional ? "?" : "";
      return `${name}${opt}: ${param.type}`;
    })
    .join(", ");
  return `fun(${rendered})${returnType ? `: ${returnType}` : ""}`;
}

function eventLiteral(params) {
  const first = params[0];
  if (!first || first.name !== "eventName") return null;
  const match = String(first.type).trim().match(/^"([^"]+)"$/);
  return match ? match[1] : null;
}

function collectOverloads(spec, label, fallbackSide, resolveAlias, stack) {
  const side = sideFromLabel(label, fallbackSide);
  const cleaned = stripReturns(spec.trim());
  const unwrapped = unwrapParens(cleaned);
  if (unwrapped.startsWith("fun(")) {
    const parsed = parseFun(unwrapped);
    if (!parsed) {
      return { overloads: [], truncated: false };
    }
    return {
      overloads: [
        {
          label: label || null,
          side,
          params: parsed.params,
          returns: parsed.returnType,
          signature: formatSignature(parsed.params, parsed.returnType),
        },
      ],
      truncated: false,
    };
  }

  if (isIdent(unwrapped)) {
    if (stack.has(unwrapped)) return { overloads: [], truncated: false };
    const alias = resolveAlias(unwrapped);
    if (!alias) {
      return {
        overloads: [
          {
            label: unwrapped,
            side: sideFromLabel(unwrapped, side),
            params: [],
            returns: null,
            signature: unwrapped,
          },
        ],
        truncated: false,
      };
    }
    stack.add(unwrapped);
    const inner = collectOverloads(
      alias.spec,
      unwrapped,
      sideFromLabel(unwrapped, side),
      resolveAlias,
      stack
    );
    stack.delete(unwrapped);
    return inner;
  }

  const parts = splitTopLevel(cleaned, "|");
  if (parts.length > MAX_UNION) {
    return { overloads: [], truncated: true, count: parts.length };
  }
  if (parts.length > 1) {
    const overloads = [];
    for (const part of parts) {
      const inner = collectOverloads(part, null, side, resolveAlias, stack);
      if (inner.truncated) {
        return { overloads: [], truncated: true, count: inner.count || parts.length };
      }
      overloads.push(...inner.overloads);
      if (overloads.length > MAX_UNION) {
        return { overloads: [], truncated: true, count: overloads.length };
      }
    }
    return { overloads, truncated: false };
  }

  return {
    overloads: [
      {
        label: label || null,
        side,
        params: [],
        returns: null,
        signature: truncate(cleaned),
      },
    ],
    truncated: false,
  };
}

function truncate(text) {
  if (text.length <= MAX_SIGNATURE) return text;
  return `${text.slice(0, MAX_SIGNATURE)}…`;
}

function listLuaFiles(root) {
  const files = [];
  function walk(dir) {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith(".")) continue;
      if (SKIP_DIRS.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (entry.isFile() && entry.name.endsWith(".lua")) files.push(full);
    }
  }
  walk(root);
  return files.sort((a, b) => a.localeCompare(b));
}

function readLines(file) {
  return fs.readFileSync(file, "utf8").split(/\r?\n/);
}

function aliasAt(line) {
  const match = line.match(/^---@alias\s+([A-Za-z_]\w*)\s+([\s\S]+)$/);
  if (!match) return null;
  return { name: match[1], spec: match[2].trim() };
}

function functionAt(line) {
  const match = line.match(/^function\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*end\s*$/);
  return match ? match[1] : null;
}

function firstWiki(text) {
  const match = text.match(/\[Wiki\]\((https?:\/\/[^)\s]+)\)/);
  return match ? match[1] : null;
}

function wikiAbove(lines, index) {
  for (let i = index - 1; i >= Math.max(0, index - 40); i--) {
    const wiki = firstWiki(lines[i]);
    if (wiki) return wiki;
    const trimmed = lines[i].trim();
    if (trimmed.startsWith("---@alias") || trimmed.startsWith("function ")) break;
  }
  return null;
}

function returnsText(text) {
  const match = text.match(/\bReturns\b\s*([\s\S]*)$/);
  if (!match) return null;
  const value = match[1].replace(/\s+/g, " ").trim();
  return value ? value.slice(0, 500) : null;
}

function parseFile(file, root) {
  const lines = readLines(file);
  const rel = path.relative(root, file).replace(/\\/g, "/");
  const side = fileSide(rel);
  const aliases = [];
  const functions = [];
  const functionLines = [];

  for (let i = 0; i < lines.length; i++) {
    const alias = aliasAt(lines[i].trim());
    if (alias) {
      aliases.push({ ...alias, line: i + 1, text: lines[i] });
    }
    const name = functionAt(lines[i].trim());
    if (name) functionLines.push({ name, index: i });
  }

  for (let i = 0; i < functionLines.length; i++) {
    const current = functionLines[i];
    const start = i > 0 ? functionLines[i - 1].index + 1 : 0;
    const doc = lines.slice(start, current.index).join("\n");
    let typeSpec = null;
    for (let line = current.index - 1; line >= start; line--) {
      const trimmed = lines[line].trim();
      if (trimmed.startsWith("---@type")) {
        typeSpec = trimmed.replace(/^---@type\s+/, "").trim();
        break;
      }
    }
    functions.push({
      name: current.name,
      line: current.index + 1,
      doc,
      typeSpec,
      deprecated: /@deprecated\b/.test(doc),
      wiki: firstWiki(doc),
      description: returnsText(typeSpec || "") || returnsText(doc),
    });
  }

  return { file: rel, side, aliases, functions, lines };
}

function directFun(spec) {
  const unwrapped = unwrapParens(stripReturns(spec.trim()));
  return unwrapped.startsWith("fun(") ? unwrapped : null;
}

function parseTree(rootDir) {
  const root = path.resolve(rootDir);
  const parsed = listLuaFiles(root).map((file) => parseFile(file, root));
  const globalAliases = new Map();
  for (const file of parsed) {
    for (const alias of file.aliases) {
      if (!globalAliases.has(alias.name)) {
        globalAliases.set(alias.name, { spec: alias.spec, file: file.file });
      }
    }
  }

  const symbols = [];
  for (const file of parsed) {
    const localAliases = new Map(file.aliases.map((alias) => [alias.name, alias]));
    const resolveAlias = (name) => localAliases.get(name) || globalAliases.get(name) || null;

    for (const alias of file.aliases) {
      const funSpec = directFun(alias.spec);
      if (!funSpec) continue;
      const parsedFun = parseFun(funSpec);
      if (!parsedFun) continue;
      const eventName = eventLiteral(parsedFun.params);
      if (!eventName) continue;
      const lookback = file.lines.slice(Math.max(0, alias.line - 41), alias.line - 1).join("\n");
      symbols.push({
        name: eventName,
        kind: "event",
        side: file.side,
        file: file.file,
        line: alias.line,
        wiki: wikiAbove(file.lines, alias.line - 1),
        deprecated: /@deprecated\b/.test(lookback),
        description: returnsText(alias.spec),
        overloads: [
          {
            label: alias.name,
            side: file.side,
            params: parsedFun.params,
            returns: parsedFun.returnType,
            signature: formatSignature(parsedFun.params, parsedFun.returnType),
          },
        ],
      });
    }

    for (const fn of file.functions) {
      const resolved = fn.typeSpec
        ? collectOverloads(fn.typeSpec, null, file.side, resolveAlias, new Set())
        : { overloads: [], truncated: false };
      let overloads = resolved.overloads;
      let description = fn.description;
      if (resolved.truncated) {
        description = `Unexpanded union of ${resolved.count || "many"} signatures. Look up the event name or a specific overload alias.`;
        overloads = [
          {
            label: null,
            side: file.side,
            params: [],
            returns: null,
            signature: truncate(stripReturns(fn.typeSpec || "")),
          },
        ];
      } else if (!overloads.length) {
        overloads = [
          {
            label: null,
            side: file.side,
            params: [],
            returns: null,
            signature: fn.typeSpec ? truncate(stripReturns(fn.typeSpec)) : `${fn.name}()`,
          },
        ];
      }
      symbols.push({
        name: fn.name,
        kind: "function",
        side: file.side,
        file: file.file,
        line: fn.line,
        wiki: fn.wiki,
        deprecated: fn.deprecated,
        description,
        overloads,
      });
    }
  }

  return { symbols };
}

module.exports = {
  fileSide,
  parseTree,
  parseFun,
  formatSignature,
  MAX_UNION,
};
