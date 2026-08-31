# Bootstrap validation results

> **Historical result:** this file records the initial imported target matrix
> and sibling-repository workflow. The current build is MSX2-only and both
> GB-PAINT and GB-BASIC are now in-tree. See
> [MSX2-ONLY.md](../MSX2-ONLY.md).

Status: **passed on 2026-08-28**.

These results validate merge commit `088436a`, whose parents are the GEMBENCH
bootstrap preparation (`c806040`) and GeoBench upstream (`6309ff3`). No
GEMBENCH runtime feature changes were included in the merge.

## Environment

| Component | Version or configuration |
| --- | --- |
| Python | 3.14.7 |
| RASM | 3.2.1, Atlas build 2026-05-05 |
| SDCC | 4.6.2, build 16671 |
| Emulator | 1983 git `50261d2` |
| Emulated machine | Omega MSX2, PAL, 512 KiB RAM, 128 KiB VRAM, V9958 |
| Firmware | RainBIOS Omega unified ROM with Sunrise IDE/Nextor |

The target build used the local GB-PAINT and GB-BASIC sibling repositories and
the already-fetched Nextor/openMSXnet files under the ignored `QA/MSXDEPS/`
path. Validation ran in an isolated worktree so generated QA media did not alter
the imported baseline files.

## Build

```sh
make gembench-msx \
    GB_PAINT_DIR=/var/home/salvogendut/Dev/GB-PAINT \
    GB_BASIC_DIR=/var/home/salvogendut/Dev/GB-BASIC
```

The build produced both kernels, the selector, applications, modules, staged
card directory, 32 MiB FAT16 image, and two 720 KiB floppy images.

| Artifact | Size |
| --- | ---: |
| Scheduler payload | 503 bytes of 512 reserved |
| Screen 6 kernel | 9,914 bytes |
| Screen 7 kernel | 11,492 bytes |
| Settings application | 14,692 bytes |
| FormRef application | 7,054 bytes |
| Browser application | 15,667 bytes |
| Paint application | 15,753 bytes |
| Example GBR | 111 bytes |

Reproducibility hashes for this merge commit:

```text
dd36eded8ce019bce42f0be1f46f036a6b6c0c23c54d7698a1d98c93375e86f1  GBKERN6.RAW
52a968660b3891b923fea4e5086eb692d7070b1c82e20223b2705ca8d962bd8e  GBKERN7.RAW
fba4a858a79d2294d51066cc0d958f2e5481930f07a511e5bfef42d32501e54e  GEOBENCH.DSK
```

## Checks

`make check` passed in the isolated target-build worktree and again in the main
integration worktree using the clean-checkout fixture prerequisite. It covered:

- seven GBR compiler, layout, checksum, and header-consistency tests;
- portable and Screen 7 picture/resource distribution audits;
- the MSX floppy distribution;
- CPC and MSX low-RAM maps;
- all 64 kernel ABI slots;
- application layout and icon formats;
- title-bar and icon editor tools; and
- calculator, kernel networking/configuration, HTTP, HTML, URL, widget, and
  reusable-form host suites.

The bootstrap adds a small title-module fixture prerequisite so the same
`make check` command can run from a clean checkout without first generating all
three target distributions.

## Boot smoke test

The generated system floppy was booted in 1983 with the Omega/RainBIOS profile.
The Nextor prompt launched `GBMSX`, the selector read the staged `MSXMODE=7`, and
the GEOBENCH desktop reached its normal 512 KiB Screen 7 state with Disk A,
Disk B, Clock, and Trash icons visible.

At frame 6001 the emulator reported VDP registers R0=`0A` and R1=`62`, 6,742
non-zero VRAM bytes, and a live guest PC at `247A`. The emulator process later
reported a host-side configuration/RTC persistence error because validation ran
under a read-only home configuration; this occurred after the successful guest
boot and did not affect the generated media.

## Baseline observations

- Screen 7 is the staged default in `QA/MSX/CARD/GEOBENCH.CFG`.
- Paint and Browser are already close to the 16 KiB application-bank ceiling.
- The initial object renderer must therefore remain optional and app-linked
  until its size is measured, especially for Settings and other large apps.
- Existing SDCC optimizer and overflow warnings were reproduced without new
  build errors.
