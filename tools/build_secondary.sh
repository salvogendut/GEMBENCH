#!/usr/bin/env bash
# Build one fixed-origin, data-free MSX2 secondary-code image at 0x4000.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:?usage: build_secondary.sh <source.s> <out.raw>}"
OUT="${2:?usage: build_secondary.sh <source.s> <out.raw>}"
SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"
name="$(basename "$SOURCE" .s)"
work="build/msx-secondary/$name"
mkdir -p "$work" "$(dirname "$OUT")"
. tools/build_cache.sh

deps=("$0" tools/build_cache.sh "$SOURCE")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' "build_secondary.v1" "SOURCE=$SOURCE" \
    "SDCC=$SDCC" "SDAS=$SDAS" "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

"$SDAS" -o "$work/secondary.rel" "$SOURCE"
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x4000 --data-loc 0x7F00 \
    "$work/secondary.rel" -o "$work/secondary.ihx"
"$MAKEBIN" -p "$work/secondary.ihx" "$work/secondary.bin"
tail -c +16385 "$work/secondary.bin" > "$OUT"
size=$(stat -c%s "$OUT")
if (( size == 0 || size > 16384 )); then
    echo "ERROR: $SOURCE produced an invalid $size-byte secondary image" >&2
    exit 1
fi
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($size bytes) from $SOURCE"
