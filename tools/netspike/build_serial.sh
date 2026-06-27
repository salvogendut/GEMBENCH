#!/usr/bin/env bash
# Build the serial spike (USIFAC port I/O) -> SERSPK.BIN (cpcbios + crt0, no driver).
set -euo pipefail
cd "$(dirname "$0")"
SDCC_BIN="${SDCC_BIN:-$HOME/Dev/sdcc/bin}"
CPCSDCC="${CPCSDCC:-$HOME/Dev/cpc-sdcc}"
SRC="$CPCSDCC/src"
AS="$SDCC_BIN/sdasz80"; CC="$SDCC_BIN/sdcc"; MAKEBIN="$SDCC_BIN/makebin"
"$AS" -o crt0.rel "$SRC/crt0.s"
"$CC" -mz80 --nostdlib --no-std-crt0 -I "$SRC" -c -o serialmain.rel serialmain.c
"$CC" -mz80 --nostdlib --no-std-crt0 --code-loc 0x4000 --data-loc 0x7000 \
    -o ser.ihx crt0.rel serialmain.rel
"$MAKEBIN" -p -o 0x4000 ser.ihx /tmp/serspk_raw.bin
python3 "$SRC/amsdos_wrap.py" /tmp/serspk_raw.bin SERSPK.BIN 4000
rm -f /tmp/serspk_raw.bin *.rel *.ihx *.lst *.sym *.map *.noi
echo "Built tools/netspike/SERSPK.BIN"
