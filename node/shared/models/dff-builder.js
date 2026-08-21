"use strict";

const { BinWriter, RW_SECTION } = require("./bin-writer");

const GEOMETRY_FLAGS = 0x02 + 0x04 + 0x08 + 0x10 + 0x40; // pos+tex+prelit+normals+modulate
const ATOMIC_FLAGS = 0x05;
const TEXTURE_FILTER_LINEAR = 2;
const TEXTURE_ADDRESSING_WRAP = 1;

function createMesh() {
  return {
    px: [],
    py: [],
    pz: [],
    nx: [],
    ny: [],
    nz: [],
    cr: [],
    cg: [],
    cb: [],
    tu: [],
    tv: [],
    triA: [],
    triB: [],
    triC: [],
    triMaterial: [],
    vertexCount: 0,
    triangleCount: 0,
    minX: Infinity,
    minY: Infinity,
    minZ: Infinity,
    maxX: -Infinity,
    maxY: -Infinity,
    maxZ: -Infinity,
  };
}

function addVertex(mesh, x, y, z, normal, color, u, v) {
  mesh.vertexCount += 1;
  const index = mesh.vertexCount - 1;
  mesh.px[index] = x;
  mesh.py[index] = y;
  mesh.pz[index] = z;
  mesh.nx[index] = normal[0];
  mesh.ny[index] = normal[1];
  mesh.nz[index] = normal[2];
  mesh.cr[index] = color[0];
  mesh.cg[index] = color[1];
  mesh.cb[index] = color[2];
  mesh.tu[index] = u;
  mesh.tv[index] = v;
  mesh.minX = Math.min(mesh.minX, x);
  mesh.minY = Math.min(mesh.minY, y);
  mesh.minZ = Math.min(mesh.minZ, z);
  mesh.maxX = Math.max(mesh.maxX, x);
  mesh.maxY = Math.max(mesh.maxY, y);
  mesh.maxZ = Math.max(mesh.maxZ, z);
  return index;
}

function addTriangle(mesh, a, b, c, material) {
  mesh.triangleCount += 1;
  const index = mesh.triangleCount - 1;
  mesh.triA[index] = a;
  mesh.triB[index] = b;
  mesh.triC[index] = c;
  mesh.triMaterial[index] = material;
}

function addQuad(mesh, c1, c2, c3, c4, normal, color, material, uvs) {
  const base = mesh.vertexCount;
  const corners = [c1, c2, c3, c4];
  for (let i = 0; i < 4; i++) {
    const uv = uvs[i];
    addVertex(mesh, corners[i][0], corners[i][1], corners[i][2], normal, color, uv[0], uv[1]);
  }
  addTriangle(mesh, base, base + 1, base + 2, material);
  addTriangle(mesh, base, base + 2, base + 3, material);
}

function shadeColor(color, factor) {
  return color.map((c) => Math.max(0, Math.min(255, Math.round(c * factor))));
}

function faceColor(palette, normal) {
  if (normal[2] > 0) return [palette.top, 1.0];
  if (normal[2] < 0) return [palette.bottom, 1.0];
  if (normal[1] < 0) return [palette.side, 1.0];
  if (normal[0] > 0) return [palette.side, 0.86];
  if (normal[1] > 0) return [palette.side, 0.68];
  return [palette.side, 0.78];
}

function writeFrameList(writer) {
  writer.beginSection(RW_SECTION.FRAMELIST);
  writer.beginSection(RW_SECTION.STRUCT);
  writer.i32(1);
  writer.vec3(1, 0, 0);
  writer.vec3(0, 1, 0);
  writer.vec3(0, 0, 1);
  writer.vec3(0, 0, 0);
  writer.i32(-1);
  writer.i32(0);
  writer.endSection();
  writer.emptySection(RW_SECTION.EXTENSION);
  writer.endSection();
}

function writeTexture(writer, name) {
  writer.beginSection(RW_SECTION.TEXTURE);
  writer.beginSection(RW_SECTION.STRUCT);
  writer.u32(
    TEXTURE_FILTER_LINEAR + TEXTURE_ADDRESSING_WRAP * 256 + TEXTURE_ADDRESSING_WRAP * 4096
  );
  writer.endSection();
  writer.rwString(name);
  writer.rwString("");
  writer.emptySection(RW_SECTION.EXTENSION);
  writer.endSection();
}

function writeMaterialList(writer, materials) {
  writer.beginSection(RW_SECTION.MATERIALLIST);
  writer.beginSection(RW_SECTION.STRUCT);
  writer.i32(materials.length);
  for (let i = 0; i < materials.length; i++) {
    writer.i32(-1);
  }
  writer.endSection();

  for (const name of materials) {
    writer.beginSection(RW_SECTION.MATERIAL);
    writer.beginSection(RW_SECTION.STRUCT);
    writer.i32(0);
    writer.rgba(255, 255, 255, 255);
    writer.i32(0);
    writer.i32(1);
    writer.f32(1);
    writer.f32(1);
    writer.f32(1);
    writer.endSection();
    writeTexture(writer, name);
    writer.emptySection(RW_SECTION.EXTENSION);
    writer.endSection();
  }
  writer.endSection();
}

