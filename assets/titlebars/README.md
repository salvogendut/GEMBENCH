# Window title-bar tiles

`.TBR` files are canonical four-pen GEOBENCH window-title themes. Each current
file is headerless and contains a 16x14 repeated background (56 bytes), an 8x10
close tile (20 bytes), and a 12x10 maximize tile (30 bytes), for 106 CPC Mode-1
bytes total. The same source is decoded at runtime by CPC, MSX, and PCW builds.
Legacy 56-byte background-only files remain supported and use the embedded
fallback gadgets.

The renderer repeats the background horizontally, then stamps the reusable
gadget tiles and draws the window title.

Edit a tile and preview it repeated across several complete window bars with:

```sh
python3 tools/titlebaredit.py assets/titlebars/ORIGINAL.TBR
```

The toolchest works on the last-clicked title, close, or maximize canvas. It
provides pencil and line drawing, outlined and filled rectangles/circles,
bucket fill, spray paint, and undo. The four arrow controls shift the active
canvas by one pixel and clear the newly exposed edge with paper colour.

All `.TBR` files in this directory are validated and staged for card and MSX
distributions. Space-constrained CPC and PCW boot floppies carry `ORIGINAL.TBR`
and `IMPROVED.TBR`; their `EXTRAS.DSK` carries the remaining themes. Select an
available theme live in Settings with **Title bar**, or set:

```ini
TITLEBAR=WEAVE
```

`ORIGINAL.TBR` is the default. The renderer carries the same complete theme as
a fallback, so a missing configured file
cannot leave window titles unpainted. Rebuild all distributions with:

```sh
make cpc
make msx
make pcw
```
