#!/usr/bin/env bash
set -euo pipefail

RASM="${RASM:-rasm}"
TITLEBAR_TBR="${TITLEBAR_TBR:-assets/titlebars/ORIGINAL.TBR}"
GADGET_GDT="${GADGET_GDT:-assets/gadgets/ORIGINAL.GDT}"
command -v "$RASM" >/dev/null || { echo "ERROR: rasm not on PATH" >&2; exit 1; }
[ -f "$TITLEBAR_TBR" ] || { echo "ERROR: title tile not found: $TITLEBAR_TBR" >&2; exit 1; }
[ "$(wc -c < "$TITLEBAR_TBR")" -eq 56 ] || {
    echo "ERROR: fallback title tile must be exactly 56 bytes: $TITLEBAR_TBR" >&2
    exit 1
}
[ -f "$GADGET_GDT" ] || { echo "ERROR: gadget theme not found: $GADGET_GDT" >&2; exit 1; }
[ "$(wc -c < "$GADGET_GDT")" -eq 50 ] || {
    echo "ERROR: fallback gadget theme must be exactly 50 bytes: $GADGET_GDT" >&2
    exit 1
}

mkdir -p build build/msx
cat "$TITLEBAR_TBR" "$GADGET_GDT" > build/TITLEBAR.TBR
rm -rf build/titlebars
mkdir -p build/titlebars
for tbr in assets/titlebars/*.TBR; do
    size="$(wc -c < "$tbr")"
    { [ "$size" -eq 56 ] || [ "$size" -eq 106 ]; } || {
        echo "ERROR: title theme must be 56 bytes (or 106-byte legacy combined): $tbr" >&2
        exit 1
    }
    name="$(basename "$tbr" | tr 'a-z' 'A-Z')"
    cp "$tbr" "build/titlebars/$name"
done
rm -rf build/gadgets
mkdir -p build/gadgets
for gdt in assets/gadgets/*.GDT; do
    size="$(wc -c < "$gdt")"
    [ "$size" -eq 50 ] || {
        echo "ERROR: gadget theme must be 50 bytes: $gdt" >&2
        exit 1
    }
    name="$(basename "$gdt" | tr 'a-z' 'A-Z')"
    cp "$gdt" "build/gadgets/$name"
done
rm -f build/GBTITLE.PAY build/GBTITLE.RAW build/msx/GBTITLE.RAW
"$RASM" kernel/modules/gbtitle.asm
"$RASM" kernel/modules/gbtitle_install.asm
"$RASM" kernel/modules/gbtitle_install.asm -DPLATFORM_MSX=1 -DTITLE_NATIVE=1
for module in build/GBTITLE.RAW build/msx/GBTITLE.RAW; do
    [ -s "$module" ] || { echo "ERROR: $module not produced" >&2; exit 1; }
done
echo "Built CPC/MSX GBTITLE.RAW with $TITLEBAR_TBR + $GADGET_GDT fallback; staged TBR/GDT assets"
