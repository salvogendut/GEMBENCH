# Pictures

Drop GEOBENCH `.PIC` files here and they are staged for the card and MSX
distributions at build time. The CPC card tree copies them into `QA/CARD/GBENCH/`
via `stage_dist.sh`; the MSX build transcodes them to Screen 6 and places copies in
both `QA/MSX/` and `QA/MSX/GBENCH/`. They show up in the Viewer.

## Make a .PIC from an image

```
tools/picconv.py photo.jpg PHOTO.PIC      # PNG, JPG, GIF, BMP... (any Pillow format)
tools/picconv.py art.png ART.PIC -d none -w 160
```

`picconv.py` maps each pixel to the 4 GEOBENCH desktop inks (blue/white/black/red),
optionally dithers, and writes the v2 `.PIC` the Viewer displays.

## Naming

Use an uppercase 8.3 name (`NAME.PIC`, ≤ 8 characters before the dot) — that's what the
CPC's AMSDOS/FAT expects, and the staging copies the file under its own name.

## Size

The Viewer holds a picture up to ~10 KB of bitmap (≈ 200×200; `PENGUIN.PIC` is the
200×200 sample) in its in-window buffer. Larger pictures load into borrowed 16 KB
RAM bank pages, so 256K+ is the practical target for large images and multiple
picture windows. The Main CPC boot floppy carries only its hand-packed core
picture set; `QA/COMPANION.DSK`, the card distribution, and the MSX distribution
carry the gallery pictures from this folder.
