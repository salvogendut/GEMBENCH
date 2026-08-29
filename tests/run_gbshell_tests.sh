#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${CC:-cc}"
SDCC="${SDCC:-sdcc}"
SDAS="$(dirname "$(command -v "$SDCC")")/sdasz80"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

"$CC" -std=c99 -Wall -Wextra -Werror \
    -I include/gembench \
    tests/test_gbshell.c lib/gembench/gbshell.c lib/gembench/gbaccessory.c \
    -o "$test_tmp/test_gbshell"
"$test_tmp/test_gbshell"

"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer \
    -I include/gembench -c lib/gembench/gbshell.c \
    -o "$test_tmp/gbshell.rel"
"$SDAS" -o "$test_tmp/gbshell_client.rel" lib/gembench/gbshell_client.s
"$SDAS" -o "$test_tmp/gbshell_register.rel" lib/gembench/gbshell_register.s
"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer \
    -I include/gembench -c lib/gembench/gbaccessory.c \
    -o "$test_tmp/gbaccessory.rel"
"$SDAS" -o "$test_tmp/gbshell_accessory_client.rel" lib/gembench/gbshell_accessory_client.s
"$SDAS" -o "$test_tmp/gbshell_accessory_register.rel" lib/gembench/gbshell_accessory_register.s

code_size() {
    local value
    value="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' "$1")"
    test -n "$value"
    printf '%d\n' "$((16#$value))"
}

request_bytes="$(code_size "$test_tmp/gbshell.rel")"
client_bytes="$(code_size "$test_tmp/gbshell_client.rel")"
register_bytes="$(code_size "$test_tmp/gbshell_register.rel")"
accessory_bytes="$(code_size "$test_tmp/gbaccessory.rel")"
accessory_client_bytes="$(code_size "$test_tmp/gbshell_accessory_client.rel")"
accessory_register_bytes="$(code_size "$test_tmp/gbshell_accessory_register.rel")"
if (( request_bytes > 64 || client_bytes > 32 || register_bytes > 16 ||
      accessory_bytes > 64 || accessory_client_bytes > 16 || accessory_register_bytes > 16 )); then
    echo "FAIL shell adapters are $request_bytes/$client_bytes/$register_bytes + $accessory_bytes/$accessory_client_bytes/$accessory_register_bytes bytes" >&2
    exit 1
fi
echo "ok   shell adapters are $request_bytes/$client_bytes/$register_bytes + accessory $accessory_bytes/$accessory_client_bytes/$accessory_register_bytes Z80 bytes"
