#!/usr/bin/env bash
# Build the netspike test binary against the cpc-sdcc W5100 C driver (#238 Phase 0).
# Outputs SPIKE.BIN (AMSDOS-headered, load/exec #4000) into this dir.
set -euo pipefail
cd "$(dirname "$0")"
SDCC_BIN="${SDCC_BIN:-$HOME/Dev/sdcc/bin}"
CPCSDCC="${CPCSDCC:-$HOME/Dev/cpc-sdcc}"
SRC="$CPCSDCC/src"
AS="$SDCC_BIN/sdasz80"; CC="$SDCC_BIN/sdcc"; MAKEBIN="$SDCC_BIN/makebin"
"$AS" -o crt0.rel "$SRC/crt0.s"
for f in w5100 netinit net; do
  "$CC" -mz80 --nostdlib --no-std-crt0 -I "$SRC" -c -o $f.rel "$SRC/$f.c"
done
"$CC" -mz80 --nostdlib --no-std-crt0 -I "$SRC" -c -o main.rel main.c
"$CC" -mz80 --nostdlib --no-std-crt0 --code-loc 0x4000 --data-loc 0x7000 \
    -o spike.ihx crt0.rel w5100.rel netinit.rel net.rel main.rel
"$MAKEBIN" -p -o 0x4000 spike.ihx /tmp/netspike_raw.bin
python3 "$SRC/amsdos_wrap.py" /tmp/netspike_raw.bin SPIKE.BIN 4000
rm -f /tmp/netspike_raw.bin *.rel *.ihx *.lst *.sym *.map *.noi
echo "Built tools/netspike/SPIKE.BIN"
