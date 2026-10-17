"use strict";

const FACE_UVS = [
  [0, 1],
  [1, 1],
  [1, 0],
  [0, 0],
];

function makePalette(color) {
  const [r, g, b] = color;
  return {
    top: [r, g, b],
    side: [
      Math.max(0, Math.floor(r * 0.85 + 0.5)),
      Math.max(0, Math.floor(g * 0.85 + 0.5)),
      Math.max(0, Math.floor(b * 0.85 + 0.5)),
    ],
    bottom: [
      Math.max(0, Math.floor(r * 0.55 + 0.5)),
      Math.max(0, Math.floor(g * 0.55 + 0.5)),
      Math.max(0, Math.floor(b * 0.55 + 0.5)),
    ],
  };
}

function face(texture, palette, n, c1, c2, c3, c4, uvs = FACE_UVS) {
  return {
    normal: n,
    corners: [c1, c2, c3, c4],
    texture,
    palette,
    uvs,
  };
}

function prismGeometry(sides, radius, hz, texture, color, drawTop = true, drawBottom = true) {
  const n = Math.max(3, Math.min(32, Math.floor(sides || 8)));
  const palette = makePalette(color);
  const quads = [];
  const step = (Math.PI * 2) / n;
  const verts = [];
  for (let i = 0; i < n; i++) {
    const angle = step * i - Math.PI / n;
    verts.push([Math.cos(angle) * radius, Math.sin(angle) * radius]);
  }

  for (let i = 0; i < n; i++) {
    const a = verts[i];
    const b = verts[(i + 1) % n];
    const midX = (a[0] + b[0]) * 0.5;
    const midY = (a[1] + b[1]) * 0.5;
    const len = Math.sqrt(midX * midX + midY * midY) || 1;
    const nx = midX / len;
    const ny = midY / len;
    quads.push(
      face(texture, palette, [nx, ny, 0], [a[0], a[1], -hz], [b[0], b[1], -hz], [b[0], b[1], hz], [a[0], a[1], hz])
    );
  }

  if (drawTop) {
    for (let i = 0; i < n; i++) {
      const a = verts[i];
      const b = verts[(i + 1) % n];
      quads.push(face(texture, palette, [0, 0, 1], [0, 0, hz], [a[0], a[1], hz], [b[0], b[1], hz], [0, 0, hz]));
    }
  }
  if (drawBottom) {
    for (let i = 0; i < n; i++) {
      const a = verts[i];
      const b = verts[(i + 1) % n];
      quads.push(
        face(texture, palette, [0, 0, -1], [0, 0, -hz], [b[0], b[1], -hz], [a[0], a[1], -hz], [0, 0, -hz])
      );
    }
  }

  const boxes = [{ min: [-radius, -radius, -hz], max: [radius, radius, hz] }];
  return { quads, boxes };
}

function boxGeometry(hx, hy, hz, texture, color, drawTop = true, drawBottom = true) {
  const palette = makePalette(color);
  const quads = [];
  if (drawTop) {
    quads.push(face(texture, palette, [0, 0, 1], [-hx, -hy, hz], [hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz]));
  }
  if (drawBottom) {
    quads.push(
      face(texture, palette, [0, 0, -1], [-hx, -hy, -hz], [-hx, hy, -hz], [hx, hy, -hz], [hx, -hy, -hz])
    );
  }
  quads.push(face(texture, palette, [0, -1, 0], [-hx, -hy, -hz], [hx, -hy, -hz], [hx, -hy, hz], [-hx, -hy, hz]));
  quads.push(face(texture, palette, [0, 1, 0], [hx, hy, -hz], [-hx, hy, -hz], [-hx, hy, hz], [hx, hy, hz]));
  quads.push(face(texture, palette, [-1, 0, 0], [-hx, hy, -hz], [-hx, -hy, -hz], [-hx, -hy, hz], [-hx, hy, hz]));
  quads.push(face(texture, palette, [1, 0, 0], [hx, -hy, -hz], [hx, hy, -hz], [hx, hy, hz], [hx, -hy, hz]));
  const boxes = [{ min: [-hx, -hy, -hz], max: [hx, hy, hz] }];
  return { quads, boxes };
}

function planeGeometry(hx, hy, texture, color) {
  const palette = makePalette(color);
  const quads = [
    face(texture, palette, [0, 0, 1], [-hx, -hy, 0], [hx, -hy, 0], [hx, hy, 0], [-hx, hy, 0]),
  ];
  const thickness = 0.05;
  const boxes = [{ min: [-hx, -hy, -thickness], max: [hx, hy, thickness] }];
  return { quads, boxes };
}

