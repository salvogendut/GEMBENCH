# Pictures

Drop GEOBENCH `.PIC` files here and they are **copied onto every card** (the unified
`QA/GEOBENCH.IMG` and the loose `QA/CARD/` tree via `stage_dist.sh`) at build time —
they show up in the Viewer.

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
200×200 sample) in its in-window buffer. Larger pictures load into a borrowed 16 KB
RAM bank (#164), so on a bare 128K machine — where every app bank is already in use —
a big image shows an empty window, while a 256K+ expansion displays it. The floppy
image (`QA/GEOBENCH.DSK`) only carries the pictures hardcoded in
`kernel/pack_apps.asm`; the card carries everything in this folder.
