#!/usr/bin/env bash
# tools/build_msx_img.sh - build a bootable Nextor FAT16 hard-disk image for the
# MSX2 target (issue #287): a
# 32 MB image, MBR partition (type 0x06) at sector 32, FAT16, filled from a
# staging directory. Nextor's Sunrise IDE driver boots NEXTOR.SYS/COMMAND2.COM
# from the partition root, so the same image is both boot and payload media.
#
# Usage: tools/build_msx_img.sh [staging-dir] [out.img]
#   staging dir default: QA/MSX/CARD (falls back to a minimal QA/MSXDEPS boot set)
#   output default:      QA/MSX/GBMSX.IMG (local artifact, git-ignored)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-QA/MSX/CARD}"
IMG="${2:-QA/MSX/GBMSX.IMG}"
SIZE_MB="${MSX_IMG_MB:-32}"
POFF=32                       # partition start, in 512-byte sectors

for t in sfdisk mkfs.fat mcopy; do
    command -v "$t" >/dev/null || { echo "ERROR: missing tool '$t' (dosfstools/mtools/util-linux)" >&2; exit 1; }
done
[ -s QA/MSXDEPS/NEXTOR.SYS ] && [ -s QA/MSXDEPS/COMMAND2.COM ] || {
    echo "ERROR: QA/MSXDEPS incomplete - run tools/fetch_msx_deps.sh first" >&2; exit 1; }

rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count="$SIZE_MB" status=none
printf 'label: dos\nstart=%s, type=06\n' "$POFF" | sfdisk -q "$IMG" >/dev/null
mkfs.fat -F16 --offset "$POFF" -n GBMSX "$IMG" >/dev/null

export MTOOLS_SKIP_CHECK=1
mcopy -i "$IMG@@$((POFF * 512))" QA/MSXDEPS/NEXTOR.SYS QA/MSXDEPS/COMMAND2.COM ::/
if [ -d "$SRC" ]; then
    for path in "$SRC"/*; do
        [ "$(basename "$path")" = Floppies ] && continue
        mcopy -s -i "$IMG@@$((POFF * 512))" "$path" ::/
    done
fi

echo "Built $IMG (${SIZE_MB}MB, FAT16 @ sector $POFF) from ${SRC}$([ -d "$SRC" ] || echo ' [missing - boot files only]')"
