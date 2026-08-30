#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${CC:-cc}"
SDCC="${SDCC:-sdcc}"
SDAS="$(dirname "$(command -v "$SDCC")")/sdasz80"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

"$CC" -std=c99 -Wall -Wextra -Werror -DGB_MSX2 \
    -I lib/gb -I include/gembench tests/test_gbfsctx.c \
    -o "$test_tmp/test_gbfsctx"
"$test_tmp/test_gbfsctx"

"$SDCC" -mz80 --std-c99 -DGB_MSX2 -I lib/gb -I include/gembench \
    -c tests/test_gbfsctx.c -o "$test_tmp/test_gbfsctx.rel"
"$SDAS" -o "$test_tmp/gbfsctx.rel" lib/gembench/gbfsctx.s
wrapper_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbfsctx.rel")"
test -n "$wrapper_hex"
wrapper_bytes="$((16#$wrapper_hex))"
if (( wrapper_bytes > 8 )); then
    echo "FAIL gbfsctx gate is $wrapper_bytes bytes" >&2
    exit 1
fi
echo "ok   gbfsctx gate is $wrapper_bytes Z80 bytes"

bash tools/build_fsctxmod.sh "$test_tmp/GBFSCTX.RAW"
test -s "$test_tmp/GBFSCTX.RAW"
