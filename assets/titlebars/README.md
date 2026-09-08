# Window title-bar tiles

`.TBR` files are canonical four-pen GEOBENCH window-title motifs. Each current
file is a headerless 16x14 repeated background (56 CPC Mode-1 bytes). Close and
maximize artwork lives independently in `assets/gadgets/*.GDT`, so either part
can be selected without duplicating the other. The same sources are decoded at
runtime by the MSX distribution and experimental CPC runtime. The format is
also suitable for the future PCW port. Legacy 106-byte combined `.TBR` themes
remain supported.

The renderer repeats the background horizontally, then stamps the reusable
gadget tiles and draws the window title.

Edit a tile and preview it repeated across several complete window bars with:

```sh
python3 tools/titlebaredit.py assets/titlebars/ORIGINAL.TBR assets/gadgets/ORIGINAL.GDT
```

The toolchest works on the last-clicked title, close, or maximize canvas. It
provides pencil and line drawing, outlined and filled rectangles/circles,
bucket fill, spray paint, and undo. The four arrow controls shift the active
canvas by one pixel and clear the newly exposed edge with paper colour.

All `.TBR` files in this directory are validated and staged for the MSX
distribution and private CPC M4 runtime. Select an available motif live in
MSX Settings with **Title bar**, or set:

```ini
TITLEBAR=WEAVE
```

`ORIGINAL.TBR` is the default. The renderer carries the composed ORIGINAL title
and gadgets as a fallback, so missing configured files cannot leave window
titles unpainted. Build the MSX distribution or private CPC runtime with:

```sh
make msx
make diagnostic-cpc-runtime
```

CPC Settings/full Desktop and PCW are not enabled. See the
[CPC chrome checkpoint](../../docs/CPC-RESTART-STEP3D-U.md) for M4-only manual
checks, strict asset admission and the plain-title recovery when its module
is unavailable.
