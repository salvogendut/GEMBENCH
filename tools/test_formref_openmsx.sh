#!/usr/bin/env bash
# Build a disposable openMSX image and exercise the MSX2 GBR-backed FormRef.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/FORMREF.RAW ] || {
    echo "ERROR: build/msx/FORMREF.RAW is missing; run 'make formref' first" >&2
    exit 1
}
[ -s build/msx-obj/formref/app.noi ] || {
    echo "ERROR: build/msx-obj/formref/app.noi is missing; run 'make formref' first" >&2
    exit 1
}

noi=build/msx-obj/formref/app.noi
lst=build/msx-obj/formref/main.lst
noi_addr() {
    awk -v symbol="$1" '$1 == "DEF" && $2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$noi"
}
lst_offset() {
    awk -v symbol="$1" '$NF ~ /:$/ { label=$NF; sub(/:+$/, "", label) }
        label == symbol { print "0x" $1; found=1; exit }
        END { if (!found) exit 1 }' "$lst"
}
lst_call_offset() {
    awk -v symbol="$1" '$NF == symbol && $(NF-1) == "call" {
            print "0x" $1; found=1; exit
        } END { if (!found) exit 1 }' "$lst"
}
hexsum() { printf '0x%X\n' "$(( $1 + $2 ))"; }

main_abs="$(noi_addr _main)"
main_local="$(lst_offset _main)"
code_base=$((main_abs - main_local))
data_base=$(( $(noi_addr s__DATA) ))
init_base=$(( $(noi_addr s__INITIALIZED) ))
export GEMBENCH_FORMREF_START="$(noi_addr _start)"
export GEMBENCH_FORMREF_MAIN="$main_abs"
export GEMBENCH_FORMREF_RESOURCE_OPEN="$(hexsum "$code_base" "$(lst_offset _form_resource_open)")"
export GEMBENCH_FORMREF_OPEN_FORM="$(hexsum "$code_base" "$(lst_offset _open_form)")"
export GEMBENCH_FORMREF_APP_DRAW="$(hexsum "$code_base" "$(lst_offset _app_draw)")"
export GEMBENCH_FORMREF_DRAW_TREE="$(noi_addr _gbr_draw_tree)"
draw_call_offset=$(( $(lst_call_offset _gbr_draw_tree) + 3 ))
export GEMBENCH_FORMREF_DRAW_RETURN="$(hexsum "$code_base" "$draw_call_offset")"
export GEMBENCH_FORMREF_GBR_READ="$(noi_addr _gbr_read)"
export GEMBENCH_FORMREF_WM_MANAGED="$(noi_addr _gb_wm_managed)"
export GEMBENCH_FORMREF_RESTORE="$(noi_addr _gb_restore_parent)"
export GEMBENCH_FORMREF_RESOURCE_READY="$(hexsum "$data_base" "$(lst_offset _resource_ready)")"
export GEMBENCH_FORMREF_SAVED_STYLE="$(hexsum "$data_base" "$(lst_offset _saved_style)")"
export GEMBENCH_FORMREF_SAVED_LEVEL="$(hexsum "$init_base" "$(lst_offset __xinit__saved_level)")"
if segment_offset="$(lst_offset _form_segment 2>/dev/null)"; then
    export GEMBENCH_FORMREF_RESOURCE="$(hexsum "$data_base" "$(lst_offset _form_resource)")"
    export GEMBENCH_FORMREF_SEGMENT="$(hexsum "$data_base" "$segment_offset")"
    export GEMBENCH_FORMREF_BANKED=1
    export GEMBENCH_FORMREF_SEGMENT_CALL="$(noi_addr _gbr_segment_call)"
else
    export GEMBENCH_FORMREF_RESOURCE="$(hexsum "$init_base" "$(lst_offset _form_resource)")"
    export GEMBENCH_FORMREF_SEGMENT=0
    export GEMBENCH_FORMREF_BANKED=0
    export GEMBENCH_FORMREF_SEGMENT_CALL=0
fi

mkdir -p build/msx
stage=$(mktemp -d -p build/msx formref-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
# Keep the validation image deterministic and offline even when the shipped
# card was built with the optional UNAPI TCP/IP bootstrap enabled.
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
# A short root-level alias makes File Manager navigation deterministic. The
# payload remains byte-for-byte identical to the shipped FormRef application.
cp build/msx/FORMREF.RAW "$stage/card/A.APP"
tools/build_msx_img.sh "$stage/card" "$stage/formref.img"

export GEMBENCH_FORMREF_OUTPUT="$PWD/build/msx/formref-openmsx.txt"
export GEMBENCH_FORMREF_FOCUS_SCREENSHOT="$PWD/build/msx/formref-focus.png"
export GEMBENCH_FORMREF_FINAL_SCREENSHOT="$PWD/build/msx/formref-final.png"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/formref_openmsx.tcl
tools/run_msx.sh "$stage/formref.img"

sed -n '1,40p' "$GEMBENCH_FORMREF_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_FORMREF_OUTPUT"
