#!/usr/bin/env bash
# One platform-neutral computation bank. No application/kernel SDK is linked.
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${1:?usage: build_usecondary.sh SOURCE_DIRECTORY OUTPUT.BIN}"
OUT="${2:?usage: build_usecondary.sh SOURCE_DIRECTORY OUTPUT.BIN}"
SECONDARY_DATA_LOC="${SECONDARY_DATA_LOC:-0x6000}"
SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
work="build/universal-secondary/$(basename "$SOURCE")"
[[ "$SECONDARY_DATA_LOC" =~ ^(0[xX][0-9A-Fa-f]+|[1-9][0-9]*|0)$ ]] || exit 2
(( SECONDARY_DATA_LOC >= 0x4008 && SECONDARY_DATA_LOC <= 0x7F00 )) || exit 2
mkdir -p "$work" "$(dirname "$OUT")"
python3 tools/check_secondary_app.py --source "$SOURCE"
"$BIN/sdasz80" -o "$work/crt0_secondary.rel" lib/gb/crt0_secondary.s
"$SDCC" -mz80 --std-c99 --sdcccall 1 --opt-code-size -c "$SOURCE/main.c" -o "$work/main.rel"
"$SDCC" -mz80 --sdcccall 1 --no-std-crt0 --code-loc 0x4000 --data-loc "$SECONDARY_DATA_LOC" \
    "$work/crt0_secondary.rel" "$work/main.rel" -o "$work/secondary.ihx"
python3 tools/check_app_layout.py "$work/secondary.map" --app "$SOURCE" \
    --data-loc "$SECONDARY_DATA_LOC" --load-limit 0x7F00 --task-stack-reserve 256 --verbose
"$BIN/makebin" -p "$work/secondary.ihx" "$work/secondary.bin"
tail -c +16385 "$work/secondary.bin" > "$OUT"
python3 tools/check_secondary_app.py --source "$SOURCE" --asm "$work/main.asm" \
    --map "$work/secondary.map" --binary "$OUT"
echo "Built computation bank $OUT ($(stat -c%s "$OUT") bytes)"
