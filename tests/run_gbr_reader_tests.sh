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

"$CC" -Wall -Wextra -Werror -std=c99 -DGB_MSX2 -DGBR_FORM_RUNTIME \
    -I include/gembench -I lib/gb \
    tests/test_gbr_object.c lib/gembench/gbr_reader.c \
    lib/gembench/gbr_object.c lib/gembench/gbr_form.c \
    -o "$test_tmp/test_gbr_object"
"$test_tmp/test_gbr_object"

"$CC" -Wall -Wextra -Werror -std=c99 -DGB_MSX2 \
    -DGBR_GRAPHICS_RUNTIME -I include/gembench -I lib/gb \
    tests/test_gbr_graphics.c lib/gembench/gbr_reader.c \
    lib/gembench/gbr_object.c lib/gembench/gbvdi.c \
    lib/gembench/gbvdi_raster.c -o "$test_tmp/test_gbr_graphics"
"$test_tmp/test_gbr_graphics"

"$CC" -Wall -Wextra -Werror -std=c99 -DGBR_MENU_HOST_TEST \
    -I include/gembench -I apps/filemgr \
    tests/test_gbr_menu.c lib/gembench/gbr_menu.c \
    -o "$test_tmp/test_gbr_menu"
"$test_tmp/test_gbr_menu"

# Link the same behavioral suite across the proposed placement boundary: the
# application-side state/hit/focus half and the renderer-only resident half.
# Rename the renderer's private geometry copy so the two halves can coexist in
# one host process while gbr_draw_tree resolves only to the resident candidate.
"$CC" -Wall -Wextra -Werror -std=c99 -DGB_MSX2 -DGBR_FORM_RUNTIME \
    -DGBR_RESIDENT_DRAW -I include/gembench -I lib/gb \
    -c lib/gembench/gbr_object.c -o "$test_tmp/gbr_object_app.o"
"$CC" -Wall -Wextra -Werror -std=c99 -DGB_MSX2 -DGBR_FORM_RUNTIME \
    -DGBR_RENDERER_ONLY -Dgbr_object_rect=gbr_resident_object_rect \
    -I include/gembench -I lib/gb \
    -c lib/gembench/gbr_object.c -o "$test_tmp/gbr_object_resident.o"
"$CC" -Wall -Wextra -Werror -std=c99 -DGB_MSX2 -DGBR_FORM_RUNTIME \
    -I include/gembench -I lib/gb tests/test_gbr_object.c \
    lib/gembench/gbr_reader.c "$test_tmp/gbr_object_app.o" \
    "$test_tmp/gbr_object_resident.o" lib/gembench/gbr_form.c \
    -o "$test_tmp/test_gbr_resident_split"
"$test_tmp/test_gbr_resident_split"
echo "ok   resident-renderer split matches app-linked behavior"

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

"$SDCC" -mz80 --opt-code-size -DGBR_READER_ACCESS_ONLY \
    -DGBR_READER_NO_FIND_TREE -I include/gembench \
    -c lib/gembench/gbr_reader.c -o "$test_tmp/gbr_reader_access.rel"
test -s "$test_tmp/gbr_reader_access.rel"
access_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbr_reader_access.rel")"
test -n "$access_hex"
access_bytes=$((16#$access_hex))
if (( access_bytes > 1024 )); then
    echo "FAIL embedded GBR accessor is $access_bytes bytes (1024-byte budget)" >&2
    exit 1
fi
echo "ok   embedded GBR accessor compiles for Z80 with SDCC ($access_bytes bytes, no static data)"

"$SDCC" -mz80 --opt-code-size -DGBR_MENU_HOST_TEST -I include/gembench \
    -c lib/gembench/gbr_menu.c -o "$test_tmp/gbr_menu.rel"
test -s "$test_tmp/gbr_menu.rel"
menu_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbr_menu.rel")"
test -n "$menu_hex"
menu_bytes=$((16#$menu_hex))
if (( menu_bytes > 2048 )); then
    echo "FAIL GBR menu runtime is $menu_bytes bytes (2048-byte budget)" >&2
    exit 1
fi
echo "ok   GBR menu runtime compiles for Z80 with SDCC ($menu_bytes bytes, caller-owned state)"

"$SDCC" -mz80 --opt-code-size -DGB_MSX2 -I include/gembench -I lib/gb \
    -c lib/gembench/gbr_object.c -o "$test_tmp/gbr_object.rel"
test -s "$test_tmp/gbr_object.rel"
object_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' "$test_tmp/gbr_object.rel")"
test -n "$object_hex"
object_bytes=$((16#$object_hex))
if (( object_bytes > 4096 )); then
    echo "FAIL GBR object runtime is $object_bytes bytes (4096-byte budget)" >&2
    exit 1
fi
echo "ok   GBR object runtime compiles for Z80 with SDCC ($object_bytes bytes, no static data)"

"$SDCC" -mz80 --opt-code-size -DGB_MSX2 -DGBR_GRAPHICS_RUNTIME \
    -I include/gembench -I lib/gb \
    -c lib/gembench/gbr_object.c -o "$test_tmp/gbr_graphics.rel"
test -s "$test_tmp/gbr_graphics.rel"
graphics_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbr_graphics.rel")"
test -n "$graphics_hex"
graphics_bytes=$((16#$graphics_hex))
if (( graphics_bytes > 6144 )); then
    echo "FAIL GBR graphics runtime is $graphics_bytes bytes (6144-byte budget)" >&2
    exit 1
fi
echo "ok   GBR graphics runtime compiles for Z80 with SDCC ($graphics_bytes bytes, caller-owned state)"

"$SDCC" -mz80 --opt-code-size -DGB_MSX2 -DGBR_FORM_RUNTIME \
    -I include/gembench -I lib/gb \
    -c lib/gembench/gbr_object.c -o "$test_tmp/gbr_form_runtime.rel"
test -s "$test_tmp/gbr_form_runtime.rel"
form_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' "$test_tmp/gbr_form_runtime.rel")"
test -n "$form_hex"
form_bytes=$((16#$form_hex))
if (( form_bytes > 6144 )); then
    echo "FAIL GBR form runtime is $form_bytes bytes (6144-byte budget)" >&2
    exit 1
fi
echo "ok   GBR form runtime compiles for Z80 with SDCC ($form_bytes bytes, no static data)"

"$SDCC" -mz80 --opt-code-size -I include/gembench \
    -c lib/gembench/gbr_form.c -o "$test_tmp/gbr_form.rel"
test -s "$test_tmp/gbr_form.rel"
engine_hex="$(awk '$1 == "A" && $2 == "_CODE" { print $4; exit }' \
    "$test_tmp/gbr_form.rel")"
test -n "$engine_hex"
engine_bytes=$((16#$engine_hex))
if (( engine_bytes > 2048 )); then
    echo "FAIL GBR form engine is $engine_bytes bytes (2048-byte budget)" >&2
    exit 1
fi
echo "ok   GBR form engine compiles for Z80 with SDCC ($engine_bytes bytes, no static data)"