function clampInt(value, min, max, fallback) {
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

/**
 * UV sphere as quads. `segments` = longitude slices, `rings` = latitude bands.
 * Higher values = smoother sphere / more points.
 */
function sphereGeometry(radius, segments, rings, texture, color) {
  const segs = clampInt(segments, 4, 64, 16);
  const bandCount = clampInt(rings, 2, 48, Math.max(4, Math.round(segs / 2)));
  const palette = makePalette(color);
  const quads = [];

  function point(i, j) {
    const u = i / segs;
    const v = j / bandCount;
    const theta = u * Math.PI * 2;
    const phi = v * Math.PI;
    const sinPhi = Math.sin(phi);
    const x = radius * Math.cos(theta) * sinPhi;
    const y = radius * Math.sin(theta) * sinPhi;
    const z = radius * Math.cos(phi);
    const len = Math.sqrt(x * x + y * y + z * z) || 1;
    return {
      pos: [x, y, z],
      normal: [x / len, y / len, z / len],
      uv: [u, 1 - v],
    };
  }

  for (let j = 0; j < bandCount; j++) {
    for (let i = 0; i < segs; i++) {
      const a = point(i, j);
      const b = point(i + 1, j);
      const c = point(i + 1, j + 1);
      const d = point(i, j + 1);
      const nx = (a.normal[0] + b.normal[0] + c.normal[0] + d.normal[0]) * 0.25;
      const ny = (a.normal[1] + b.normal[1] + c.normal[1] + d.normal[1]) * 0.25;
      const nz = (a.normal[2] + b.normal[2] + c.normal[2] + d.normal[2]) * 0.25;
      const nLen = Math.sqrt(nx * nx + ny * ny + nz * nz) || 1;
      quads.push({
        normal: [nx / nLen, ny / nLen, nz / nLen],
        corners: [a.pos, d.pos, c.pos, b.pos],
        texture,
        palette,
        uvs: [a.uv, d.uv, c.uv, b.uv],
      });
    }
  }

  const boxes = [{ min: [-radius, -radius, -radius], max: [radius, radius, radius] }];
  return { quads, boxes, segments: segs, rings: bandCount };
}

const CRYSTAL_CELL = 0.46;
const CRYSTAL_TIP = 0.008;
const CRYSTAL_SIDES = 6;
const CRYSTAL_SPIKES = [
  { radius: 0.12, length: 1.22, tipFrac: 0.46, yaw: 0.35, tilt: 0.16, baseDist: 0 },
  { radius: 0.07, length: 0.62, tipFrac: 0.5, yaw: 0.15, tilt: 0.55, baseDist: 0.05 },
  { radius: 0.055, length: 0.48, tipFrac: 0.5, yaw: 1.45, tilt: 0.68, baseDist: 0.06 },
  { radius: 0.065, length: 0.58, tipFrac: 0.48, yaw: 2.55, tilt: 0.5, baseDist: 0.05 },
  { radius: 0.045, length: 0.4, tipFrac: 0.55, yaw: 3.85, tilt: 0.75, baseDist: 0.06 },
  { radius: 0.06, length: 0.52, tipFrac: 0.5, yaw: 5.15, tilt: 0.6, baseDist: 0.05 },
];

function crossNormal(ax, ay, az, bx, by, bz) {
  const nx = ay * bz - az * by;
  const ny = az * bx - ax * bz;
  const nz = ax * by - ay * bx;
  const len = Math.sqrt(nx * nx + ny * ny + nz * nz) || 1;
  return [nx / len, ny / len, nz / len];
}

/** Pointed hex cluster. Authored in world units; stays inside one 1x1 cell. */
function crystalGeometry(texture, color) {
  const palette = makePalette(color);
  const quads = [];
  const hz = 0.64;
  const faceUVs = FACE_UVS;

  function ring(z, radius) {
    const verts = [];
    for (let i = 0; i < CRYSTAL_SIDES; i++) {
      const a = Math.PI / CRYSTAL_SIDES + i * ((2 * Math.PI) / CRYSTAL_SIDES);
      verts.push([radius * Math.cos(a), radius * Math.sin(a), z]);
    }
    return verts;
  }

  function appendSpike(spec) {
    const { radius, length, yaw, tilt } = spec;
    const bodyZ = Math.max(0.02, length * (1 - (spec.tipFrac || 0.5)));
    const st = Math.sin(tilt);
    const ct = Math.cos(tilt);
    const cy = Math.cos(yaw);
    const sy = Math.sin(yaw);
    const baseRing = ring(0, radius);
    let lift = 0;
    for (const p of baseRing) {
      const drop = p[0] * st;
      if (drop > lift) lift = drop;
    }
    const dist = spec.baseDist || 0;
    const ox = dist * Math.cos(yaw);
    const oy = dist * Math.sin(yaw);
    const oz = -hz + lift;

    function xform(p) {
      const x1 = p[0] * ct + p[2] * st;
      const z1 = -p[0] * st + p[2] * ct;
      return [x1 * cy - p[1] * sy + ox, x1 * sy + p[1] * cy + oy, z1 + oz];
    }

    const shoulder = ring(bodyZ, radius);
    const tip = ring(length, CRYSTAL_TIP);

    function emit(a, b, c, d, flatten) {
      const p1 = xform(a);
      const p2 = xform(b);
      const p3 = xform(c);
      const p4 = xform(d);
      let n = crossNormal(
        p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2],
        p3[0] - p1[0], p3[1] - p1[1], p3[2] - p1[2]
      );
      if (flatten) {
        const horiz = Math.sqrt(n[0] * n[0] + n[1] * n[1]) || 1;
        n = [n[0] / horiz, n[1] / horiz, 0];
      }
      quads.push(face(texture, palette, n, p1, p2, p3, p4, faceUVs));
    }

    for (let i = 0; i < CRYSTAL_SIDES; i++) {
      const j = (i + 1) % CRYSTAL_SIDES;
      emit(baseRing[i], baseRing[j], shoulder[j], shoulder[i], true);
      emit(shoulder[i], shoulder[j], tip[j], tip[i], false);
    }
    let a = 1;
    while (a < CRYSTAL_SIDES - 1) {
      emit(baseRing[0], baseRing[a + 2], baseRing[a + 1], baseRing[a], false);
      a += 2;
    }
  }

  for (const spec of CRYSTAL_SPIKES) appendSpike(spec);

  let maxAbs = 0;
  for (const quad of quads) {
    for (const p of quad.corners) {
      maxAbs = Math.max(maxAbs, Math.abs(p[0]), Math.abs(p[1]));
    }
  }
  if (maxAbs > CRYSTAL_CELL) {
    const scale = CRYSTAL_CELL / maxAbs;
    for (const quad of quads) {
      for (const p of quad.corners) {
        p[0] *= scale;
        p[1] *= scale;
      }
    }
  }

  const boxes = [{ min: [-CRYSTAL_CELL, -CRYSTAL_CELL, -hz], max: [CRYSTAL_CELL, CRYSTAL_CELL, hz] }];
  return { quads, boxes };
}

