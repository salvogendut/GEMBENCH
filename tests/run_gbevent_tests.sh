#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${CC:-cc}"
SDCC="${SDCC:-sdcc}"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

"$CC" -Wall -Wextra -Werror -std=c99 \
    -I include/gembench -I lib/gb \
    tests/test_gbevent.c lib/gembench/gbevent.c \
    -o "$test_tmp/test_gbevent"
"$test_tmp/test_gbevent"

"$SDCC" -mz80 --opt-code-size -I include/gembench -I lib/gb \
    -c lib/gembench/gbevent.c -o "$test_tmp/gbevent.rel"
test -s "$test_tmp/gbevent.rel"
code_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbevent.rel")"
test -n "$code_hex"
code_bytes=$((16#$code_hex))
if (( code_bytes > 1024 )); then
    echo "FAIL GEMBENCH event runtime is $code_bytes bytes (1024-byte budget)" >&2
    exit 1
fi
echo "ok   GEMBENCH event runtime compiles for Z80 ($code_bytes bytes, caller-owned state)"
