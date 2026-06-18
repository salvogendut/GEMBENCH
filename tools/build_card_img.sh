#!/usr/bin/env bash
# tools/build_card_img.sh - build a partitioned FAT16 card image from the staged QA/CARD
# distribution. Usable on BOTH storage backends: the SYMBiFACE IDE (which reads the MBR
# partition table) and the Albireo CH376 (which auto-detects the FAT partition). The IDE
# kernel and UniDOS/FATFS both read FAT16, so one image serves the boot AND the runtime.
#
# Output: QA/GEOBENCH.IMG (a 32 MB FAT16 partition at sector 32 / byte 16384 - the same
# layout as a real CPC CF/SD card). Rebuilt by tools/build_kernel.sh after the card is staged.
set -euo pipefail
cd "$(dirname "$0")/.."
CARD="${1:-QA/CARD}"
IMG="${2:-QA/GEOBENCH.IMG}"
SIZE_MB="${CARD_IMG_MB:-32}"
POFF=32                       # partition start, in 512-byte sectors (byte 16384)

[ -d "$CARD" ] || { echo "ERROR: $CARD not found - run tools/build_kernel.sh first" >&2; exit 1; }
for t in sfdisk mkfs.fat mcopy; do
    command -v "$t" >/dev/null || { echo "ERROR: missing tool '$t' (dosfstools/mtools/util-linux)" >&2; exit 1; }
done

rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count="$SIZE_MB" status=none
# MBR with one FAT16 partition (type 0x06) from sector POFF to the end of the image.
printf 'label: dos\nstart=%s, type=06\n' "$POFF" | sfdisk -q "$IMG" >/dev/null
# Format that partition as FAT16 (offset is in sectors).
mkfs.fat -F16 --offset "$POFF" -n GEOBENCH "$IMG" >/dev/null
# Copy the whole staged card into the partition root (-s = recurse into GEOBENCH/).
export MTOOLS_SKIP_CHECK=1
mcopy -s -i "$IMG@@$((POFF * 512))" "$CARD"/* ::/

echo "Built $IMG (${SIZE_MB}MB, FAT16 partition @ sector $POFF) from $CARD/"
