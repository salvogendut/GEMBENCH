# Portable GEOBENCH picture format

GEOBENCH `.PIC` files use one platform-independent byte encoding. The exact same
file can be copied between CPC, MSX2, and PCW storage without conversion.

## GBPC v2 layout

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 4 | ASCII `GBPC` |
| 4 | 1 | Version `2` |
| 5 | 1 | Canonical packing mode `1` |
| 6 | 2 | Width in pixels, little-endian |
| 8 | 2 | Height in pixels, little-endian |
| 10 | 4 | CPC ink numbers for logical pens 0-3 |
| 14 | variable | Row-major packed pixels |

Rows occupy `(width + 3) / 4` bytes. Four logical two-bit pen values are packed
as CPC Mode-1 bytes: pen bit 0 for pixels 0-3 is stored in bits 7-4, and pen bit
1 is stored in bits 3-0. This is the canonical file representation even when the
picture is created or edited on an MSX2 or PCW.

## Runtime display

- CPC displays canonical bytes directly, so the constrained resident kernel pays
  no conversion cost.
- MSX2 translates each canonical byte to V9938 Screen 6 packing while blitting.
- PCW translates directly to the emulator CGA2 hardware-pen representation while
  blitting. Real PCW hardware shows the corresponding monochrome texture.

The generated lookup tables are reversible. A legacy v2 file tagged with mode
`6` is normalized to canonical mode `1` when loaded into a bank on MSX2 or PCW;
new files must always be written as mode `1`. Paint keeps its canvas and banked
edit tiles canonical and translates only temporary display rows.

Run `make check` to validate the codec tables and confirm that every staged
`PICS` folder and CPC/PCW Extras disk carries byte-identical picture payloads.
