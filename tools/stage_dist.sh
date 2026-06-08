#!/usr/bin/env bash
# stage_dist.sh <outdir>: copy the COMPLETE GEOBENCH distribution into <outdir> -
# the exact set of files to drop onto a CPC USB/SD drive (or an image). One source
# of truth for the file set, shared by build_kernel.sh (-> QA/) and deploy_ide.sh
# (-> a temp dir it mcopies into the IDE image). Conventions:
#   * GBKERN.BIN        - a real 128-byte AMSDOS header (UniDOS RUN"s it), exec 0x8000
#   * <app>.APP         - HEADERLESS raw images (the kernel loads them to #4000 itself)
#   * GBCFG/GBFAT.BIN   - headerless raw kernel C modules
#   * fonts/icons/cursors/WELCOME.TXT - copied as-is
#   * GEOBENCH.CFG      - written with CR+LF line endings (the CPC requires them)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: tools/stage_dist.sh <outdir>}"
mkdir -p "$OUT"

# kernel: headered
python3 tools/amsdos_header.py build/GBKERN.RAW "$OUT/GBKERN.BIN" GBKERN BIN 0x8000
# launchable apps: headerless raw, .APP
for a in DESKTOP FILEMGR VIEWER NOTEPAD ICONED CLOCK CHELLO; do
    cp "build/$a.RAW" "$OUT/$a.APP"
done
# kernel modules: headerless raw, .BIN
cp build/GBCFG.RAW "$OUT/GBCFG.BIN"
cp build/GBFAT.RAW "$OUT/GBFAT.BIN"
# assets
cp build/DEFAULT.FNT build/CLASSIC.FNT build/DEFAULT.IST \
   build/DEFAULT.SPR build/HAND.SPR "$OUT/"
cp assets/WELCOME.TXT "$OUT/"
# config (CR+LF line endings, as the CPC requires)
printf 'FONT=DEFAULT\r\nICONS=DEFAULT\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\n' \
    > "$OUT/GEOBENCH.CFG"
