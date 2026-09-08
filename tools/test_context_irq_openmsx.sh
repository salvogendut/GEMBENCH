#!/usr/bin/env bash
# Prove real timer preemption, not merely cooperative Clock yields. All altered
# applications and the Nextor hard disk are private diagnostic copies.
set -euo pipefail
cd "$(dirname "$0")/.."
stage=$(mktemp -d -p build/msx context-irq-stage.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/assembly/build/msx" "$stage/card"
repo=$PWD
(
    cd "$stage/assembly"
    "${RASM:-rasm}" "$repo/kernel/scheduler_image.asm" -DGEMBENCH_BASELINE=0 \
        -DPREEMPTIVE_TIMER=1 -DPREEMPTIVE_SWITCH=1 -s -sq -o scheduler
)
scheduler="$stage/assembly/build/msx/GBSCHED.RAW"
if [ -n "${CONTEXT_SCHEDULER_REFERENCE:-}" ]; then
    # A captured pre-extraction image may be tested with these symbols only
    # when every byte matches. Never silently test symbols from another build.
    cmp "$CONTEXT_SCHEDULER_REFERENCE" "$scheduler"
    cp "$CONTEXT_SCHEDULER_REFERENCE" "$scheduler"
fi
cp -a apps/desktop "$stage/context_irq_desktop"
GLOBAL_APPDEFS='-DGB_PREEMPTIVE -DGB_PREEMPTIVE_DIAGNOSTIC' \
    TASK_ROOT=1 TASK_RUNTIME_RAW="$scheduler" TASK_STACK_RESERVE=256 BASELINE=0 \
    DATA_LOC=0x7D90 DOC=1 TITLEBAR=1 GB_DEFER=1 GB_SERVICE_COLLECTOR=1 \
    GB_TIMER_COLLECTOR=1 APPDEFS='-DGB_MSX2 -DGB_DESK_ACCESSORIES' \
    bash tools/build_capp.sh "$stage/context_irq_desktop" "$stage/DESKTOP.RAW"
GLOBAL_APPDEFS=-DGB_PREEMPTIVE TASK=1 TASK_STACK_RESERVE=256 \
    APPDEFS=-DGB_MSX2 DATA_LOC=0x6200 \
    bash tools/build_capp.sh apps/taskdemo "$stage/TASKDEMO.RAW"
cp -a QA/MSX/CARD/. "$stage/card/"
sed -i "s/^MSXMODE=.*/MSXMODE=${MSX_TEST_MODE:-7}/" "$stage/card/GEOBENCH.CFG"
rm -f -- "$stage/card/UNAPINET.COM" "$stage/card/UNAPI.TXT"
printf 'GBMSX\r\n' > "$stage/card/AUTOEXEC.BAT"
cp "$stage/DESKTOP.RAW" "$stage/card/GBENCH/DESKTOP.APP"
cp "$stage/TASKDEMO.RAW" "$stage/card/GBENCH/TASKDEMO.APP"
bash tools/build_msx_img.sh "$stage/card" "$stage/context-irq.img"
export GEOBENCH_CONTEXT_SYMBOLS="$PWD/$stage/assembly/scheduler.sym"
export GEOBENCH_CONTEXT_OUTPUT="$PWD/build/msx/context-irq-${MSX_TEST_MODE:-7}.txt"
MSX_RAM=512k MSX_HEADLESS=1 MSX_UNAPI=0 MSX_MOUSE=0 SDL_AUDIODRIVER=dummy \
    MSX_SCRIPT=debug/context_irq_openmsx.tcl bash tools/run_msx.sh "$stage/context-irq.img"
sed -n '1,30p' "$GEOBENCH_CONTEXT_OUTPUT"
grep -qx 'STATUS=PASS' "$GEOBENCH_CONTEXT_OUTPUT"
