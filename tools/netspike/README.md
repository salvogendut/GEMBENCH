# netspike — Net4CPC (W5100S) round-trip test harness (#238 Phase 0)

A throwaway-but-kept harness that proved the GEOBENCH networking path end to end
before the current `GBNET.MOD` implementation. It builds a tiny CPC binary against
the **cpc-sdcc** C W5100 driver (`~/Dev/cpc-sdcc/src`: `w5100.c`/`net.c`/
`netinit.c`), connects to a local TCP server, and prints the reply — all headless
in the 1984 emulator.

## Result (proven)
The CPC connects to `127.0.0.1:2323`, sends `hi`, and receives the server's banner
+ echo:
```
NET SPIKE / init ok / open ok / CONNECTED! / HELLO FROM HOST / ECHO:hi / DONE
```

## Run
```bash
# needs iDSK on PATH (e.g. inside `distrobox enter my-distrobox`)
tools/netspike/run.sh
```
Then view `tools/netspike/spike.ppm`.

## Recipe / gotchas
- **`net4cpc=true` + `net4cpc_tap=false` go under the `[hardware]` config section**
  (NOT `[net]` — that silently no-ops → the binary prints "NO CHIP").
- Default **host-socket mode** (no `--tap`, no sudo) handles outbound TCP to any IP,
  including `127.0.0.1`. `--tap` is only needed for inbound/ping/DHCP.
- Same SDCC as GEOBENCH (`~/Dev/sdcc`, 4.5.x, `sdcccall(1)`) — the driver's `__naked`
  asm is compatible as-is.
- The server and emulator must run in the **same shell** (a backgrounded server dies
  when its launching shell exits).

## Status
The production path now lives in `GBNET.MOD` plus the `gb_net_*` app API. Keep this
directory as a historical spike and as a small independent Net4CPC transport test.
