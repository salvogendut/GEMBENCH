#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/universal/FORMREF.APP}"

python3 tools/gbrc.py apps/formref/formref.json \
    --output build/universal/FORMREF.GBR \
    --c-header apps/uformref/formref_gbr.h --symbol-prefix FORMREF
UNIVERSAL_GBR_FORMS=1 UNIVERSAL_GBR_EMBEDDED=1 \
APP_ICON=apps/formref/icon.asm DATA_LOC="${DATA_LOC:-0x7D20}" \
    bash tools/build_uapp.sh apps/uformref "$OUT"
