#!/usr/bin/env bash
# Run netspike in 1984 headless: start the local TCP server, boot SPIKE.BIN with
# Net4CPC enabled (default host-socket mode, no TAP), capture trace + screenshot.
set -euo pipefail
cd "$(dirname "$0")"
EMU="${EMU:-$HOME/Dev/1984/1984}"
ROMS="${ROMS:-$HOME/.config/1984/roms}"
[ -f SPIKE.BIN ] || ./build.sh
# DSK (needs iDSK; run from a shell that has it, e.g. distrobox)
rm -f spike.dsk; iDSK spike.dsk -n >/dev/null 2>&1
iDSK spike.dsk -i SPIKE.BIN -t 1 >/dev/null 2>&1
cat > net.conf <<CFG
[machine]
memory=128
[roms]
os=$ROMS/OS_6128.ROM
basic=$ROMS/BASIC_1.1.ROM
amsdos=$ROMS/AMSDOS.ROM
[hardware]
net4cpc=true
net4cpc_tap=false
CFG
python3 server.py 2>server.log & SRV=$!
sleep 1
SDL_VIDEODRIVER=offscreen timeout 90 "$EMU" --config=net.conf --disk-a=spike.dsk \
    --autostart=SPIKE --trace-net4cpc --screenshot-at=3000:spike.ppm --exit-after=3100 2>trace.log || true
kill $SRV 2>/dev/null || true
echo "--- server.log ---"; cat server.log
echo "--- trace (net4cpc) head ---"; head -15 trace.log
echo "screenshot: tools/netspike/spike.ppm"
