#!/usr/bin/env bash
# stage_dist.sh <outdir>: stage the GEOBENCH Albireo card (#104 + #134 + #136).
# The shipped product is the Albireo (CH376) kernel plus the AMSDOS floppy fallback
# baked into it (boots floppy A when no card is present). The M4 + IDE backends are
# ARCHIVED - frozen in-tree, not built or shipped (see docs/ARCHIVED.md).
# On-card layout:
#   GB.BAS       - BASIC loader: RUN"GBALB. (A machine-code loader is impossible under
#                  UniDOS - see memory geobench-loader-136 - hence BASIC.)
#   GBALB.BIN    - Albireo (CH376) kernel: real 128-byte AMSDOS header, exec 0x8000;
#                  falls back to floppy A when no card is present.
#   GEOBENCH.CFG - config (root; read before the kernel enters /GBENCH)
#   GBENCH/      - everything the kernel loads at boot (apps/modules/fonts/icons/cursor)
# Boot: RUN"GB -> RUN"GBALB -> the kernel reads /GBENCH.
# Needs build/GBALB.RAW.
#   * <app>.APP / GBCFG/GBFAT/FLOPPYSV/GBUI.MOD - HEADERLESS raw kernel modules (#234: .MOD,
#     not .BIN, so .BIN is reserved for native runnable binaries; the kernel loads them)
#   * GB.BAS / GEOBENCH.CFG - written with CR+LF line endings (the CPC requires them)
set -euo pipefail
cd "$(dirname "$0")/.."
RASM="${RASM:-rasm}"

OUT="${1:?usage: tools/stage_dist.sh <outdir>}"
SYS="$OUT/GBENCH"                    # the system folder (#174: <=7 chars so the M4's
                                     # '>'-prefixed dir listing round-trips it; was /GEOBENCH)
mkdir -p "$SYS"

# --- root: the loader, the Albireo kernel, the config -------------------------
# GB.BAS just RUN"s the Albireo kernel. (A machine-code loader is impossible under
# UniDOS - see memory geobench-loader-136 - hence BASIC.) ASCII with CR+LF, as the
# CPC requires. The archived M4 card used a POKE'd m4detect.asm probe here to pick
# GBM4 vs GBALB; with M4 frozen out (docs/ARCHIVED.md) the loader is a one-liner.
printf '10 RUN"GBALB\r\n' > "$OUT/GB.BAS"
python3 tools/amsdos_header.py build/GBALB.RAW "$OUT/GBALB.BIN" GBALB BIN 0x8000
cp build/GEOBENCH.CFG "$OUT/GEOBENCH.CFG"   # #205: one source, shared with the floppy DSK (pack_apps3)

# --- /GBENCH: apps, modules, assets -------------------------------------------
for a in DESKTOP FILEMGR VIEWER NOTEPAD ICONED CLOCK PAINT XAOS SETTINGS; do
    cp "build/$a.RAW" "$SYS/$a.APP"
done
cp build/CIRCLE.RAW "$SYS/CIRCLE.SAV"       # #219: the test screensaver (a .SAV, not a .APP)
cp build/DECO.RAW   "$SYS/DECO.SAV"         # art-deco panels screensaver (ported from symsav-deco)
cp build/XMATRIX.RAW "$SYS/XMATRIX.SAV"     # Matrix digital-rain screensaver (ported from symsav-xmatrix)
cp build/MOUNTAIN.RAW "$SYS/MOUNTAIN.SAV"   # isometric terrain screensaver (ported from symsav-mountain)
cp build/STARFLD.RAW  "$SYS/STARFLD.SAV"    # 3D star-field screensaver (inspired by symsav-starfield)
cp build/FRACTALI.RAW "$SYS/FRACTALI.SAV"   # fractal screensaver (ported from symsav-fractalic) - CARD ONLY
cp build/XROACH.RAW   "$SYS/XROACH.SAV"     # cockroach screensaver (ported from symsav-xroach) - CARD ONLY
cp build/MUNCH.RAW    "$SYS/MUNCH.SAV"      # munching-squares screensaver (xscreensaver port) - CARD ONLY
cp build/RORSCH.RAW   "$SYS/RORSCH.SAV"     # rorschach ink-blot screensaver (xscreensaver port) - CARD ONLY
cp build/TRUCHET.RAW  "$SYS/TRUCHET.SAV"    # truchet-tile maze screensaver (xscreensaver port) - CARD ONLY
cp build/ANT.RAW      "$SYS/ANT.SAV"        # Langton's-ant screensaver (xscreensaver port) - CARD ONLY
cp build/LIGHTN.RAW   "$SYS/LIGHTN.SAV"     # fractal-lightning screensaver (xscreensaver port) - CARD ONLY
cp build/PYRO.RAW     "$SYS/PYRO.SAV"       # fireworks screensaver (xscreensaver port) - CARD ONLY
cp build/FOREST.RAW   "$SYS/FOREST.SAV"     # fractal-trees screensaver (xscreensaver port) - CARD ONLY
cp build/HELIX.RAW    "$SYS/HELIX.SAV"      # harmonograph screensaver (xscreensaver port) - CARD ONLY
cp build/CATCLK.RAW   "$SYS/CATCLK.SAV"     # Kit-Cat clock screensaver (inspired by X11 catclock) - CARD ONLY
cp build/GBCFG.RAW "$SYS/GBCFG.MOD"          # #234: kernel modules use .MOD (.BIN = native runnable)
cp build/GBFAT.RAW "$SYS/GBFAT.MOD"
cp build/FLOPPYSV.RAW "$SYS/FLOPPYSV.MOD"   # #135: paged AMSDOS/floppy write module
cp build/GBUI.RAW "$SYS/GBUI.MOD"           # #142: paged dialog (popup/prompt/file-picker) module
cp build/DEFAULT.FNT build/CLASSIC.FNT build/DEFAULT.IST build/PAINT.IST \
   build/DEFAULT.SPR build/HAND.SPR "$SYS/"
cp build/SPLASH.BIN "$SYS/SPLASH.MOD"         # #196: bootsplash lollipop bitmap (.MOD, #234)
for bdp in build/*.BDP; do                    # #128: backdrop tiles (BACKDROP=<name>)
    [ -e "$bdp" ] && cp "$bdp" "$SYS/"
done
for ist in assets/iconsets/*.IST; do          # tracked custom icon sets (edit with
    [ -e "$ist" ] && cp "$ist" "$SYS/"         # tools/iconedit.py); select via ICONS=<name>
done
cp assets/WELCOME.TXT "$SYS/"
for pic in assets/pictures/*.PIC; do        # ship every .PIC in assets/pictures/ to the card
    [ -e "$pic" ] && cp "$pic" "$SYS/"       # (PENGUIN.PIC + anything you add - view in the Viewer)
done
