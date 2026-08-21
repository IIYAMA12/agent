"use strict";

const { BinWriter } = require("./bin-writer");

const SURFACE = Buffer.from([0, 0, 0, 0]);

/**
 * @param {{ min: number[], max: number[] }[]} boxes
 * @param {{ modelId?: number, name?: string }} [options]
 * @returns {{ data: Buffer, info: object }}
 */
function buildCol(boxes, options = {}) {
  const list = boxes && boxes.length ? boxes : [{ min: [0, 0, 0], max: [0.1, 0.1, 0.1] }];
  const bounds = {
    minX: Infinity,
    minY: Infinity,
    minZ: Infinity,
    maxX: -Infinity,
    maxY: -Infinity,
    maxZ: -Infinity,
  };

  for (const box of list) {
    bounds.minX = Math.min(bounds.minX, box.min[0]);
    bounds.minY = Math.min(bounds.minY, box.min[1]);
    bounds.minZ = Math.min(bounds.minZ, box.min[2]);
    bounds.maxX = Math.max(bounds.maxX, box.max[0]);
    bounds.maxY = Math.max(bounds.maxY, box.max[1]);
    bounds.maxZ = Math.max(bounds.maxZ, box.max[2]);
  }

  const centerX = (bounds.minX + bounds.maxX) * 0.5;
  const centerY = (bounds.minY + bounds.maxY) * 0.5;
  const centerZ = (bounds.minZ + bounds.maxZ) * 0.5;
  const dx = bounds.maxX - centerX;
  const dy = bounds.maxY - centerY;
  const dz = bounds.maxZ - centerZ;
  const radius = Math.sqrt(dx * dx + dy * dy + dz * dz);

  const body = new BinWriter();
  body.fixedString(options.name || "agentmdl", 22);
  body.u16((options.modelId || 0) % 65536);
  body.f32(radius);
  body.vec3(centerX, centerY, centerZ);
  body.vec3(bounds.minX, bounds.minY, bounds.minZ);
  body.vec3(bounds.maxX, bounds.maxY, bounds.maxZ);
  body.u32(0);
  body.u32(0);
  body.u32(list.length);
  for (const box of list) {
    body.raw(
      Buffer.concat([
        BinWriter.encodeF32(box.min[0]),
        BinWriter.encodeF32(box.min[1]),
        BinWriter.encodeF32(box.min[2]),
        BinWriter.encodeF32(box.max[0]),
        BinWriter.encodeF32(box.max[1]),
        BinWriter.encodeF32(box.max[2]),
        SURFACE,
      ])
    );
  }
  body.u32(0);
  body.u32(0);

  const data = body.build();
  return {
    data: Buffer.concat([Buffer.from("COLL"), BinWriter.encodeU32(data.length), data]),
    info: { boxes: list.length, radius },
  };
}

module.exports = { buildCol };
