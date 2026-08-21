"use strict";

const path = require("path");
const { PNG } = require("pngjs");
const jpeg = require("jpeg-js");

/**
 * Decode PNG file bytes to BGRA8 Buffer and size (resized/padded later if needed).
 * @param {Buffer} pngBuffer
 * @returns {{ pixels: Buffer, width: number, height: number }}
 */
function decodePngToBgra(pngBuffer) {
  const png = PNG.sync.read(pngBuffer);
  const { width, height, data } = png;
  const pixels = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const s = i * 4;
    const d = i * 4;
    pixels[d] = data[s + 2]; // B
    pixels[d + 1] = data[s + 1]; // G
    pixels[d + 2] = data[s]; // R
    pixels[d + 3] = data[s + 3]; // A
  }
  return { pixels, width, height };
}

/**
 * Decode JPEG file bytes to BGRA8 (alpha always 255).
 * @param {Buffer} jpegBuffer
 * @returns {{ pixels: Buffer, width: number, height: number }}
 */
function decodeJpegToBgra(jpegBuffer) {
  const decoded = jpeg.decode(jpegBuffer, { useTArray: true, formatAsRGBA: true });
  const { width, height, data } = decoded;
  const pixels = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const s = i * 4;
    const d = i * 4;
    pixels[d] = data[s + 2];
    pixels[d + 1] = data[s + 1];
    pixels[d + 2] = data[s];
    pixels[d + 3] = 255;
  }
  return { pixels, width, height };
}

function isPngMagic(buf) {
  return (
    buf.length >= 8 &&
    buf[0] === 0x89 &&
    buf[1] === 0x50 &&
    buf[2] === 0x4e &&
    buf[3] === 0x47
  );
}

function isJpegMagic(buf) {
  return buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
}

/**
 * Decode PNG or JPEG by magic bytes (fallback: file extension).
 * @param {Buffer} buffer
 * @param {string} [filePath]
 * @returns {{ pixels: Buffer, width: number, height: number, format: "png"|"jpeg" }}
 */
function decodeImageToBgra(buffer, filePath) {
  const ext = filePath ? path.extname(filePath).toLowerCase() : "";
  if (isPngMagic(buffer) || ext === ".png") {
    const decoded = decodePngToBgra(buffer);
    return { ...decoded, format: "png" };
  }
  if (isJpegMagic(buffer) || ext === ".jpg" || ext === ".jpeg") {
    const decoded = decodeJpegToBgra(buffer);
    return { ...decoded, format: "jpeg" };
  }
  throw new Error(
    `Unsupported image format${filePath ? ` (${path.basename(filePath)})` : ""} — use PNG or JPG`
  );
}

/**
 * Encode BGRA to PNG (RGBA).
 * @param {Buffer} bgra
 * @param {number} width
 * @param {number} height
 * @returns {Buffer}
 */
function encodeBgraToPng(bgra, width, height) {
  const png = new PNG({ width, height });
  for (let i = 0; i < width * height; i++) {
    const s = i * 4;
    const d = i * 4;
    png.data[d] = bgra[s + 2];
    png.data[d + 1] = bgra[s + 1];
    png.data[d + 2] = bgra[s];
    png.data[d + 3] = bgra[s + 3];
  }
  return PNG.sync.write(png);
}

/**
 * Nearest-neighbor resize / pad-crop to square size.
 * @param {Buffer} pixels
 * @param {number} srcW
 * @param {number} srcH
 * @param {number} size
 * @returns {Buffer}
 */
function resizeBgraNearest(pixels, srcW, srcH, size) {
  const out = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    const sy = Math.min(srcH - 1, Math.floor((y * srcH) / size));
    for (let x = 0; x < size; x++) {
      const sx = Math.min(srcW - 1, Math.floor((x * srcW) / size));
      const si = (sy * srcW + sx) * 4;
      const di = (y * size + x) * 4;
      out[di] = pixels[si];
      out[di + 1] = pixels[si + 1];
      out[di + 2] = pixels[si + 2];
      out[di + 3] = pixels[si + 3];
    }
  }
  return out;
}

/**
 * Solid color BGRA texture.
 * @param {number} size
 * @param {{ r: number, g: number, b: number, a?: number }} color
 * @returns {Buffer}
 */
function solidBgra(size, color) {
  const r = color.r & 0xff;
  const g = color.g & 0xff;
  const b = color.b & 0xff;
  const a = color.a != null ? color.a & 0xff : 255;
  const out = Buffer.alloc(size * size * 4);
  for (let i = 0; i < size * size; i++) {
    const d = i * 4;
    out[d] = b;
    out[d + 1] = g;
    out[d + 2] = r;
    out[d + 3] = a;
  }
  return out;
}

module.exports = {
  decodePngToBgra,
  decodeJpegToBgra,
  decodeImageToBgra,
  encodeBgraToPng,
  resizeBgraNearest,
  solidBgra,
};
