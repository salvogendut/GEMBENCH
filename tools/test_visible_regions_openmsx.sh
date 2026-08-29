#!/usr/bin/env bash
# Exercise bounded Desktop visibility through real move, top, and close gestures.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/DESKTOP.RAW ] || {
    echo "ERROR: build/msx/DESKTOP.RAW is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s build/msx-obj/desktop/app.noi ] || {
    echo "ERROR: Desktop symbols are missing; run 'make gembench-msx' first" >&2
    exit 1
}
cmp -s build/msx/DESKTOP.RAW QA/MSX/CARD/GBENCH/DESKTOP.APP || {
    echo "ERROR: staged DESKTOP.APP does not match the build; run 'make gembench-msx' first" >&2
    exit 1
}

main_sym=build/msx-obj/desktop/main.sym
region_sym=build/msx-obj/desktop/gbregion.sym
noi=build/msx-obj/desktop/app.noi

symbol_offset() {
    local file=$1 symbol=$2
    awk -v symbol="$symbol" '$2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$file"
}
noi_addr() {
    awk -v symbol="$1" '$1 == "DEF" && $2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$noi"
}
hexsum() { printf '0x%X\n' "$(( $1 + $2 ))"; }

main_abs=$(noi_addr _main)
main_offset=$(symbol_offset "$main_sym" _main)
code_base=$((main_abs - 0x$main_offset))
data_base=$(( $(noi_addr s__DATA) ))
paint_visible_offset=$(symbol_offset "$main_sym" _paint_visible)
paint_visible_abs=$(hexsum "$code_base" "0x$paint_visible_offset")
paint_return_offset=$(awk '
    /_paint_visible:/ { inside=1; next }
    inside && $NF == "ret" { print "0x" $1; found=1; exit }
    END { if (!found) exit 1 }
' build/msx-obj/desktop/main.lst)
paint_return_abs=$(hexsum "$code_base" "$paint_return_offset")
begin_call_offset=$(awk '$NF == "_gb_visible_begin" && $(NF-1) == "call" {
        print "0x" $1; found=1; exit
    } END { if (!found) exit 1 }' build/msx-obj/desktop/main.lst)
after_begin_abs=$(hexsum "$code_base" "$((begin_call_offset + 3))")
state_offset=$(symbol_offset "$main_sym" _desktop_regions)
state_abs=$(hexsum "$data_base" "0x$state_offset")

region_begin_abs=$(noi_addr _gb_visible_begin)
region_begin_offset=$(symbol_offset "$region_sym" _gb_visible_begin)
region_base=$((region_begin_abs - 0x$region_begin_offset))
for pair in \
    RECT_COPY:_rect_copy \
    RECT_INTERSECT:_rect_intersect \
    EMIT:_emit \
    SUBTRACT:_subtract_cover; do
    name=${pair%%:*}
    symbol=${pair#*:}
    offset=$(symbol_offset "$region_sym" "$symbol")
    printf -v "region_$name" '0x%X' "$((region_base + 0x$offset))"
done

main_file_offset=$((main_abs - 0x4000))
read -r sig0 sig1 sig2 < <(od -An -t u1 -j "$main_file_offset" -N 3 build/msx/DESKTOP.RAW)

export GEMBENCH_REGION_OUTPUT="$PWD/build/msx/visible-regions-openmsx.txt"
export GEMBENCH_REGION_SCREEN_DIR="$PWD/build/msx/visible-regions-screens"
export GEMBENCH_REGION_MAIN="$main_abs"
export GEMBENCH_REGION_SIG0="$sig0"
export GEMBENCH_REGION_SIG1="$sig1"
export GEMBENCH_REGION_SIG2="$sig2"
export GEMBENCH_REGION_PAINT_VISIBLE="$paint_visible_abs"
export GEMBENCH_REGION_PAINT_RETURN="$paint_return_abs"
export GEMBENCH_REGION_BEGIN="$region_begin_abs"
export GEMBENCH_REGION_AFTER_BEGIN="$after_begin_abs"
export GEMBENCH_REGION_STATE="$state_abs"
export GEMBENCH_REGION_RECT_COPY="$region_RECT_COPY"
export GEMBENCH_REGION_RECT_INTERSECT="$region_RECT_INTERSECT"
export GEMBENCH_REGION_EMIT="$region_EMIT"
export GEMBENCH_REGION_SUBTRACT="$region_SUBTRACT"
if [ "${MSX_HEADLESS:-0}" = 1 ]; then
    export GEMBENCH_REGION_SCREENSHOTS=0
else
    export GEMBENCH_REGION_SCREENSHOTS=1
fi

stage=$(mktemp -d -p build/msx visible-regions-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp build/msx/CLOCK.RAW "$stage/card/A.APP"
tools/build_msx_img.sh "$stage/card" "$stage/visible-regions.img"

mkdir -p "$GEMBENCH_REGION_SCREEN_DIR"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/visible_regions_openmsx.tcl
tools/run_msx.sh "$stage/visible-regions.img"

sed -n '1,40p' "$GEMBENCH_REGION_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_REGION_OUTPUT"
