const fs = require("fs");
const path = require("path");

const CAPTURES_DIR = path.resolve(path.join(__dirname, "../../../captures"));
const MAX_CAPTURES = 30;

function stamp() {
  const date = new Date();
  const pad = (value) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join("-") + `_${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
}

function safePlayerName(name) {
  const cleaned = String(name || "player")
    .replace(/[^A-Za-z0-9_-]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 32);
  return cleaned || "player";
}

function readSavedCapture(file) {
  const relative = String(file || "").replace(/\\/g, "/");
  if (!/^captures\/[^/]+\.jpg$/.test(relative)) {
    return null;
  }
  const absolute = path.join(CAPTURES_DIR, path.basename(relative));
  if (!fs.existsSync(absolute)) {
    return null;
  }
  return decodeJpeg(fs.readFileSync(absolute));
}

function decodeCapture(imageBase64) {
  if (typeof imageBase64 !== "string" || imageBase64.length === 0) {
    return null;
  }
  return decodeJpeg(Buffer.from(imageBase64, "base64"));
}

function decodeJpeg(image) {
  if (!image || image.length < 3 || image[0] !== 0xff || image[1] !== 0xd8) {
    return null;
  }
  return image;
}

function pruneCaptures(dir = CAPTURES_DIR, max = MAX_CAPTURES) {
  let names;
  try {
    names = fs.readdirSync(dir);
  } catch {
    return;
  }

  const files = [];
  for (const name of names) {
    if (!name.toLowerCase().endsWith(".jpg")) {
      continue;
    }
    const absolute = path.join(dir, name);
    let stat;
    try {
      stat = fs.statSync(absolute);
    } catch {
      continue;
    }
    if (!stat.isFile()) {
      continue;
    }
    files.push({ absolute, mtimeMs: stat.mtimeMs });
  }

  files.sort((a, b) => a.mtimeMs - b.mtimeMs || a.absolute.localeCompare(b.absolute));
  const extra = files.length - max;
  for (let i = 0; i < extra; i += 1) {
    try {
      fs.unlinkSync(files[i].absolute);
    } catch {
      // The next capture tries again.
    }
  }
}

function registerScreenFeatures(registry) {
  registry.register("screen.capture", {
    description:
      "Capture a player's current game view as a JPEG (async: takePlayerScreenShot, then poll onPlayerScreenShot). Includes the GTA HUD, dxDraw, and DGS. Excludes the chat box and CEGUI. The player must be connected, not minimized, and must allow screen uploads. Returns path (absolute JPEG) and file (captures/<timestamp>_<player>.jpg). Keeps the newest 30 shots.",
    params: {
      player: { optional: true },
      serial: { optional: true },
      width: { optional: true },
      height: { optional: true },
      quality: { optional: true },
      maxBandwidth: { optional: true },
    },
    async run(mta, params) {
      const { player, ...options } = params;
      const polled = await mta.screenCaptureComplete(player, options, { timeoutMs: 25000, intervalMs: 250 });
      const payload = polled?.result && (polled.result.file || polled.result.imageBase64) ? polled.result : polled;
      const fromFile = readSavedCapture(payload?.file);
      const image = fromFile || decodeCapture(payload?.imageBase64);
      if (!image) {
        const error = new Error("Screen capture returned no image");
        error.code = "SCREEN_CAPTURE_EMPTY";
        error.body = polled;
        throw error;
      }

      fs.mkdirSync(CAPTURES_DIR, { recursive: true });
      let relative = fromFile ? String(payload.file).replace(/\\/g, "/") : null;
      if (!relative) {
        const filename = `${stamp()}_${safePlayerName(payload.player)}.jpg`;
        fs.writeFileSync(path.join(CAPTURES_DIR, filename), image);
        relative = path.posix.join("captures", filename);
      }
      pruneCaptures();

      return {
        file: relative,
        path: path.join(CAPTURES_DIR, path.basename(relative)),
        player: payload.player || null,
        width: payload.width,
        height: payload.height,
        bytes: image.length,
      };
    },
  });
}

module.exports = { registerScreenFeatures };
