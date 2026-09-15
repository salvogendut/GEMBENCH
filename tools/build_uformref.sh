#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/universal/FORMREF.APP}"

python3 tools/gbrc.py apps/formref/formref.json \
    --output build/universal/FORMREF.GBR \
    --c-header apps/uformref/formref_gbr.h --symbol-prefix FORMREF
SECONDARY_DATA_LOC=0x4400 bash tools/build_usecondary.sh \
    apps/uformref/formcompute build/universal/FORMREF.BIN
UNIVERSAL_GBR_FORMS=1 UNIVERSAL_GBR_EMBEDDED=1 \
UNIVERSAL_COMPUTE=1 APP_SECONDARY=build/universal/FORMREF.BIN \
APP_ICON=apps/formref/icon.asm DATA_LOC="${DATA_LOC:-0x7DE0}" \
    bash tools/build_uapp.sh apps/uformref "$OUT"
