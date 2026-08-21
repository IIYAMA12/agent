"use strict";

function to565(r, g, b) {
  const r5 = Math.min(31, Math.max(0, Math.round((r * 31) / 255)));
  const g6 = Math.min(63, Math.max(0, Math.round((g * 63) / 255)));
  const b5 = Math.min(31, Math.max(0, Math.round((b * 31) / 255)));
  return (r5 << 11) | (g6 << 5) | b5;
}

function from565(c) {
  const r5 = (c >> 11) & 31;
  const g6 = (c >> 5) & 63;
  const b5 = c & 31;
  return [
    Math.round((r5 * 255) / 31),
    Math.round((g6 * 255) / 63),
    Math.round((b5 * 255) / 31),
  ];
}

function dist2(r1, g1, b1, r2, g2, b2) {
  const dr = r1 - r2;
  const dg = g1 - g2;
  const db = b1 - b2;
  return dr * dr + dg * dg + db * db;
}

function lerpByte(a, b, num, den) {
  return Math.round((a * (den - num) + b * num) / den);
}

function encodeBlock(pixels, base, rowStride) {
  const rs = new Array(16);
  const gs = new Array(16);
  const bs = new Array(16);
  let minL = Infinity;
  let maxL = -Infinity;
  let minI = 0;
  let maxI = 0;

  for (let y = 0; y < 4; y++) {
    const row = base + y * rowStride;
    for (let x = 0; x < 4; x++) {
      const i = y * 4 + x;
      const p = row + x * 4;
      const b = pixels[p] || 0;
      const g = pixels[p + 1] || 0;
      const r = pixels[p + 2] || 0;
      rs[i] = r;
      gs[i] = g;
      bs[i] = b;
      const lum = r * 2 + g * 3 + b;
      if (lum < minL) {
        minL = lum;
        minI = i;
      }
      if (lum > maxL) {
        maxL = lum;
        maxI = i;
      }
    }
  }

  let c0 = to565(rs[maxI], gs[maxI], bs[maxI]);
  let c1 = to565(rs[minI], gs[minI], bs[minI]);
  if (c0 < c1) {
    const tmp = c0;
    c0 = c1;
    c1 = tmp;
  } else if (c0 === c1) {
    if (c0 < 0xffff) c0 += 1;
    else c1 -= 1;
  }

  const [r0, g0, b0] = from565(c0);
  const [r1, g1, b1] = from565(c1);
  const palette = [
    [r0, g0, b0],
    [r1, g1, b1],
    [lerpByte(r0, r1, 1, 3), lerpByte(g0, g1, 1, 3), lerpByte(b0, b1, 1, 3)],
    [lerpByte(r0, r1, 2, 3), lerpByte(g0, g1, 2, 3), lerpByte(b0, b1, 2, 3)],
  ];

  let bits = 0;
  let bitPos = 0;
  for (let i = 0; i < 16; i++) {
    let best = 0;
    let bestD = Infinity;
    for (let p = 0; p < 4; p++) {
      const d = dist2(rs[i], gs[i], bs[i], palette[p][0], palette[p][1], palette[p][2]);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    bits += best * 2 ** bitPos;
    bitPos += 2;
  }

  const out = Buffer.alloc(8);
  out.writeUInt16LE(c0, 0);
  out.writeUInt16LE(c1, 2);
  out.writeUInt32LE(bits >>> 0, 4);
  return out;
}

/**
 * @param {Buffer} pixels BGRA8
 * @param {number} size width/height (power of two, multiple of 4)
 * @returns {Buffer}
 */
function bgraToDxt1(pixels, size) {
  if (size % 4 !== 0) {
    throw new Error("size must be multiple of 4 for DXT1");
  }
  const expected = size * size * 4;
  if (pixels.length < expected) {
    throw new Error("pixel buffer too short");
  }

  const blocks = [];
  const rowStride = size * 4;
  for (let by = 0; by < size; by += 4) {
    for (let bx = 0; bx < size; bx += 4) {
      const base = by * rowStride + bx * 4;
      blocks.push(encodeBlock(pixels, base, rowStride));
    }
  }
  return Buffer.concat(blocks);
}

module.exports = { bgraToDxt1 };
