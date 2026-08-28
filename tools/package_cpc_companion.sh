#!/usr/bin/env bash
# Repack only the CPC companion floppy from already-built application payloads.
set -euo pipefail
cd "$(dirname "$0")/.."

RASM="${RASM:-rasm}"
OUT="${1:-QA/CPC/Floppies/COMPANION.DSK}"

mkdir -p "$(dirname "$OUT")"
rm -f build/companion.dsk
"$RASM" kernel/pack_comp1.asm -eo
"$RASM" kernel/pack_comp2.asm -eo
"$RASM" kernel/pack_comp3.asm -eo
"$RASM" kernel/pack_comp4.asm -eo
"$RASM" kernel/pack_comp5.asm -eo
cp build/companion.dsk "$OUT"

echo "  + $OUT (Companion floppy: Paint/Telnet/Wget/Browser/Shell/Mahjong/Xaos/Calc + helpers/savers)"
