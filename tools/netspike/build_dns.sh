#!/usr/bin/env bash
# Build the DNS spike against the GEOBENCH-ported resolver (kernel/kc/dns.c + udp.c,
# w5100.c, net.c, gbnet_init.c) + cpc-sdcc crt0/cpcbios. Outputs DNSSPK.BIN here.
set -euo pipefail
cd "$(dirname "$0")"
SDCC_BIN="${SDCC_BIN:-$HOME/Dev/sdcc/bin}"
CPCSDCC="${CPCSDCC:-$HOME/Dev/cpc-sdcc}"
SRC="$CPCSDCC/src"
KC="$(cd ../../kernel/kc && pwd)"
AS="$SDCC_BIN/sdasz80"; CC="$SDCC_BIN/sdcc"; MAKEBIN="$SDCC_BIN/makebin"
INC="-I $KC -I $SRC"        # kc/ wins for w5100/net/dns/udp/netinit; cpcbios from src
"$AS" -o crt0.rel "$SRC/crt0.s"
for f in "$KC/w5100" "$KC/net" "$KC/gbnet_init" "$KC/udp" "$KC/dns"; do
  "$CC" -mz80 --nostdlib --no-std-crt0 $INC -c -o "$(basename $f).rel" "$f.c"
done
"$CC" -mz80 --nostdlib --no-std-crt0 $INC -c -o dnsmain.rel dnsmain.c
"$CC" -mz80 --nostdlib --no-std-crt0 --code-loc 0x4000 --data-loc 0x7000 \
    -o dns.ihx crt0.rel w5100.rel net.rel gbnet_init.rel udp.rel dns.rel dnsmain.rel
"$MAKEBIN" -p -o 0x4000 dns.ihx /tmp/dnsspk_raw.bin
python3 "$SRC/amsdos_wrap.py" /tmp/dnsspk_raw.bin DNSSPK.BIN 4000
rm -f /tmp/dnsspk_raw.bin *.rel *.ihx *.lst *.sym *.map *.noi
echo "Built tools/netspike/DNSSPK.BIN"
