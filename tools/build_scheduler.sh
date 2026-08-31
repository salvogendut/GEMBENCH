#!/usr/bin/env bash
# Build the app-carried fixed-RAM scheduler payload for one target.
set -euo pipefail
cd "$(dirname "$0")/.."

RASM="${RASM:-rasm}"
target="${1:-cpc}"
PREEMPTIVE_TIMER="${PREEMPTIVE_TIMER:-1}"
PREEMPTIVE_SWITCH="${PREEMPTIVE_SWITCH:-1}"
GEMBENCH_BASELINE="${GEMBENCH_BASELINE:-0}"

if [ "$PREEMPTIVE_TIMER" != 0 ] && [ "$PREEMPTIVE_TIMER" != 1 ]; then
    echo "PREEMPTIVE_TIMER must be 0 or 1" >&2
    exit 2
fi
if [ "$PREEMPTIVE_SWITCH" != 0 ] && [ "$PREEMPTIVE_SWITCH" != 1 ]; then
    echo "PREEMPTIVE_SWITCH must be 0 or 1" >&2
    exit 2
fi
if [ "$GEMBENCH_BASELINE" != 0 ] && [ "$GEMBENCH_BASELINE" != 1 ]; then
    echo "GEMBENCH_BASELINE must be 0 or 1" >&2
    exit 2
fi

case "$target" in
    cpc)
        out="build/GBSCHED.RAW"
        defs=()
        ;;
    msx)
        out="build/msx/GBSCHED.RAW"
        defs=(-DPLATFORM_MSX=1)
        limit=1536
        ;;
    pcw)
        out="build/pcw/GBSCHED.RAW"
        defs=(-DPLATFORM_PCW=1)
        limit=512
        ;;
    *)
        echo "usage: $0 {cpc|msx|pcw}" >&2
        exit 2
        ;;
esac

: "${limit:=512}"

mkdir -p "$(dirname "$out")"
rm -f "$out"
"$RASM" kernel/scheduler_image.asm -s -o "/tmp/geobench-scheduler-$target" \
    -DPREEMPTIVE_TIMER="$PREEMPTIVE_TIMER" -DPREEMPTIVE_SWITCH="$PREEMPTIVE_SWITCH" \
    -DGEMBENCH_BASELINE="$GEMBENCH_BASELINE" \
    "${defs[@]}" >/dev/null

if [ ! -s "$out" ]; then
    echo "ERROR: scheduler build did not create $out" >&2
    exit 1
fi
size=$(stat -c%s "$out")
if (( size > limit )); then
    echo "ERROR: $target scheduler is $size bytes; fixed slot is $limit bytes" >&2
    exit 1
fi
echo "Built $out ($size/$limit bytes, app-carried fixed-RAM scheduler)"
