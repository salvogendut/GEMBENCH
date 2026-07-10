# Custom icon sets

Drop tracked `.IST` icon-set files here and they are automatically staged for the
CPC card and MSX distributions. The CPC build copies them into `QA/CARD/GBENCH/`
via `stage_dist.sh`; the MSX build transcodes them to Screen 6 in
`QA/MSX/GBENCH/`. Unlike `build/DEFAULT.IST` — a gitignored build artifact that
`packicons.py` regenerates from `lib/icon_*.asm` on every build — files here are
version-controlled and the build never overwrites them.

## Make / edit a set

```
tools/iconedit.py assets/iconsets/MYSET.IST     # tkinter editor (.IST and .SPR)
```

`iconedit.py` opens an existing `.IST` or starts a new one; draw, then Save.

A selectable desktop set must supply **every** slot the desktop draws (currently 25
icons, since #198 dropped the duplicate `icon_iconset` slot) — the Settings app only
lists `.IST` files whose header icon count is ≥ 25 (`MIN_IST_ICONS`), so toolchests
like `PAINT.IST` are excluded.
When a new desktop icon is added, append it to each tracked set with
`tools/ist_append.py assets/iconsets/MYSET.IST lib/icon_<name>.asm` (`packicons.py`
only regenerates `build/DEFAULT.IST`).
When an existing slot changes meaning, replace that slot in every tracked set:

```
tools/ist_replace_slot.py assets/iconsets/MYSET.IST 17 lib/icon_browser.asm
```

## Use it on the desktop

Select the set in the boot config `GEOBENCH.CFG` (written by `stage_dist.sh`):

```
ICONS=MYSET
```

The kernel loads `MYSET.IST` from the system folder at boot and falls back to
`DEFAULT.IST` if it is missing.

## Changing the DEFAULT icons instead

If you want to change the icons shown out of the box (not a separate selectable
set), edit the source PNGs and regenerate the committed asm:

```
# edit assets/<name>.png in any image editor (32x32, the desktop 4-colour palette)
tools/regen_icons.sh            # png2cpc every assets/*.png -> lib/icon_*.asm
tools/build_kernel.sh           # repacks build/DEFAULT.IST + the card
```

See `docs/DEVELOPMENT.md` for the full icon pipeline.
