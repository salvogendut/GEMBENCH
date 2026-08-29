#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${CC:-cc}"
SDCC="${SDCC:-sdcc}"
SDAS="$(dirname "$(command -v "$SDCC")")/sdasz80"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

"$CC" -Wall -Wextra -Werror -std=c99 -DGB_SCRAP_HOST_TEST \
    -I lib/gb -I include/gembench tests/test_gbscrap.c \
    lib/gembench/gbscrap.c -o "$test_tmp/test_gbscrap"
"$test_tmp/test_gbscrap"

"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer \
    -I lib/gb -I include/gembench -c lib/gembench/gbscrap.c \
    -o "$test_tmp/gbscrap.rel"
test -s "$test_tmp/gbscrap.rel"
code_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbscrap.rel")"
data_hex="$(awk '$1 == "A" && $2 == "_DATA" { print $4; exit }' \
    "$test_tmp/gbscrap.rel")"
test -n "$code_hex"
code_bytes=$((16#$code_hex))
data_bytes=0
if [ -n "$data_hex" ]; then data_bytes=$((16#$data_hex)); fi
if (( code_bytes > 1536 || data_bytes != 0 )); then
    echo "FAIL typed-scrap runtime is $code_bytes code + $data_bytes static bytes" >&2
    exit 1
fi
echo "ok   typed-scrap runtime compiles for Z80 ($code_bytes bytes, no static data)"

"$SDAS" -o "$test_tmp/gbscrap_text.rel" lib/gembench/gbscrap_text.s
text_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbscrap_text.rel")"
test -n "$text_hex"
text_bytes=$((16#$text_hex))
if (( text_bytes > 128 )); then
    echo "FAIL compact typed-text adapter is $text_bytes bytes" >&2
    exit 1
fi
echo "ok   compact typed-text adapter is $text_bytes Z80 bytes"
