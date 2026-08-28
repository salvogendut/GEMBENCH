#!/usr/bin/env bash
# Build the Milestone-7 resident-renderer candidate without installing it.
#
# The candidate is linked exactly as a resident C body would be: the renderer-
# only half of gbr_object, the banked accessor, shared button/field drawing, and
# the libgb kernel trampolines.  Its map is the placement decision's fit input;
# a candidate larger than the remaining #8000..#BFFF kernel window must not be
# hidden by dropping dependencies from the measurement.
set -euo pipefail
cd "$(dirname "$0")/.."

outdir="${1:-build/m7/resident}"
SDCC="${SDCC:-sdcc}"
bindir="$(dirname "$(command -v "$SDCC")")"
SDAS="$bindir/sdasz80"
mkdir -p "$outdir"

common=(-mz80 --opt-code-size --fomit-frame-pointer -DGB_MSX2)
"$SDCC" "${common[@]}" -DGBR_FORM_RUNTIME -DGBR_RENDERER_ONLY \
    -DGBR_BANKED -I include/gembench -I lib/gb \
    -c lib/gembench/gbr_object.c -o "$outdir/gbr_object.rel"
"$SDCC" "${common[@]}" -DGBR_BANKED -DGBR_READER_ACCESS_ONLY \
    -DGBR_READER_NO_FIND_TREE -I include/gembench \
    -c lib/gembench/gbr_reader.c -o "$outdir/gbr_reader.rel"
"$SDCC" "${common[@]}" -I include/gembench \
    -c lib/gembench/gbr_bank.c -o "$outdir/gbr_bank.rel"
"$SDCC" "${common[@]}" -I lib/gb \
    -c lib/gb/gbwidgets.c -o "$outdir/gbwidgets.rel"
"$SDAS" -o "$outdir/gbr_bank_call.rel" lib/gembench/gbr_bank.s
"$SDAS" -o "$outdir/gblib.rel" lib/gb/gblib.s

"$SDCC" -mz80 --no-std-crt0 --code-loc 0x0100 --data-loc 0xC1C0 \
    "$outdir/gbr_object.rel" "$outdir/gbr_reader.rel" \
    "$outdir/gbr_bank.rel" "$outdir/gbr_bank_call.rel" \
    "$outdir/gbwidgets.rel" "$outdir/gblib.rel" \
    -o "$outdir/resident.ihx"

code_hex="$(awk '$1 == "_CODE" { print $3; exit }' "$outdir/resident.map")"
bss_hex="$(awk '$1 == "_BSS" { print $3; exit }' "$outdir/resident.map")"
code_bytes=$((16#${code_hex:-0}))
bss_bytes=$((16#${bss_hex:-0}))
kernel_bytes=0
if [ -s build/msx/GBKERN7.RAW ]; then
    kernel_bytes="$(stat -c%s build/msx/GBKERN7.RAW)"
fi
available=$((16384 - kernel_bytes))
fits=unknown
if (( kernel_bytes > 0 )); then
    if (( code_bytes <= available )); then fits=yes; else fits=no; fi
fi

printf 'resident renderer candidate: %d code bytes, %d fixed-RAM bytes\n' \
    "$code_bytes" "$bss_bytes"
if (( kernel_bytes > 0 )); then
    printf 'current Screen 7 kernel: %d bytes; resident headroom: %d; fits: %s\n' \
        "$kernel_bytes" "$available" "$fits"
fi
printf 'CODE_BYTES=%d\nBSS_BYTES=%d\nKERNEL_BYTES=%d\nHEADROOM_BYTES=%d\nFITS=%s\n' \
    "$code_bytes" "$bss_bytes" "$kernel_bytes" "$available" "$fits" \
    > "$outdir/measurement.txt"
