# Custom icon sets

Drop tracked `.IST` icon-set files here and they are automatically staged for the
CPC card and MSX distributions. The CPC build copies them into
`QA/CPC/CARD/GBENCH/` via `stage_dist.sh`; MSX copies the same files into its
`GBENCH/` folder unchanged. The space-constrained PCW boot disk stages its selected
sets (currently `REFINED.IST`) from this same canonical source. MSX and PCW let the
kernel transcode a selected set to native display bytes when it is loaded.

`build/DEFAULT.IST` is a gitignored build artifact regenerated from `lib/icon_*.asm`
each build in all desktop targets; it stays canonical (Mode-1) so it is shared by all
platforms. Tracked sets in this folder are version-controlled and never regenerated.

## Make / edit a set

```
tools/iconedit.py assets/iconsets/MYSET.IST     # tkinter editor (.IST and .SPR)
```

`iconedit.py` opens an existing `.IST` or starts a new one; draw, then Save.

A selectable desktop set must supply every resident system/file-type slot
(currently 17 icons after application-owned icons moved to GBAP headers in
#430). Settings only lists `.IST` files whose header icon count is exactly 17
(`MIN_IST_ICONS`), so toolchests and legacy layouts with shifted slot meanings
remain excluded.

To migrate a 25-slot set created before #430, remove the eight former
application slots in descending order:

```sh
for slot in 22 21 20 19 17 16 12 11; do
    tools/ist_remove_slot.py assets/iconsets/MYSET.IST "$slot"
done
```

Convert a legacy set before naming it manually in `GEOBENCH.CFG`; the
space-constrained kernel assumes the current positional layout.
When a new desktop icon is added, append it to each tracked set with
`tools/ist_append.py assets/iconsets/MYSET.IST lib/icon_<name>.asm` (`packicons.py`
only regenerates `build/DEFAULT.IST`).
When an existing slot changes meaning, replace that slot in every tracked set:

```
tools/ist_replace_slot.py assets/iconsets/MYSET.IST 14 lib/icon_sd.asm
```

## Use it on the desktop

Select the set in the boot config `GEOBENCH.CFG` (written by `stage_dist.sh`):

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
tools/build_kernel.sh           # repacks build/DEFAULT.IST + the card
```

See `docs/DEVELOPMENT.md` for the full icon pipeline.
