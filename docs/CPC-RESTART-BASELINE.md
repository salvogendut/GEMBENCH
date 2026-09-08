# CPC restart: step-1 validation record

Date: 2026-09-05. Issue: [#63](https://github.com/salvogendut/GEMBENCH/issues/63).
Reference: `5ed8a157656848cad1db1e21c68490ef06b015cb`.
See the [plan](CPC-RESTART-PLAN.md) and
[feature acceptance matrix](CPC-RESTART-MSX2-REFERENCE.md).

## Fresh verification

The full existing `make check` suite passed on an isolated, detached worktree
of the pinned MSX2 revision. No kernel, library, application, test or QA source
changes were needed to obtain this result.

Environment: `my-distrobox`, SDCC 4.6.2 #16671 (compiler and `sdasz80` from
`/var/home/salvogendut/Dev/sdcc/bin`), RASM 3.2.1 (2026-05-05 build), Python
3.14.6. The explicit compiler paths select the same compiler already on the
container's PATH.

| Check | Result and scope |
|---|---|
| Python test discovery | PASS: 57 tests, including resource compilation, ABI/build policy, identity, timer/service models and visibility geometry/source integration. |
| Native contracts and Z80 compilation | PASS: GBR reader/object/forms, VDI profiles, events, regions, typed scrap, shell, deferred messages and filesystem bindings. |
| Universal SDK and packages | PASS: deterministic ABI Probe, Clock and Calculator; GBAP v4 corruption and portability checks; v6/48-byte MSX gate audit with 1,201-byte validator. |
| Assets, ABI, layouts and committed media | PASS: low-RAM and jump-table checks, canonical pictures/catalogs, title/gadget/config and MSX floppy audits, package/icon tools. These audit committed distribution fixtures, not a freshly rebuilt full OS. |
| Existing app/kernel/libgb host suites | PASS: Calculator arithmetic and the kernel/libgb configuration, HTTP/HTML/forms/URL/window-kind tests included by `make check`. |
| Full distribution rebuild | NOT RUN in step 1. `make check` builds its fixtures and universal apps, but is not `make geobench-msx`. |
| openMSX / 1983 runtime workflows | NOT RUN in step 1. Historical scripts were inspected and mapped to acceptance IDs; no new emulator pass is claimed. |
| CPC integration / 1984 | NOT RUN; the restart branch intentionally starts with the MSX2-only source baseline. |

### Reproduction

Run from the repository. Explicit tool paths avoid a test script's default
`../sdcc/bin` dependency when the worktree is outside the usual development
directory:

```sh
restart_reference_dir=$(mktemp -d /tmp/geobench-cpc-reference.XXXXXX)
git worktree add --detach "$restart_reference_dir" 5ed8a157656848cad1db1e21c68490ef06b015cb
distrobox enter my-distrobox -- env \
  SDCC=/var/home/salvogendut/Dev/sdcc/bin/sdcc \
  SDAS=/var/home/salvogendut/Dev/sdcc/bin/sdasz80 \
  make -C "$restart_reference_dir" check
```

The actual validation worktree is
`/tmp/geobench-cpc-restart-baseline.iKQ6w8`. Its local, temporary log is
`make-check-explicit-tools.log` (exit 0), SHA-256
`6f07867448bee6ce2b9daf9370b490844e305a64636535b96cecce9488ecdff9`.
Temporary logs can disappear; the revision, command, toolchain and outcome
above are the durable record. The worktree's only untracked files after the run
were the two captured validation logs; tracked source/media were unchanged.

Fresh universal artifact SHA-256 values:

| Artifact | SHA-256 |
|---|---|
| `ABIPROBE.APP` | `7ff08894818e70b451f9bdd1708e6e4abea12be8e91e781e52b570b76d5c6200` |
| `CLOCK.APP` | `d542b0a0757b8695705295510c3a2a59d59761026324013ec778046c6d108314` |
| `CALC.APP` | `abcc0e5e1fedb84f4df59fc70bb6d49b768ca492a944544e5930bccbe4252f5c` |

These identify this baseline/toolchain, not permanently frozen future package
hashes. An approved experimental-ABI update requires rebuilding all copies
together and verifying identity within the new build.

### Initial attempts and environment findings

The first run in the ordinary workspace stopped at the MSX2-only assertion
because `QA/CPC` contained leftover generated media from the parked branch.
Those files were preserved. Switching Git branches does not remove all
generated/untracked artifacts, so baseline checks use the isolated worktree.

The first isolated run passed Python/GBR tests and native VDI contracts, then
stopped when `tests/run_gbvdi_tests.sh` looked for `../sdcc/bin/sdcc` relative to
`/tmp`. Supplying its supported `SDCC`/`SDAS` overrides fixed the environment;
the full rerun passed. Neither attempt established a runtime defect or justified
changing the target-policy tests. Record the relative toolchain assumption as
a reproducibility concern for later build-workflow cleanup.

## Runtime baseline required before step-2 changes

Prepare one clean MSX2 distribution with the documented emulator/Nextor inputs
and `make geobench-msx`, and keep matching symbols and image/package hashes.
Use openMSX as the reference and 1983 for complementary boot/interaction
confirmation. Disable optional UNAPI for non-network scenarios; absence is
also a required network-service error case.

Run the workflows for the subsystem being extracted before and after its
change. The existing entry points are:

| Work package | Existing entry points after the distribution build |
|---|---|
| Owner/page/application extraction first | `make gembench-m1-sysinfo`; `tools/test_m1_architecture_openmsx.sh`; `tools/test_m2_paint_openmsx.sh` |
| Loader and public ABI | `make geobench-v2-msx-openmsx`; `tools/test_m3_boot_modes_openmsx.sh` (private-shadow boot smoke only) |
| Focus/damage/timers | `tools/test_visible_regions_openmsx.sh`; `tools/test_window_kinds_openmsx.sh`; `tools/test_desk_accessories_openmsx.sh` |
| Resource/forms/settings | `tools/test_formref_openmsx.sh`; `tools/test_settings_vdi_openmsx.sh` |
| Shell, scrap and services | `tools/test_shell_service_openmsx.sh`; `tools/test_typed_scrap_openmsx.sh`; `make gembench-m7-service-probes` then `tools/test_m7_service_openmsx.sh` |
| Secondary code and BASIC | `tools/test_m6_secondary_openmsx.sh`; `tools/test_gb_basic_openmsx.sh` |

For scripted runs, select the installed openMSX using `OPENMSX`, set
`MSX_HEADLESS=1` and `MSX_UNAPI=0`, and retain each script's output and screenshot
paths. Some make targets rebuild their prerequisites; prefer the underlying
script when the required image and symbols were already built and unchanged.

Coverage work identified by inspection:

1. Apply the detailed native Clock occlusion/worker assertions to the shipped
   universal Clock. `tools/test_multi_event_openmsx.sh` deliberately stages
   `build/msx/CLOCK.RAW`; Desk tests use the universal package.
2. Observe public sysinfo v6 in addition to the old boot smoke's private v5
   shadow. Convert observation addresses to symbol/target adapters.
3. Add intermediate write/region assertions and repeated lifecycle scenarios
   where only final state or selected pixels are currently checked.
4. Capture a per-platform responsiveness and memory/stack budget; no fresh
   latency or full-kernel headroom measurement is claimed by this host run.

Step 1 has produced the reference, acceptance scenarios and fresh host baseline.
Runtime baselines and missing assertions remain explicit prerequisites for
their affected step-2 extractions; none is silently marked as passing.
