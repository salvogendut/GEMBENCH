#!/usr/bin/env bash
# Deploy a freshly built GEOBENCH onto a COPY of the real IDE disk for testing.
#
# Reflink-copies the pristine ~/DIMITRI/IDE.img to build/GEOBENCH_IDE.img (never
# touches the original) and drops in the kernel, apps, modules and assets with
# mtools. Conventions (verified against a working image):
#   * GBKERN.BIN  - a real 128-byte AMSDOS header (UniDOS RUN"s it).
#   * launchable apps - HEADERLESS raw images, .APP extension (the kernel loads
#     them to #4000 itself; #70 renamed them from .BIN so the FM can tell a
#     GEOBENCH app from a native CPC binary).
#   * kernel C modules (GBCFG/GBFAT) - headerless raw, .BIN.
#   * assets - copied as-is.
#
# Run inside the build container:  distrobox enter my-distrobox -- bash tools/deploy_ide.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${IDE_SRC:-$HOME/DIMITRI/IDE.img}"
IMG="build/GEOBENCH_IDE.img"

[ -f "$SRC" ] || { echo "source image $SRC not found" >&2; exit 1; }
cp --reflink=auto "$SRC" "$IMG"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

tools/stage_dist.sh "$STAGE"   # stage the full distribution (shared)

for f in "$STAGE"/*; do
    mcopy -i "$IMG" -o "$f" ::/
done
echo "Deployed GEOBENCH -> $IMG"
