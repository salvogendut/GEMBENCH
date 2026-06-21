#!/usr/bin/env bash
# stage_dist.sh <outdir>: stage the ONE unified GEOBENCH card (#134 + #136 + #174).
# One card boots on BOTH an M4 board and an Albireo (CH376) machine: it carries both
# kernels and a GB.BAS loader that detects the hardware and RUN"s the right one.
# On-card layout:
#   GB.BAS       - BASIC loader: POKEs a tiny detector (tools/m4detect.asm), CALLs it,
#                  and RUN"s GBM4 if the M4 firmware ROM is in slot 6 else GBALB. (A
#                  machine-code loader is impossible under UniDOS/M4ROM - see memory
#                  geobench-loader-136 - hence BASIC.)
#   GBM4.BIN     - M4-board SD kernel (#174, raw-sector C_SDREAD backend).
#   GBALB.BIN    - Albireo (CH376) kernel. Both: real 128-byte AMSDOS header, exec 0x8000;
#                  both fall back to floppy A when no card is present.
#   GEOBENCH.CFG - config (root; read before the kernel enters /GBENCH)
#   GBENCH/      - everything the kernel loads at boot (apps/modules/fonts/icons/cursor)
# Boot: RUN"GB -> (detect) -> RUN"GBM4 | RUN"GBALB -> the kernel reads /GBENCH. IDE is
# retired (frozen on branch legacy-ide; still buildable via STORAGE=ide but not shipped).
# Needs build/GBM4.RAW + build/GBALB.RAW.
#   * <app>.APP / GBCFG/GBFAT/FLOPPYSV.BIN - HEADERLESS raw images (kernel loads them)
#   * GB.BAS / GEOBENCH.CFG - written with CR+LF line endings (the CPC requires them)
set -euo pipefail
cd "$(dirname "$0")/.."
RASM="${RASM:-rasm}"

OUT="${1:?usage: tools/stage_dist.sh <outdir>}"
SYS="$OUT/GBENCH"                    # the system folder (#174: <=7 chars so the M4's
                                     # '>'-prefixed dir listing round-trips it; was /GEOBENCH)
mkdir -p "$SYS"

# --- root: the detecting loader, BOTH kernels, the config ---------------------
# Assemble the M4-detector and bake its bytes into a BASIC loader: POKE it to #4000
# (free until the kernel loads at #8000 - no MEMORY juggling, which breaks M4ROM's
# RUN" of the kernel above a lowered HIMEM), CALL it, PEEK its verdict at #4030, and
# RUN" the matching kernel. ASCII BASIC with CR+LF, as the CPC requires.
"$RASM" tools/m4detect.asm -ob build/m4detect.bin >/dev/null
python3 - "$OUT/GB.BAS" build/m4detect.bin <<'PY'
import sys
out, binf = sys.argv[1], sys.argv[2]
b = open(binf, 'rb').read()
end = 0x4000 + len(b) - 1
data = ",".join("&%02X" % x for x in b)
lines = [
    "10 FOR i=&4000 TO &%X:READ d:POKE i,d:NEXT" % end,
    "20 CALL &4000",
    '30 IF PEEK(&4030)=1 THEN RUN"GBM4',
    '40 RUN"GBALB',
    "50 DATA " + data,
]
open(out, 'wb').write(("\r\n".join(lines) + "\r\n").encode('ascii'))
PY
python3 tools/amsdos_header.py build/GBM4.RAW  "$OUT/GBM4.BIN"  GBM4  BIN 0x8000
python3 tools/amsdos_header.py build/GBALB.RAW "$OUT/GBALB.BIN" GBALB BIN 0x8000
printf 'FONT=DEFAULT\r\nICONS=REFINED\r\nCURSOR=DEFAULT\r\nVIEW=DEFAULT\r\n' \
    > "$OUT/GEOBENCH.CFG"

# --- /GBENCH: apps, modules, assets -------------------------------------------
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
