# Custom icon sets

Drop tracked `.IST` icon-set files here and the MSX2 build automatically stages
them into `QA/MSX/CARD/GBENCH/`. The kernel transcodes a selected canonical set
to native display bytes when it is loaded.

`build/DEFAULT.IST` is a gitignored build artifact regenerated from the ordered
system/file-type `lib/icon_*.asm` sources
each build; it stays in canonical Mode-1 packing so Screen 6 and Screen 7 can
decode the same resource. Tracked sets in this folder are version-controlled and
never regenerated.

## Make / edit a set

```
tools/iconedit.py assets/iconsets/MYSET.IST     # tkinter editor (.IST and .SPR)
```

`iconedit.py` opens an existing `.IST` or starts a new one; draw, then Save.

A selectable desktop set must supply every resident system/file-type slot
(currently 21 icons, including the auxiliary CF, IDE, Fractal, Settings, and
Calculator artwork slots). Settings only lists `.IST` files whose header icon count is exactly 21
(`MIN_IST_ICONS`), so toolchests and legacy layouts with shifted slot meanings
remain excluded.

To migrate a 25-slot set created before #430, remove the nine former
application slots in descending order, then append the five auxiliary slots:

```sh
for slot in 22 21 20 19 17 16 12 11 1; do
    tools/ist_remove_slot.py assets/iconsets/MYSET.IST "$slot"
done
tools/ist_append.py assets/iconsets/MYSET.IST \
    lib/icon_cf.asm lib/icon_ide.asm lib/icon_fractal.asm \
    lib/icon_settings.asm lib/icon_calculator.asm
```

Convert a legacy set before naming it manually in `GEOBENCH.CFG`; the
space-constrained kernel assumes the current positional layout.
When a new desktop icon is added, append it to each tracked set with
`tools/ist_append.py assets/iconsets/MYSET.IST lib/icon_<name>.asm` (`packicons.py`
only regenerates `build/DEFAULT.IST`).
When an existing slot changes meaning, replace that slot in every tracked set:

```
tools/ist_replace_slot.py assets/iconsets/MYSET.IST 13 lib/icon_sd.asm
```

## Use it on the desktop

Select the set in the boot config `GEOBENCH.CFG`:

```
ICONS=MYSET
```

The kernel loads `MYSET.IST` from the system folder at boot and falls back to
`DEFAULT.IST` if it is missing. When the configured active set is opened from
the system drive in GEOBENCH's ICONED and saved, the kernel reloads it and
repaints the desktop immediately; no reboot is required. Saving an inactive set
does not replace the current theme.

## Changing the DEFAULT icons instead

If you want to change resident system/file-type icons shown out of the box,
edit the source PNGs and regenerate the committed ASM. Application icons are
edited through `apps/<name>/icon.asm` or the APP itself:

```
# edit assets/<name>.png in any image editor (32x32, the desktop 4-colour palette)
tools/regen_icons.sh            # png2cpc every assets/*.png -> lib/icon_*.asm
tools/build_kernel_msx.sh       # repacks build/msx/DEFAULT.IST + the card
```

See `docs/DEVELOPMENT.md` for the full icon pipeline.
