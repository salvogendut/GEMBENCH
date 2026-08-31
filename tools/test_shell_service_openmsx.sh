#!/usr/bin/env bash
# Reopen a text document through File Manager and prove that the live Notepad is reused.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -s build/msx/FILEMGR.RAW ] && [ -s build/msx/NOTEPAD.RAW ] || {
    echo "ERROR: MSX apps are missing; run 'make geobench-msx' first" >&2
    exit 1
}
[ -s build/msx/gbkernm7.sym ] || {
    echo "ERROR: Screen-7 kernel symbols are missing; run 'make geobench-msx' first" >&2
    exit 1
}
cmp -s build/msx/FILEMGR.RAW QA/MSX/CARD/GBENCH/FILEMGR.APP
cmp -s build/msx/NOTEPAD.RAW QA/MSX/CARD/GBENCH/NOTEPAD.APP

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
export GEMBENCH_SHELL_MAIN="$main_abs"
export GEMBENCH_SHELL_LEN="$(hexsum "$data_base" "0x$(sym_offset _len)")"
export GEMBENCH_SHELL_BUF="$(hexsum "$data_base" "0x$(sym_offset _buf)")"
export GEMBENCH_SHELL_PROC="$(hexsum "$code_base" "0x$(sym_offset _n_proc)")"
export GEMBENCH_SHELL_DELIVER="$(awk '$1 == "KSH_DELIVER" { sub(/^#/, "0x", $2); print $2; found=1; exit }
    END { if (!found) exit 1 }' build/msx/gbkernm7.sym)"

main_file_offset=$((main_abs - 0x4000))
read -r sig0 sig1 sig2 < <(od -An -t u1 -j "$main_file_offset" -N 3 build/msx/NOTEPAD.RAW)
export GEMBENCH_SHELL_SIG0="$sig0"
export GEMBENCH_SHELL_SIG1="$sig1"
export GEMBENCH_SHELL_SIG2="$sig2"

mkdir -p build/msx
stage=$(mktemp -d -p build/msx shell-service-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

mkdir "$stage/card"
cp -a QA/MSX/CARD/. "$stage/card/"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
printf 'FIRST14' > "$stage/card/A.TXT"
printf 'SECOND14' > "$stage/card/B.TXT"
tools/build_msx_img.sh "$stage/card" "$stage/shell-service.img"

export GEMBENCH_SHELL_OUTPUT="$PWD/build/msx/shell-service-openmsx.txt"
export MSX_UNAPI=0
export MSX_MOUSE=0
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/shell_service_openmsx.tcl
tools/run_msx.sh "$stage/shell-service.img"

sed -n '1,30p' "$GEMBENCH_SHELL_OUTPUT"
grep -qx 'STATUS=PASS' "$GEMBENCH_SHELL_OUTPUT"