function writeBinMeshPlg(writer, mesh, materialCount) {
  const groups = Array.from({ length: materialCount }, () => []);
  for (let i = 0; i < mesh.triangleCount; i++) {
    const mat = mesh.triMaterial[i];
    groups[mat].push(
      Buffer.concat([
        BinWriter.encodeU32(mesh.triA[i]),
        BinWriter.encodeU32(mesh.triB[i]),
        BinWriter.encodeU32(mesh.triC[i]),
      ])
    );
  }

  writer.beginSection(RW_SECTION.BINMESHPLG);
  writer.i32(0);
  writer.i32(materialCount);
  writer.i32(mesh.triangleCount * 3);
  for (let material = 0; material < materialCount; material++) {
    const group = groups[material];
    writer.i32(group.length * 3);
    writer.i32(material);
    writer.raw(Buffer.concat(group));
  }
  writer.endSection();
}

function writeGeometry(writer, mesh, materials) {
  writer.beginSection(RW_SECTION.GEOMETRY);
  writer.beginSection(RW_SECTION.STRUCT);
  writer.u16(GEOMETRY_FLAGS);
  writer.u8(1);
  writer.u8(0);
  writer.i32(mesh.triangleCount);
  writer.i32(mesh.vertexCount);
  writer.i32(1);

  for (let i = 0; i < mesh.vertexCount; i++) {
    writer.rgba(mesh.cr[i], mesh.cg[i], mesh.cb[i], 255);
  }
  for (let i = 0; i < mesh.vertexCount; i++) {
    writer.raw(Buffer.concat([BinWriter.encodeF32(mesh.tu[i]), BinWriter.encodeF32(mesh.tv[i])]));
  }
  for (let i = 0; i < mesh.triangleCount; i++) {
    writer.raw(
      Buffer.concat([
        BinWriter.encodeU16(mesh.triB[i]),
        BinWriter.encodeU16(mesh.triA[i]),
        BinWriter.encodeU16(mesh.triMaterial[i]),
        BinWriter.encodeU16(mesh.triC[i]),
      ])
    );
  }

  const centerX = (mesh.minX + mesh.maxX) * 0.5;
  const centerY = (mesh.minY + mesh.maxY) * 0.5;
  const centerZ = (mesh.minZ + mesh.maxZ) * 0.5;
  const dx = mesh.maxX - centerX;
  const dy = mesh.maxY - centerY;
  const dz = mesh.maxZ - centerZ;
  const radius = Math.sqrt(dx * dx + dy * dy + dz * dz);

  writer.vec3(centerX, centerY, centerZ);
  writer.f32(radius);
  writer.i32(1);
  writer.i32(1);

  for (let i = 0; i < mesh.vertexCount; i++) {
    writer.vec3(mesh.px[i], mesh.py[i], mesh.pz[i]);
  }
  for (let i = 0; i < mesh.vertexCount; i++) {
    writer.vec3(mesh.nx[i], mesh.ny[i], mesh.nz[i]);
  }
  writer.endSection();

  writeMaterialList(writer, materials);
  writer.beginSection(RW_SECTION.EXTENSION);
  writeBinMeshPlg(writer, mesh, materials.length);
  writer.endSection();
  writer.endSection();
  return radius;
}

function writeAtomic(writer) {
  writer.beginSection(RW_SECTION.ATOMIC);
  writer.beginSection(RW_SECTION.STRUCT);
  writer.i32(0);
  writer.i32(0);
  writer.i32(ATOMIC_FLAGS);
  writer.i32(0);
  writer.endSection();
  writer.emptySection(RW_SECTION.EXTENSION);
  writer.endSection();
}

/**
 * @param {object[]} quads
 * @returns {{ data: Buffer, info: object }}
 */
function buildDff(quads) {
  const mesh = createMesh();
  const materials = [];
  const materialOf = new Map();

  for (const quad of quads) {
    const texture = quad.texture || "texture";
    let material = materialOf.get(texture);
    if (material == null) {
      material = materials.length;
      materials.push(texture);
      materialOf.set(texture, material);
    }
    const [base, factor] = faceColor(quad.palette, quad.normal);
    const color = shadeColor(base, factor);
    const uvs = quad.uvs || [
      [0, 1],
      [1, 1],
      [1, 0],
      [0, 0],
    ];
    addQuad(mesh, quad.corners[0], quad.corners[1], quad.corners[2], quad.corners[3], quad.normal, color, material, uvs);
  }

  const writer = new BinWriter();
  writer.beginSection(RW_SECTION.CLUMP);
  writer.beginSection(RW_SECTION.STRUCT);
  writer.i32(1);
  writer.i32(0);
  writer.i32(0);
  writer.endSection();
  writeFrameList(writer);
  writer.beginSection(RW_SECTION.GEOMETRYLIST);
  writer.beginSection(RW_SECTION.STRUCT);
  writer.i32(1);
  writer.endSection();
  const radius = writeGeometry(writer, mesh, materials);
  writer.endSection();
  writeAtomic(writer);
  writer.emptySection(RW_SECTION.EXTENSION);
  writer.endSection();

  return {
    data: writer.build(),
    info: {
      vertices: mesh.vertexCount,
      triangles: mesh.triangleCount,
      materials: materials.length,
      radius,
    },
  };
}

module.exports = { buildDff };
