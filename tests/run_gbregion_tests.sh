#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${CC:-cc}"
SDCC="${SDCC:-sdcc}"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

"$CC" -Wall -Wextra -Werror -std=c99 -DGB_REGION_HOST_TEST \
    -I include/gembench tests/test_gbregion.c lib/gembench/gbregion.c \
    -o "$test_tmp/test_gbregion"
"$test_tmp/test_gbregion"

"$SDCC" -mz80 --opt-code-size -I include/gembench \
    -c lib/gembench/gbregion.c -o "$test_tmp/gbregion.rel"
test -s "$test_tmp/gbregion.rel"
code_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbregion.rel")"
data_hex="$(awk '$1 == "A" && $2 == "_DATA" { print $4; exit }' \
    "$test_tmp/gbregion.rel")"
test -n "$code_hex"
code_bytes=$((16#$code_hex))
data_bytes=0
if [ -n "$data_hex" ]; then data_bytes=$((16#$data_hex)); fi
if (( code_bytes > 2048 || data_bytes != 0 )); then
    echo "FAIL visible-region runtime is $code_bytes code + $data_bytes static bytes" >&2
    exit 1
fi
echo "ok   visible-region runtime compiles for Z80 ($code_bytes bytes, no static data)"
