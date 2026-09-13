#!/usr/bin/env bash
# Link a read-only observer/keyboard driver against unmodified 1983 core sources.
set -euo pipefail
cd "$(dirname "$0")/.."
source_root="${MSX_1983_SOURCE:-../1983}"
output="${1:-build/msx-stability-1983/bridge}"
# Explicit opt-in for guest filesystem tests, using disposable copies only.
writable="${MSX_TEST_WRITABLE_IMAGE:-0}"
[[ "$writable" = 0 || "$writable" = 1 ]] || { echo 'MSX_TEST_WRITABLE_IMAGE must be 0 or 1' >&2; exit 2; }
sources=()
for unit in cartridge cassette ata floppy megaflash msx msx_scsi psg rtc scc \
            scsi_disk sdcard sd_mapper sunrise tc8566 vdp v9990 wd2793 z80; do
    sources+=("$source_root/src/$unit.c")
done
mkdir -p "$(dirname "$output")"
"${CC:-cc}" -O2 -std=c11 -Wall -Wextra -Wpedantic -I "$source_root/src" \
    -DMSX_TEST_WRITABLE_IMAGE="$writable" \
    tools/msx_stability_1983.c "${sources[@]}" -lm -o "$output"
git -C "$source_root" rev-parse HEAD
sha256sum "$output" "${sources[@]}"
