#!/usr/bin/env bash
# tools/build_msx_floppy.sh - build a bootable 720KB MSX-DOS 2 floppy image for the
# MSX2 target (#287). MSX floppies (720K) are far bigger than the CPC's (~180K), so
# the whole GEOBENCH distro fits on ONE disk. Unlike the CPC .DSK (self-booting
# GEOBENCH), this carries third-party MSX-DOS 2 files (MSXDOS2.SYS + COMMAND2.COM),
# so - like QA/GBMSX.IMG - the .DSK is a LOCAL artifact (git-ignored), not committed.
#
# Boot chain: the disk-interface ROM runs the MSX boot sector -> loads MSXDOS.SYS
# (= MSXDOS2.SYS) -> COMMAND2.COM -> AUTOEXEC.BAT ("GBMSX") -> the desktop. Needs an
# MSX with MSX-DOS 2 (a DOS2 disk interface; most bare MSX2s have DOS1 - see docs).
#
# Usage: tools/build_msx_floppy.sh [staging-dir] [out.dsk]
#   staging dir default: QA/MSX        (the same tree build_msx_img.sh packs)
#   output default:      QA/GBMSX.DSK  (local artifact, git-ignored)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-QA/MSX}"
DSK="${2:-QA/GBMSX.DSK}"
DEPS=QA/MSXDEPS

for t in mkfs.fat mcopy dd; do
    command -v "$t" >/dev/null || { echo "ERROR: missing tool '$t' (dosfstools/mtools)" >&2; exit 1; }
done
for f in msxboot.bin MSXDOS2.SYS COMMAND2.COM; do
    [ -s "$DEPS/$f" ] || { echo "ERROR: $DEPS/$f missing - run tools/fetch_msx_deps.sh" >&2; exit 1; }
done
[ -d "$SRC" ] || { echo "ERROR: staging dir '$SRC' missing - run tools/build_kernel_msx.sh" >&2; exit 1; }

rm -f "$DSK"
# 720K (1440 x 512) FAT12, standard MSX geometry: 2 sec/cluster, 1 reserved, 2 FATs,
# 112 root entries, 9 sec/track, 2 heads.
mkfs.fat -F12 -S512 -s2 -R1 -f2 -r112 -h0 -n GBMSX -C "$DSK" 720 >/dev/null
# Inject the MSX boot code (offset 0x1E..0x1FF) over mkfs's x86 stub, keeping mkfs's
# BPB (0x00-0x1D) so it stays consistent with the filesystem the MSX boot code reads.
dd if="$DEPS/msxboot.bin" of="$DSK" bs=1 skip=30 seek=30 count=482 conv=notrunc status=none

export MTOOLS_SKIP_CHECK=1
# The MSX-DOS 2 kernel (cartridge / disk-interface ROM) loads MSXDOS2.SYS +
# COMMAND2.COM; also drop the DOS1 names the plain boot sector would look for, so
# the disk boots on either a DOS2 or a DOS1 interface.
mcopy -i "$DSK" "$DEPS/MSXDOS2.SYS" ::MSXDOS2.SYS
mcopy -i "$DSK" "$DEPS/MSXDOS2.SYS" ::MSXDOS.SYS
mcopy -i "$DSK" "$DEPS/COMMAND2.COM" ::COMMAND2.COM
mcopy -i "$DSK" "$DEPS/COMMAND2.COM" ::COMMAND.COM
# The GEOBENCH distro (GBMSX.COM + AUTOEXEC.BAT -> "GBMSX" + GBENCH/ + pictures + CFG).
mcopy -s -i "$DSK" "$SRC"/* ::/

USED=$(( $(du -sk "$SRC" | cut -f1) ))
echo "Built $DSK (720K MSX-DOS 2 boot floppy) from $SRC  (~${USED}K of ~713K used)"
