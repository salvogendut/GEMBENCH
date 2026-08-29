#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${CC:-cc}"
SDCC="${SDCC:-../sdcc/bin/sdcc}"
SDAS="${SDAS:-../sdcc/bin/sdasz80}"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

"$CC" -std=c99 -Wall -Wextra -Werror -DGB_MSX2 \
    -I include/gembench -I lib/gb \
    tests/test_gbvdi.c lib/gembench/gbvdi.c \
    lib/gembench/gbvdi_raster.c lib/gembench/gbvdi_text.c \
    -o "$test_tmp/test_gbvdi"
"$test_tmp/test_gbvdi"

"$CC" -std=c99 -Wall -Wextra -Werror -DGB_MSX2 -DGB_VDI_BASE_PROFILE \
    -I include/gembench -I lib/gb \
    tests/test_gbvdi_base.c lib/gembench/gbvdi_base.c \
    -o "$test_tmp/test_gbvdi_base"
"$test_tmp/test_gbvdi_base"

"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer \
    --max-allocs-per-node 100000 -DGB_MSX2 \
    -I include/gembench -I lib/gb -c lib/gembench/gbvdi.c \
    -o "$test_tmp/gbvdi.rel"
"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer -DGB_MSX2 \
    --max-allocs-per-node 100000 \
    -DGB_VDI_BASE_PROFILE -I include/gembench -I lib/gb \
    -c lib/gembench/gbvdi_base.c -o "$test_tmp/gbvdi_base.rel"
"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer -DGB_MSX2 \
    -I include/gembench -I lib/gb -c lib/gembench/gbvdi_raster.c \
    -o "$test_tmp/gbvdi_raster.rel"
"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer -DGB_MSX2 \
    -I include/gembench -I lib/gb -c lib/gembench/gbvdi_text.c \
    -o "$test_tmp/gbvdi_text.rel"
"$SDAS" -o "$test_tmp/gbvdi_text_call.rel" lib/gembench/gbvdi_text.s

code_size() {
    local value
    value=$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' "$1")
    printf '%d\n' "$((16#$value))"
}

core_bytes=$(code_size "$test_tmp/gbvdi.rel")
base_bytes=$(code_size "$test_tmp/gbvdi_base.rel")
raster_bytes=$(code_size "$test_tmp/gbvdi_raster.rel")
text_bytes=$(code_size "$test_tmp/gbvdi_text.rel")
text_call_bytes=$(code_size "$test_tmp/gbvdi_text_call.rel")
if (( base_bytes > 768 || core_bytes > 1200 || raster_bytes > 1150 ||
      text_bytes > 768 || text_call_bytes > 32 )); then
    echo "FAIL gbvdi profiles are $base_bytes/$core_bytes/$raster_bytes/$text_bytes/$text_call_bytes bytes" >&2
    exit 1
fi
echo "ok   gbvdi base/core/raster/text/call profiles are $base_bytes/$core_bytes/$raster_bytes/$text_bytes/$text_call_bytes Z80 bytes"
