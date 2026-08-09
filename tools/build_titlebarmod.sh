#!/usr/bin/env bash
set -euo pipefail

RASM="${RASM:-rasm}"
TITLEBAR_TBR="${TITLEBAR_TBR:-assets/titlebars/ORIGINAL.TBR}"
command -v "$RASM" >/dev/null || { echo "ERROR: rasm not on PATH" >&2; exit 1; }
[ -f "$TITLEBAR_TBR" ] || { echo "ERROR: title tile not found: $TITLEBAR_TBR" >&2; exit 1; }
[ "$(wc -c < "$TITLEBAR_TBR")" -eq 106 ] || {
    echo "ERROR: fallback title theme must be exactly 106 bytes: $TITLEBAR_TBR" >&2
    exit 1
}

mkdir -p build build/msx build/pcw
cp "$TITLEBAR_TBR" build/TITLEBAR.TBR
rm -rf build/titlebars
mkdir -p build/titlebars
for tbr in assets/titlebars/*.TBR; do
    size="$(wc -c < "$tbr")"
    { [ "$size" -eq 56 ] || [ "$size" -eq 106 ]; } || {
        echo "ERROR: title theme must be 56 (legacy) or 106 bytes: $tbr" >&2
        exit 1
    }
    name="$(basename "$tbr" | tr 'a-z' 'A-Z')"
    cp "$tbr" "build/titlebars/$name"
done
rm -f build/GBTITLE.PAY build/GBTITLE.RAW build/msx/GBTITLE.RAW build/pcw/GBTITLE.RAW
"$RASM" kernel/modules/gbtitle.asm
"$RASM" kernel/modules/gbtitle_install.asm
"$RASM" kernel/modules/gbtitle_install.asm -DPLATFORM_MSX=1 -DTITLE_NATIVE=1
"$RASM" kernel/modules/gbtitle_install.asm -DPLATFORM_PCW=1 -DTITLE_NATIVE=1
for module in build/GBTITLE.RAW build/msx/GBTITLE.RAW build/pcw/GBTITLE.RAW; do
    [ -s "$module" ] || { echo "ERROR: $module not produced" >&2; exit 1; }
done
echo "Built build/GBTITLE.RAW with $TITLEBAR_TBR fallback; staged build/titlebars/*.TBR"
