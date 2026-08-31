# Milestone 7 banking decision

Status: **complete 2026-08-29**. The shipping placement remains an embedded
GBR with an app-linked renderer. The mapper-backed path remains available as an
MSX2-only experiment; it is not enabled by the normal distribution build.

## Question

Milestone 7 tested whether FormRef's immutable GBR data and shared rendering
code should move out of its application segment. Three placements were built
from the same GBR v1 source and object runtime:

1. the existing embedded resource and app-linked renderer;
2. an auxiliary mapper segment with the app-linked renderer; and
3. a renderer-only resident split with its complete target dependencies.

The binary GBR v1 format did not change. CPC and PCW do not expose the mapper
service and their 7,054-byte FormRef binaries are unchanged.

## Static measurements

The application loader accepts 16,128 bytes at `0x4000..0x7EFF`; the resident
MSX kernel must remain below `0xC000`.

| Placement | Screen 7 kernel | FormRef app | App headroom | Resource | Extra mapper segment |
| --- | ---: | ---: | ---: | ---: | ---: |
| Embedded, app-linked (selected) | 12,260 | 13,023 | 3,105 | 306 bytes in app | 0 |
| Mapper resource, app-linked | 12,516 | 15,912 | 216 | 306-byte file | 1 while app is open |
| Mapper resource, resident candidate | 12,516 + 6,242 | not installed | not applicable | 306-byte file | 1 while app is open |

The mapper transport itself costs 256 resident bytes. Moving this small
resource to disk then requires the strict external reader, growing FormRef by
2,889 bytes despite removing the 306-byte embedded blob. It leaves only 216
bytes below the loader guard.

The resident renderer candidate is not a partial object-file estimate. The
probe links the renderer-only `gbr_object` split, banked accessor, button and
field drawing, libgb trampolines, and compiler support into one target image.
It is 6,242 code bytes plus two fixed-RAM bytes. The banked kernel has 3,868
resident bytes free, so the candidate exceeds the hard `0xC000` limit by 2,374
bytes. It cannot be installed without first changing the kernel placement
model.

## Runtime comparison

Both runnable placements passed the same map-derived openMSX driver. It opens
the real FormRef application through File Manager, renders the resource tree,
changes Style to Compact, changes Level to 2, saves, and observes the modal
restore. The split renderer also passes the complete host object/form behavior
suite, including unsupported-type preflight.

| openMSX observation | Embedded | Mapper resource |
| --- | ---: | ---: |
| Tree count / committed Style / Level | 1 / 1 / 2 | 1 / 1 / 2 |
| Lowest observed SP delta from `main` | 184 bytes | 202 bytes |
| First modal GBR draw | 887.758 ms | 668.618 ms |
| Return key to completed GBR redraw | 1,135.416 ms | 915.880 ms |
| Resource mapper segment / bytes | none | segment 8 / 306 |

These timings are one deterministic interaction run per placement and measure
the FormRef path, not the desktop baseline repaint probes. The banked run's
lower elapsed draw time does not overcome its fit result: it consumes one
mapper page, 256 resident bytes, and nearly all application headroom. No
persistent VRAM cache is introduced by either placement.

The complementary 1983 runs both reached frame 6,001 with PC `0x247A`, SP
`0xD8EA`, VDP registers `R0=0x0A` and `R1=0x62`, 25 free mapper segments at
GEMBENCH entry, and the Screen 7 baseline matched. openMSX remains authoritative
for the interactive FormRef result and timing.

## Decision

Keep GBR v1 resources embedded when they are small and keep the object/form
renderer app-linked for the first ABI review. This preserves 3,105 bytes of
FormRef headroom, costs no resident bytes or extra mapper page, and keeps the
normal Screen 7 kernel at the Milestone 6 size.

The MSX2 mapper transport is retained behind `GEMBENCH_M7_BANKED=1` because it
is safe, bounded, restores the application mapping before returning, and may be
useful for substantially larger future resources. It is an experimental
transport, not a commitment to bank every GBR. A shared paged renderer can be
reconsidered after the ABI review; the measured resident C renderer does not
fit the current nucleus.

Milestone 9 expanded the release FormRef tree and added an optional form-policy
unit. The rejected mapper experiment was already within 216 bytes of its loader
ceiling, so its reproduction target remains pinned to the original 306-byte
`formref-m7.json` fixture and excludes the later checkbox/radio renderer. This
keeps the measurements above reproducible without constraining the selected
embedded path or pretending that the mapper placement regained headroom.

## Reproduce

```sh
# Selected distribution and interaction path
MSX_UNAPI_TSR= make geobench-msx
tools/test_formref_openmsx.sh

# Auxiliary-segment comparison
MSX_UNAPI_TSR= make geobench-msx-banked
tools/test_formref_openmsx.sh

# Resident candidate map and fit result
make gembench-m7-resident-probe
cat build/m7/resident/measurement.txt

# Complementary boot/integration telemetry (use an absolute output path)
python3 debug/gembench_baseline_1983.py \
  --ide-image QA/MSX/GBMSX.IMG \
  --output-dir "$PWD/build/m7/1983" \
  --frames 6000
```
