"use strict";

const { BinWriter, RW_SECTION } = require("./bin-writer");
const { bgraToDxt1 } = require("./dxt1");

const RASTER_FORMAT_8888 = 0x0500;
const RASTER_FORMAT_1555 = 0x0100;
const D3DFMT_A8R8G8B8 = 21;
const D3DFMT_DXT1 = 0x31545844;
const PLATFORM_D3D9 = 9;
const RASTER_TYPE_TEXTURE = 4;
const FILTER_LINEAR = 2;
const ADDRESSING_WRAP = 1;
const ADDRESSING_CLAMP = 3;

function writeTextureNative(writer, name, size, pixels, hasAlpha, clamp, compressed) {
  const addressing = clamp ? ADDRESSING_CLAMP : ADDRESSING_WRAP;

  writer.beginSection(RW_SECTION.TEXTURENATIVE);
  writer.beginSection(RW_SECTION.STRUCT);
  writer.u32(PLATFORM_D3D9);

  writer.u16(FILTER_LINEAR);
  writer.u8(addressing + addressing * 16);
  writer.u8(0);

  writer.fixedString(name, 32);
  writer.fixedString("", 32);

  if (compressed) {
    writer.u32(RASTER_FORMAT_1555);
    writer.u32(D3DFMT_DXT1);
    writer.u16(size);
    writer.u16(size);
    writer.u8(16);
    writer.u8(1);
    writer.u8(RASTER_TYPE_TEXTURE);
    writer.u8(8);
  } else {
    writer.u32(RASTER_FORMAT_8888);
    writer.u32(D3DFMT_A8R8G8B8);
    writer.u16(size);
    writer.u16(size);
    writer.u8(32);
    writer.u8(1);
    writer.u8(RASTER_TYPE_TEXTURE);
    writer.u8(hasAlpha ? 1 : 0);
  }

  writer.u32(pixels.length);
  writer.raw(pixels);
  writer.endSection();
  writer.emptySection(RW_SECTION.EXTENSION);
  writer.endSection();
}

/**
 * @param {{ name: string, pixels: Buffer, size: number, hasAlpha?: boolean, clamp?: boolean }[]} textures
 * @param {{ compression?: "dxt1"|"none" }} [options]
 * @returns {{ data: Buffer, info: object }}
 */
function buildTxd(textures, options = {}) {
  const useDxt1 = (options.compression || "dxt1") === "dxt1";
  const writer = new BinWriter();
  writer.beginSection(RW_SECTION.TEXDICTIONARY);

  writer.beginSection(RW_SECTION.STRUCT);
  writer.u16(textures.length);
  writer.u16(0);
  writer.endSection();

  let compressedCount = 0;
  for (const texture of textures) {
    let raster = texture.pixels;
    let compressed = false;
    if (useDxt1) {
      try {
        raster = bgraToDxt1(texture.pixels, texture.size);
        compressed = true;
        compressedCount += 1;
      } catch {
        raster = texture.pixels;
        compressed = false;
      }
    }
    writeTextureNative(
      writer,
      texture.name,
      texture.size,
      raster,
      Boolean(texture.hasAlpha),
      Boolean(texture.clamp),
      compressed
    );
  }

  writer.emptySection(RW_SECTION.EXTENSION);
  writer.endSection();

  return {
    data: writer.build(),
    info: {
      count: textures.length,
      compression: useDxt1 ? "dxt1" : "none",
      compressedCount,
    },
  };
}

module.exports = { buildTxd };
