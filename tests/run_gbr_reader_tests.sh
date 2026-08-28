#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${CC:-cc}"
SDCC="${SDCC:-sdcc}"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

"$CC" -Wall -Wextra -Werror -std=c99 -I include/gembench \
    tests/test_gbr_reader.c lib/gembench/gbr_reader.c \
    -o "$test_tmp/test_gbr_reader"
"$test_tmp/test_gbr_reader"

"$SDCC" -mz80 --opt-code-size -I include/gembench \
    -c lib/gembench/gbr_reader.c -o "$test_tmp/gbr_reader.rel"
test -s "$test_tmp/gbr_reader.rel"
code_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' "$test_tmp/gbr_reader.rel")"
test -n "$code_hex"
code_bytes=$((16#$code_hex))
if (( code_bytes > 4096 )); then
    echo "FAIL GBR reader Z80 code is $code_bytes bytes (4096-byte budget)" >&2
    exit 1
fi
echo "ok   GBR reader compiles for Z80 with SDCC ($code_bytes bytes, no static data)"
