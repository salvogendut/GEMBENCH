# Pictures

Drop GEOBENCH `.PIC` files here and they are classified from their GBPC header at
build time. Portable mode-1 pictures are staged for every platform: the CPC build
copies them into `QA/CPC/CARD/PICS/` and packs them into
`QA/CPC/Floppies/EXTRAS.DSK`; the MSX build copies them into `QA/MSX/PICS/`, and
the PCW build packs them into `QA/PCW/EXTRAS.DSK`. Mode-7 sixteen-colour pictures
are staged only into `QA/MSX/PICS/` for the Screen 7 Viewer.

## Make a .PIC from an image

```
tools/picconv.py photo.jpg PHOTO.PIC      # PNG, JPG, GIF, BMP... (any Pillow format)
tools/picconv.py art.png ART.PIC -d none -w 160
tools/picconv.py art.png ART16.PIC -c 16 -w 320 --height 255
```

`picconv.py` optionally dithers and writes the v2 `.PIC` the Viewer displays.
Four-colour output uses the portable GEOBENCH desktop inks
(blue/white/black/red); sixteen-colour output targets MSX Screen 7.

## Naming

Use an uppercase 8.3 name (`NAME.PIC`, ≤ 8 characters before the dot) — that's what the
CPC's AMSDOS/FAT expects, and the staging copies the file under its own name.

## Size

The Viewer holds a picture up to ~10 KB of bitmap (≈ 200×200; `PENGUIN.PIC` is the
200×200 sample) in its in-window buffer. Larger pictures load into borrowed 16 KB
RAM bank pages, so 256K+ is the practical target for large images and multiple
picture windows. The Main CPC and PCW boot floppies carry only `LOGO.PIC`; the
platform Extras disk and card/MSX `PICS/` directories carry the full gallery from
this folder.