function buildGeometry(options = {}) {
  const shape = String(options.shape || "box").toLowerCase();
  const texture = options.textureName || "texture";
  const color = options.vertexColor || [255, 255, 255];

  if (shape === "plane") {
    const hx = Number(options.sizeX ?? options.width ?? 1) * 0.5;
    const hy = Number(options.sizeY ?? options.depth ?? options.sizeX ?? 1) * 0.5;
    return planeGeometry(hx, hy, texture, color);
  }

  if (shape === "crystal") {
    return crystalGeometry(texture, color);
  }

  if (shape === "prism") {
    const radius = Number(options.radius ?? options.sizeX ?? 1) * 0.5;
    const hz = Number(options.sizeZ ?? options.height ?? 1) * 0.5;
    return prismGeometry(options.sides || 8, radius, hz, texture, color);
  }

  if (shape === "sphere" || shape === "ball") {
    const diameter = Number(options.diameter ?? options.sizeX ?? options.radius ?? 1);
    const radius =
      options.radius != null && options.diameter == null && options.sizeX == null
        ? Number(options.radius)
        : diameter * 0.5;
    const segments = options.segments ?? options.sides ?? options.points ?? 16;
    const rings = options.rings ?? options.bands ?? Math.max(4, Math.round(Number(segments) / 2));
    return sphereGeometry(radius, segments, rings, texture, color);
  }

  const hx = Number(options.sizeX ?? options.width ?? 1) * 0.5;
  const hy = Number(options.sizeY ?? options.depth ?? options.sizeX ?? 1) * 0.5;
  const hz = Number(options.sizeZ ?? options.height ?? 1) * 0.5;
  return boxGeometry(hx, hy, hz, texture, color);
}

module.exports = { buildGeometry, makePalette, boxGeometry, prismGeometry, crystalGeometry };

