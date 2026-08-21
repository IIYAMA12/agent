"use strict";

const RW_VERSION = 0x1803ffff;

const RW_SECTION = {
  STRUCT: 0x01,
  STRING: 0x02,
  EXTENSION: 0x03,
  TEXTURE: 0x06,
  MATERIAL: 0x07,
  MATERIALLIST: 0x08,
  FRAMELIST: 0x0e,
  GEOMETRY: 0x0f,
  CLUMP: 0x10,
  ATOMIC: 0x14,
  TEXTURENATIVE: 0x15,
  TEXDICTIONARY: 0x16,
  GEOMETRYLIST: 0x1a,
  BINMESHPLG: 0x50e,
};

function encodeU8(value) {
  return Buffer.from([value & 0xff]);
}

function encodeU16(value) {
  const buf = Buffer.alloc(2);
  buf.writeUInt16LE(value & 0xffff, 0);
  return buf;
}

function encodeU32(value) {
  const buf = Buffer.alloc(4);
  buf.writeUInt32LE(value >>> 0, 0);
  return buf;
}

function encodeI32(value) {
  const buf = Buffer.alloc(4);
  buf.writeInt32LE(value | 0, 0);
  return buf;
}

function encodeF32(value) {
  const buf = Buffer.alloc(4);
  buf.writeFloatLE(value, 0);
  return buf;
}

class BinWriter {
  constructor() {
    this.parts = [];
    this.length = 0;
    this.sections = [];
  }

  raw(data) {
    const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
    this.parts.push(buf);
    this.length += buf.length;
    return this;
  }

  u8(value) {
    return this.raw(encodeU8(value));
  }

  u16(value) {
    return this.raw(encodeU16(value));
  }

  u32(value) {
    return this.raw(encodeU32(value));
  }

  i32(value) {
    return this.raw(encodeI32(value));
  }

  f32(value) {
    return this.raw(encodeF32(value));
  }

  vec3(x, y, z) {
    return this.raw(Buffer.concat([encodeF32(x), encodeF32(y), encodeF32(z)]));
  }

  rgba(r, g, b, a) {
    return this.raw(Buffer.from([r & 0xff, g & 0xff, b & 0xff, a & 0xff]));
  }

  fixedString(text, width) {
    const src = Buffer.from(String(text || ""), "utf8").subarray(0, Math.max(0, width - 1));
    const out = Buffer.alloc(width, 0);
    src.copy(out);
    return this.raw(out);
  }

  beginSection(sectionType) {
    this.u32(sectionType);
    this.u32(0);
    this.u32(RW_VERSION);
    this.sections.push({
      sizePartIndex: this.parts.length - 2,
      bodyStart: this.length,
    });
    return this;
  }

  endSection() {
    const section = this.sections.pop();
    if (!section) return this;
    const size = this.length - section.bodyStart;
    this.parts[section.sizePartIndex] = encodeU32(size);
    return this;
  }

  emptySection(sectionType) {
    return this.beginSection(sectionType).endSection();
  }

  rwString(text) {
    this.beginSection(RW_SECTION.STRING);
    const str = String(text || "");
    let padded = str.length + 1;
    const rem = padded % 4;
    if (rem > 0) padded += 4 - rem;
    const buf = Buffer.alloc(padded, 0);
    Buffer.from(str, "utf8").copy(buf);
    this.raw(buf);
    return this.endSection();
  }

  build() {
    return Buffer.concat(this.parts);
  }
}

BinWriter.encodeU8 = encodeU8;
BinWriter.encodeU16 = encodeU16;
BinWriter.encodeU32 = encodeU32;
BinWriter.encodeI32 = encodeI32;
BinWriter.encodeF32 = encodeF32;

module.exports = { BinWriter, RW_SECTION, RW_VERSION };
