# MSX2-only target policy

As of 31 August 2026, GEMBENCH targets MSX2 only.

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

That branch is the restoration point if either port is rebuilt. New GEMBENCH
code must not add CPC or PCW build targets to the active tree.

Some source names and formats retain historical terms such as “CPC Mode 1.”
They describe the canonical four-pen byte packing inherited by MSX2 assets;
they do not indicate an active CPC target. Portable algorithms and file formats
remain where the MSX2 build consumes them.
