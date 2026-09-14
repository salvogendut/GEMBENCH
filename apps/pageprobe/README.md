# Portable data-page diagnostic

Private receiver qualification for issue #84, not a replacement editor or
normal distribution application. The same PAGEPRB.APP bytes run on MSX and CPC.

```sh
UNIVERSAL_DATA_PAGES=1 UNIVERSAL_SCRAP=1 APP_ICON=apps/abiprobe/icon.asm \
  bash tools/build_uapp.sh apps/pageprobe build/universal/PAGEPRB.APP
```

Requires the opt-in receiver build and `portable-data-pages`/`typed-clipboard`
capabilities. See [contract and isolated test workflow](../../docs/PORTABLE-PAGES.md).
Run the test builders in a disposable, source-matched worktree: they prepare
private images but also update that worktree's build/diagnostic outputs.

The app roundtrips 16 KiB through bounded transfers, tests invalid spans,
overlaps, stale/free handles and pool exhaustion. It leaves one live owned page
for close cleanup and stores its old handle in the session clipboard for the
next launch. The drivers perform three launch/close cycles and compare exact
page-pool baselines. This intentionally replaces clipboard contents on the
private test machine. It does not write the disk.

`pageprobe_state`: status (85 PASS/255 FAIL), little-endian check count,
number of extra pages allocated, prior-lifetime token checked, little-endian
live page handle, reserved byte. Total checks depend on receiver free capacity.
Foreign-owner/code-purpose/worker and malformed-module tests are separate
instruction fixtures; do not infer those cases from this app alone.
