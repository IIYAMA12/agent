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

function face(texture, palette, n, c1, c2, c3, c4) {
  return {
    normal: n,
    corners: [c1, c2, c3, c4],
    texture,
    palette,
    uvs: FACE_UVS,
  };
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

function prismGeometry(sides, radius, hz, texture, color) {
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
      face(
        texture,
        palette,
        [nx, ny, 0],
        [a[0], a[1], -hz],
        [b[0], b[1], -hz],
        [b[0], b[1], hz],
        [a[0], a[1], hz]
      )
    );
  }

  for (let i = 0; i < n; i++) {
    const a = verts[i];
    const b = verts[(i + 1) % n];
    quads.push(
      face(texture, palette, [0, 0, 1], [0, 0, hz], [a[0], a[1], hz], [b[0], b[1], hz], [0, 0, hz])
    );
  }
  for (let i = 0; i < n; i++) {
    const a = verts[i];
    const b = verts[(i + 1) % n];
    quads.push(
      face(texture, palette, [0, 0, -1], [0, 0, -hz], [b[0], b[1], -hz], [a[0], a[1], -hz], [0, 0, -hz])
    );
  }

  const boxes = [{ min: [-radius, -radius, -hz], max: [radius, radius, hz] }];
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

  if (shape === "prism") {
    const radius = Number(options.radius ?? options.sizeX ?? 1) * 0.5;
    const hz = Number(options.sizeZ ?? options.height ?? 1) * 0.5;
    return prismGeometry(options.sides || 8, radius, hz, texture, color);
  }

  const hx = Number(options.sizeX ?? options.width ?? 1) * 0.5;
  const hy = Number(options.sizeY ?? options.depth ?? options.sizeX ?? 1) * 0.5;
  const hz = Number(options.sizeZ ?? options.height ?? 1) * 0.5;
  return boxGeometry(hx, hy, hz, texture, color);
}

module.exports = { buildGeometry, makePalette };
