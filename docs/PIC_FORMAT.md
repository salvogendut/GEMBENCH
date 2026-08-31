# GEMBENCH picture format

GBPC v2 retains a canonical four-colour format plus an optional sixteen-colour
Screen 7 payload for the MSX2 Viewer, wallpaper loader, and Paint.

## GBPC v2 layout

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 4 | ASCII `GBPC` |
| 4 | 1 | Version `2` |
| 5 | 1 | Packing mode: `1` (portable four-colour) or `7` (MSX Screen 7) |
| 6 | 2 | Width in pixels, little-endian |
| 8 | 2 | Height in pixels, little-endian |
| 10 | 4 | legacy ink indices for logical pens 0-3 |
| 14 | variable | Row-major packed pixels |

### Mode 1: portable four-colour

Rows occupy `(width + 3) / 4` bytes. Four logical two-bit pen values are packed
in the historical Mode-1 byte order: pen bit 0 for pixels 0-3 is stored in bits
7-4, and pen bit 1 is stored in bits 3-0. This remains the canonical
representation for four-colour pictures created or edited by GEMBENCH.

### Mode 7: MSX2 sixteen-colour

Rows occupy `width / 2` bytes. Each byte stores its left pixel in the high
nibble and its right pixel in the low nibble. Width must be a multiple of four.
The first four palette indices retain GEOBENCH's UI pens; indices 4-15 use the
fixed Screen 7 extension palette. Viewer and the desktop wallpaper loader accept
pictures up to 512x255 whose complete file is smaller than 64 KiB.

Mode 7 is a Screen-7 extension, not a replacement for the canonical payload. It
is displayed only by the MSX2 Screen 7 kernel. Screen 6 rejects it without
interpreting its bytes. Paint edits Mode-7 pictures only under Screen 7.

## Runtime display

- MSX2 Screen 6 translates each canonical byte to native V9938 packing.
- MSX2 Screen 7 expands mode-1 UI bytes at the display boundary and can stream a
  mode-7 payload directly to VRAM.

The generated lookup tables are reversible. A legacy v2 file tagged with mode
`6` is normalized to canonical mode `1` when loaded into a bank on MSX2.
New portable files must use mode `1`; mode `7` is reserved for the sixteen-colour
extension. Paint keeps documents in a borrowed bank and transfers only the active
20x20 edit tile into its app page. Screen-7 Paint can create and edit mode `7`
tiles directly.

`tools/picconv.py` defaults to portable four-colour output. Use `--colors 16`
(or select 16 in its GUI) to produce an MSX Screen 7 picture:

```bash
tools/picconv.py source.png output.PIC --colors 16 --width 200 --height 255
```

The GUI exposes both dimensions. Leave either dimension blank to calculate it
from the source aspect ratio; setting both requests that exact output size.

Run `make check` to validate the codec tables and confirm that the staged MSX2
`PICS` folder matches the canonical and Screen-7 asset sources.
