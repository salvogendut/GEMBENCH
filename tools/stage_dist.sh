#!/usr/bin/env bash
# stage_dist.sh <outdir>: stage the GEOBENCH card distribution (Albireo, #134 + #136).
# On-card layout:
#   GB.BAS       - BASIC loader: RUN"GBALB (machine-code loader is impossible under
#                  UniDOS, see memory geobench-loader-136, hence BASIC)
#   GBALB.BIN    - Albireo (CH376) kernel; real 128-byte AMSDOS header, exec 0x8000.
#                  Falls back to floppy (drive A) when no CH376 card is present.
#   GEOBENCH.CFG - config (root; read before the kernel enters /GEOBENCH)
#   GEOBENCH/    - everything the kernel loads at boot (apps/modules/fonts/icons/cursor)
# Boot: RUN"GB -> RUN"GBALB -> the kernel reads /GEOBENCH. IDE is retired (frozen on
# branch legacy-ide; still buildable via STORAGE=ide but not shipped). Needs build/GBALB.RAW.
#   * <app>.APP / GBCFG/GBFAT/FLOPPYSV.BIN - HEADERLESS raw images (kernel loads them)
#   * GB.BAS / GEOBENCH.CFG - written with CR+LF line endings (the CPC requires them)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: tools/stage_dist.sh <outdir>}"
SYS="$OUT/GEOBENCH"                  # everything the kernel loads lives here
mkdir -p "$SYS"

# --- root: the loader, the Albireo kernel, the config -------------------------
# IDE is retired (frozen on branch legacy-ide). One kernel ships now: GBALB (Albireo
# CH376), which also drives a floppy when no card is present - so GB.BAS just RUN"s it.
# (The IDE backend source stays buildable via STORAGE=ide, just not shipped.)
printf '10 RUN"GBALB\r\n' > "$OUT/GB.BAS"
python3 tools/amsdos_header.py build/GBALB.RAW "$OUT/GBALB.BIN" GBALB BIN 0x8000
printf 'FONT=DEFAULT\r\nICONS=REFINED\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\n' \
    > "$OUT/GEOBENCH.CFG"

# --- /GEOBENCH: apps, modules, assets -----------------------------------------
for a in DESKTOP FILEMGR VIEWER NOTEPAD ICONED CLOCK PAINT XAOS; do
    cp "build/$a.RAW" "$SYS/$a.APP"
done
cp build/GBCFG.RAW "$SYS/GBCFG.BIN"
cp build/GBFAT.RAW "$SYS/GBFAT.BIN"
cp build/FLOPPYSV.RAW "$SYS/FLOPPYSV.BIN"   # #135: paged AMSDOS/floppy write module
cp build/GBUI.RAW "$SYS/GBUI.BIN"           # #142: paged dialog (popup/prompt/file-picker) module
cp build/DEFAULT.FNT build/CLASSIC.FNT build/DEFAULT.IST build/PAINT.IST \
   build/DEFAULT.SPR build/HAND.SPR "$SYS/"
for ist in assets/iconsets/*.IST; do          # tracked custom icon sets (edit with
    [ -e "$ist" ] && cp "$ist" "$SYS/"         # tools/iconedit.py); select via ICONS=<name>
done
cp assets/WELCOME.TXT "$SYS/"
for pic in assets/pictures/*.PIC; do        # ship every .PIC in assets/pictures/ to the card
    [ -e "$pic" ] && cp "$pic" "$SYS/"       # (PENGUIN.PIC + anything you add - view in the Viewer)
done
