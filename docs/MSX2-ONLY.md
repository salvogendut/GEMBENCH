# Current MSX2-only implementation state

As of 31 August 2026, the active GEOBENCH tree builds and releases MSX2 only.

The active tree builds and releases for an MSX2 with a V9938/V9958, 128 KiB of
VRAM, at least 512 KiB of mapper RAM, and MSX-DOS 2 or Nextor. The top-level
`make`, application helpers, scheduler builder, GB-BASIC component, committed
QA media, and release checks expose only this target.

CPC and PCW build scripts, target backends, staged media, diagnostics, and
target-specific documentation were removed in issue #50. The last working
multi-platform tree—including the newly vendored GB-BASIC source—is preserved
on the remote branch:

```text
archive/cpc-pcw-targets
```

That branch remains an archival source for the new ports. This is no longer a
permanent target policy. The first CPC ABI experiment under issue #54 is parked
on `feature/54-reintegrate-cpc` at `5647857`. Issue #63 starts the
[five-step CPC restart](CPC-RESTART-PLAN.md) from working MSX2 `5ed8a15`, beginning
with a behavioral reference and shared-core extraction. PCW follows under #62.
Until their gates pass, CPC/PCW targets must not be exposed as working release
builds.

The new direction is specified in
[UNIVERSAL-APPLICATION-ABI.md](UNIVERSAL-APPLICATION-ABI.md) and its
[migration plan](UNIVERSAL-APPLICATION-ABI-MIGRATION.md). The active MSX2 build
continues unchanged while that work is developed on feature branches.

Some source names and formats retain historical terms such as “CPC Mode 1.”
They describe the canonical four-pen byte packing inherited by MSX2 assets;
they do not indicate an active CPC target. Portable algorithms and file formats
remain where the MSX2 build consumes them.
