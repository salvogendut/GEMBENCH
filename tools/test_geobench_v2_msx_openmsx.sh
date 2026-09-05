#!/usr/bin/env bash
# Exercise GBAP v4 success and pre-entry transactional rejection on real MSX2.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d QA/MSX/CARD/GBENCH ] || {
    echo "ERROR: QA/MSX/CARD is missing; run 'make geobench-msx' first" >&2
    exit 1
}
for path in build/universal/ABIPROBE.APP build/msx/GBAPV4.RAW \
            build/universal-obj/abiprobe/app.noi; do
    [ -s "$path" ] || {
        echo "ERROR: Gate-2 artifact $path is missing; run 'make geobench-msx'" >&2
        exit 1
    }
done
python3 tools/test_geobench_v2_msx_gate.py \
    --staged QA/MSX/CARD/GBENCH/ABIPROBE.APP

kernel_symbols=build/msx/gbkernm7.sym
if [ "${MSX_TEST_MODE:-7}" = 6 ]; then kernel_symbols=build/msx/gbkernm.sym; fi
export GEMBENCH_M5_K_POLL="0x$(awk '$1 == "K_POLL" { value=$2; sub(/^#/, "", value); print value; exit }' "$kernel_symbols")"
export GEMBENCH_M5_MAIN="$(awk '$2 == "_main" { print $3; exit }' build/universal-obj/abiprobe/app.noi)"
export GEMBENCH_M5_ENTRY="$(awk '$2 == "_start" { print $3; exit }' build/universal-obj/abiprobe/app.noi)"
export GEMBENCH_M5_PAGES="$(python3 -c 'import pathlib,sys; sys.path.insert(0,"tools"); from embed_app_icon import parse_manifest; print(parse_manifest(pathlib.Path("build/universal/ABIPROBE.APP").read_bytes())["minimum_pages"])')"
export GEMBENCH_M5_BAD_PREENTRY=1
export MSX_UNAPI=0
export MSX_MOUSE=0
export MSX_HEADLESS=1
export SDL_AUDIODRIVER=dummy
export MSX_SCRIPT=debug/m5_gbap3_openmsx.tcl

stage=$(mktemp -d -p build/msx v2-gbap4-stage.XXXXXX)
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT

for mode in good bad legacy; do
    mkdir -p "$stage/$mode/card"
    cp -a QA/MSX/CARD/. "$stage/$mode/card/"
    rm -f -- "$stage/$mode/card/UNAPINET.COM" "$stage/$mode/card/UNAPI.TXT"
    sed -i 's/^SAVERTIME=.*/SAVERTIME=0/' "$stage/$mode/card/GEOBENCH.CFG"
    sed -i "s/^MSXMODE=.*/MSXMODE=${MSX_TEST_MODE:-7}/" "$stage/$mode/card/GEOBENCH.CFG"
    printf 'GBMSX\r\n' > "$stage/$mode/card/AUTOEXEC.BAT"
    cp build/universal/ABIPROBE.APP "$stage/$mode/card/GBENCH/FILEMGR.APP"
done

# An actual previously shipped ABI 2.0 executable, not new code with a lowered
# manifest. Its CRT insists on sysinfo minor==0, so this exercises the separate
# compatibility view. The same file is used unchanged in both video modes.
python3 - "$stage/legacy/card/GBENCH/FILEMGR.APP" <<'PY'
from pathlib import Path
import subprocess, sys
from tools.embed_app_icon import parse_manifest
data = subprocess.check_output(["git", "show", "a30a802:QA/MSX/CARD/GBENCH/ABIPROBE.APP"])
assert parse_manifest(data)["minimum_abi"] == (2, 0)
Path(sys.argv[1]).write_bytes(data)
PY

# Flip one code byte while leaving every header, bound, and entry intact. This
# drives the complete assembly validator through its CRC path; it must reject
# before _start and release the pending owner/page.
python3 -c 'from pathlib import Path; p=Path(__import__("sys").argv[1]); d=bytearray(p.read_bytes()); d[-1] ^= 1; p.write_bytes(d)' \
    "$stage/bad/card/GBENCH/FILEMGR.APP"

new_main=$GEMBENCH_M5_MAIN
for mode in good bad legacy; do
    tools/build_msx_img.sh "$stage/$mode/card" "$stage/$mode/v2-$mode.img"
    export GEMBENCH_M5_MODE="$mode"
    export GEMBENCH_M5_MAIN="$new_main"
    if [ "$mode" = legacy ]; then
        export GEMBENCH_M5_MODE=good
        # The frozen CRT is CALL guard; OR A; RET Z; CALL init; CALL main.
        export GEMBENCH_M5_MAIN="$(python3 -c 'import pathlib,struct,sys; d=pathlib.Path(sys.argv[1]).read_bytes(); e=struct.unpack_from("<H",d,1)[0]-0x4000; assert d[e+8]==0xCD; print(struct.unpack_from("<H",d,e+9)[0])' "$stage/legacy/card/GBENCH/FILEMGR.APP")"
    fi
    export GEMBENCH_M5_OUTPUT="$PWD/build/msx/v2-gbap4-${MSX_TEST_MODE:-7}-$mode.txt"
    tools/run_msx.sh "$stage/$mode/v2-$mode.img"
    sed -n '1,20p' "$GEMBENCH_M5_OUTPUT"
    grep -qx 'STATUS=PASS' "$GEMBENCH_M5_OUTPUT"
done
