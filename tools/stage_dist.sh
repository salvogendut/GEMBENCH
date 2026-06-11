#!/usr/bin/env bash
# stage_dist.sh <outdir>: stage the COMPLETE GEOBENCH distribution into <outdir>
# in the on-card layout (#134): the kernel GB.BIN and GEOBENCH.CFG at the root, and
# EVERYTHING the kernel loads at boot under a GEOBENCH/ subfolder (so the card root
# stays clean next to SymBOS/CP/M/UniDOS files). The kernel enters /GEOBENCH at boot
# (falling back to a flat root for floppies, which have no subdirectories). One source
# of truth for the file set, shared by build_kernel.sh (-> QA/) and deploy_ide.sh
# (-> a temp dir it mcopies into the card image). Conventions:
#   * GB.BIN            - a real 128-byte AMSDOS header (UniDOS RUN"GB), exec 0x8000
#   * <app>.APP         - HEADERLESS raw images (the kernel loads them to #4000 itself)
#   * GBCFG/GBFAT.BIN   - headerless raw kernel C modules
#   * fonts/icons/cursors/WELCOME.TXT - copied as-is
#   * GEOBENCH.CFG      - written with CR+LF line endings (the CPC requires them)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: tools/stage_dist.sh <outdir>}"
SYS="$OUT/GEOBENCH"                  # everything the kernel loads lives here
mkdir -p "$SYS"

# --- root: only the kernel + the config ---------------------------------------
# kernel: headered, named GB.BIN so it RUN"GB's
python3 tools/amsdos_header.py build/GBKERN.RAW "$OUT/GB.BIN" GB BIN 0x8000
# config: read from the root before the kernel enters /GEOBENCH (CR+LF as the CPC needs)
printf 'FONT=DEFAULT\r\nICONS=DEFAULT\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\n' \
    > "$OUT/GEOBENCH.CFG"

# --- /GEOBENCH: apps, modules, assets -----------------------------------------
# launchable apps: headerless raw, .APP
for a in DESKTOP FILEMGR VIEWER NOTEPAD ICONED CLOCK PAINT XAOS; do
    cp "build/$a.RAW" "$SYS/$a.APP"
done
# kernel modules: headerless raw, .BIN
cp build/GBCFG.RAW "$SYS/GBCFG.BIN"
cp build/GBFAT.RAW "$SYS/GBFAT.BIN"
cp build/FLOPPYSV.RAW "$SYS/FLOPPYSV.BIN"   # #135: paged AMSDOS/floppy write module
# assets
cp build/DEFAULT.FNT build/CLASSIC.FNT build/DEFAULT.IST build/PAINT.IST \
   build/DEFAULT.SPR build/HAND.SPR "$SYS/"
cp assets/WELCOME.TXT "$SYS/"
cp assets/penguin.PIC "$SYS/PENGUIN.PIC"   # sample 200x200 picture (view in Viewer)
