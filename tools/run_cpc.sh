#!/usr/bin/env bash
# Run already-built M4 media. Never build, copy or alter the user's machine setup.
set -euo pipefail
cd "$(dirname "$0")/.."
emulator="${CPC_EMULATOR:-../1984/1984}"
media="$PWD/QA/CPC-Desktop"
if [ ! -s "$media/GEOBENCH.IMG" ] || [ ! -s "$media/1984.conf" ]; then
    echo 'CPC Desktop image missing. Run make cpc first.' >&2
    exit 1
fi
if [ ! -x "$emulator" ]; then
    echo '1984 not found; set CPC_EMULATOR to its executable.' >&2
    exit 1
fi
exec "$emulator" "--config=$media/1984.conf" --6128 --memory=512 --autostart=BOOT "$@"
