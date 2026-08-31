#!/usr/bin/env bash
# Exercise typed text copy/paste and type mismatch through two MSX2 Notepads.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/NOTEPAD.RAW ] || {
    echo "ERROR: build/msx/NOTEPAD.RAW is missing; run 'make geobench-msx' first" >&2
    exit 1
}
[ -s build/msx-obj/notepad/app.noi ] || {
    echo "ERROR: Notepad symbols are missing; run 'make geobench-msx' first" >&2
    exit 1
}
cmp -s build/msx/NOTEPAD.RAW QA/MSX/CARD/GBENCH/NOTEPAD.APP || {
    echo "ERROR: staged NOTEPAD.APP does not match build/msx/NOTEPAD.RAW; run 'make geobench-msx' first" >&2
    exit 1
}

sym=build/msx-obj/notepad/main.sym
noi=build/msx-obj/notepad/app.noi
sym_offset() {
    awk -v symbol="$1" '$2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$sym"
}
noi_addr() {
    awk -v symbol="$1" '$1 == "DEF" && $2 == symbol { print $3; found=1; exit }
        END { if (!found) exit 1 }' "$noi"
}
hexsum() { printf '0x%X\n' "$(( $1 + $2 ))"; }

main_abs="$(noi_addr _main)"
main_rel="$(sym_offset _main)"
code_base=$((main_abs - 0x$main_rel))
data_base=$(( $(noi_addr s__DATA) ))
try_close_rel=$((16#$(sym_offset _try_close)))

export GEMBENCH_SCRAP_MAIN="$main_abs"
export GEMBENCH_SCRAP_LEN="$(hexsum "$data_base" "0x$(sym_offset _len)")"
export GEMBENCH_SCRAP_BUF="$(hexsum "$data_base" "0x$(sym_offset _buf)")"
# paste_clip's common epilogue begins three bytes before the following function.
export GEMBENCH_SCRAP_PASTE_RETURN="$(hexsum "$code_base" "$((try_close_rel - 3))")"
export GEMBENCH_SCRAP_PASTE_ENTRY="$(hexsum "$code_base" "0x$(sym_offset _paste_clip)")"
export GEMBENCH_SCRAP_SELECT_ALL="$(hexsum "$code_base" "0x$(sym_offset _select_all)")"
export GEMBENCH_SCRAP_COPY_SEL="$(hexsum "$code_base" "0x$(sym_offset _copy_sel)")"

main_file_offset=$((main_abs - 0x4000))
read -r sig0 sig1 sig2 < <(od -An -t u1 -j "$main_file_offset" -N 3 build/msx/NOTEPAD.RAW)
export GEMBENCH_SCRAP_SIG0="$sig0"
export GEMBENCH_SCRAP_SIG1="$sig1"
export GEMBENCH_SCRAP_SIG2="$sig2"

mkdir -p build/msx
stage=$(mktemp -d -p build/msx typed-scrap-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp build/msx/NOTEPAD.RAW "$stage/card/A.APP"
cp build/msx/NOTEPAD.RAW "$stage/card/B.APP"
tools/build_msx_img.sh "$stage/card" "$stage/typed-scrap.img"

export GEMBENCH_SCRAP_OUTPUT="$PWD/build/msx/typed-scrap-openmsx.txt"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/typed_scrap_openmsx.tcl
tools/run_msx.sh "$stage/typed-scrap.img"

sed -n '1,30p' "$GEMBENCH_SCRAP_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_SCRAP_OUTPUT"
