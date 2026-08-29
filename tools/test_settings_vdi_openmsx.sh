#!/usr/bin/env bash
# Build a disposable image and confirm Settings reaches its MSX2 VDI drawing path.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/SETTINGS.RAW ] || {
    echo "ERROR: build/msx/SETTINGS.RAW is missing; run 'make gembench-msx' first" >&2
    exit 1
}
[ -s build/msx-obj/settings/app.noi ] || {
    echo "ERROR: Settings linker symbols are missing; run 'make gembench-msx' first" >&2
    exit 1
}

noi=build/msx-obj/settings/app.noi
lst=build/msx-obj/settings/main.lst
noi_addr() {
    awk -v symbol="$1" '$1 == "DEF" && $2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$noi"
}
lst_offset() {
    awk -v symbol="$1" '$NF ~ /:$/ { label=$NF; sub(/:+$/, "", label) }
        label == symbol { print "0x" $1; found=1; exit }
        END { if (!found) exit 1 }' "$lst"
}
lst_return() {
    awk -v symbol="$1" '
        $NF == symbol ":" { inside=1; next }
        inside && /; Function / { exit }
        inside && $2 == "C9" && $NF == "ret" { value="0x" $1 }
        END { if (value == "") exit 1; print value }' "$lst"
}

export GEMBENCH_SETTINGS_VDI_INIT="$(noi_addr _gb_vdi_init)"
export GEMBENCH_SETTINGS_VDI_FILL="$(noi_addr _gb_vdi_fill)"
export GEMBENCH_SETTINGS_VDI_FRAME="$(noi_addr _gb_vdi_frame)"
export GEMBENCH_SETTINGS_GB_FILL="$(noi_addr _gb_fill)"
export GEMBENCH_SETTINGS_GB_FRAME="$(noi_addr _gb_frame)"
export GEMBENCH_SETTINGS_MAIN="$(noi_addr _main)"
code_base=$((GEMBENCH_SETTINGS_MAIN - $(lst_offset _main)))
data_base="$(noi_addr s__DATA)"
export GEMBENCH_SETTINGS_DRAW="$(printf '0x%X\n' \
    $((code_base + $(lst_offset _s_draw))))"
export GEMBENCH_SETTINGS_DRAW_RET="$(printf '0x%X\n' \
    $((code_base + $(lst_return _s_draw))))"
export GEMBENCH_SETTINGS_COLP_RET="$(printf '0x%X\n' \
    $((code_base + $(lst_return _colp_draw))))"
export GEMBENCH_SETTINGS_PICKER_STATE="$(printf '0x%X\n' \
    $((data_base + $(lst_offset _picker_state))))"
probe_offset=$((GEMBENCH_SETTINGS_VDI_INIT - 0x4000))
export GEMBENCH_SETTINGS_PROBE="$(
    od -An -tu1 -j "$probe_offset" -N 8 build/msx/SETTINGS.RAW |
        awk '{$1=$1; gsub(/ /, ","); print}'
)"
export GEMBENCH_SETTINGS_OUTPUT="$PWD/build/msx/settings-vdi-openmsx.txt"
export GEMBENCH_SETTINGS_SCREENSHOT="$PWD/build/msx/settings-vdi.png"
if [ "${MSX_HEADLESS:-0}" = 1 ]; then
    export GEMBENCH_SETTINGS_SCREENSHOTS=0
else
    export GEMBENCH_SETTINGS_SCREENSHOTS=1
fi

mkdir -p build/msx
stage=$(mktemp -d -p build/msx settings-vdi-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp build/msx/SETTINGS.RAW "$stage/card/A.APP"
tools/build_msx_img.sh "$stage/card" "$stage/settings-vdi.img"

export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/settings_vdi_openmsx.tcl
tools/run_msx.sh "$stage/settings-vdi.img"

sed -n '1,20p' "$GEMBENCH_SETTINGS_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_SETTINGS_OUTPUT"
grep -qx 'MAIN_SEEN=1' "$GEMBENCH_SETTINGS_OUTPUT"
grep -qx 'OUTER_DRAW_SEEN=1' "$GEMBENCH_SETTINGS_OUTPUT"
grep -qx 'OUTER_DRAW_DONE=1' "$GEMBENCH_SETTINGS_OUTPUT"
grep -qx 'PICKER_STATE=1' "$GEMBENCH_SETTINGS_OUTPUT"
grep -q '^EDITOR_DRAWS=[1-9][0-9]*$' "$GEMBENCH_SETTINGS_OUTPUT"
grep -q '^DRAW_CALLS=F:18,24,58,184,1 ' "$GEMBENCH_SETTINGS_OUTPUT"
