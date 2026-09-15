#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/universal/GBRDEMO.APP}"

UNIVERSAL_FS=1 UNIVERSAL_GBR_OBJECTS=1 \
APP_ICON=lib/icon_app.asm DATA_LOC="${DATA_LOC:-0x7900}" \
bash tools/build_uapp.sh apps/ugbrdemo "$OUT"
