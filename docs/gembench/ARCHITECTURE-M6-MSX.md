# Architecture Milestone 6: MSX2 secondary-code call gate

Status: **implemented on the MSX2 target in issue
[#41](https://github.com/salvogendut/GEMBENCH/issues/41)**.

Milestone 6 implements improvement 7 from the SymbOS-inspired architecture
review. A GBAP v3 application may carry one optional fixed-origin secondary
code image, copy it into a generation-tagged page owned by the application,
and call bounded entry offsets without making the primary application
relocatable. CPC and PCW do not advertise or execute this contract yet.

## Package and loading contract

The M5 primary descriptor remains first. An M6 package may append one type-2
descriptor with these requirements:

- MSX2 is present in its platform mask;
- required and executable flags are set;
- compression is `none`, with equal nonzero stored and unpacked sizes;
- its fixed load address is `0x4000`;
- it follows the primary segment exactly and ends at the manifest image size;
- the complete package remains at or below the existing 16,128-byte loader
  ceiling; and
- its bytes begin `JP entry`, `GBS3`, version `1`.

The app-linked v3 startup validates both descriptors before C initialization.
`gb_secondary_open()` then allocates purpose `GB_PAGE_SECONDARY_CODE` (`7`),
resolves its private mapper segment only after owner/generation validation, and
copies the payload in bounded 512-byte chunks. A failed startup returns before
window publication, so the existing pending-owner transaction reclaims both
the primary and any secondary page.

`GB_CAP_SECONDARY_CODE` (`0x2000`) advertises the runtime. The platform-neutral
descriptor value is retained for later CPC/PCW implementations, but applications
must test the capability before depending on the MSX2 runtime API.

## Call convention

The application-linked API is declared in `include/gembench/gbsecondary.h`:

```c
gb_secondary_t code;

if (gb_secondary_open(&code) == GB_SECONDARY_OK) {
    volatile unsigned char *xfer = gb_secondary_transfer();
    /* marshal values into the fixed record */
    gb_secondary_call(&code, entry_offset);
}
```

No pointer into `0x4000-0x7FFF` may cross the call. Parameters and results use
the fixed 512-byte record at `0xC400`, or a future explicitly documented
register convention. Secondary code is assembled at `0x4000`, owns no writable
data there, and reaches the resident kernel only through stable jump-table
entries.

Calls are synchronous and root-task-only. Before mapping, the runtime rejects:

- null handles and entry offsets outside the loaded image (`BADARG`);
- preemptible worker context (`CONTEXT`);
- an already active serialized gate (`BUSY`);
- an invalid generation (`STALE`);
- a page owned by another application (`OWNER`);
- a page whose purpose is not secondary code (`BADARG`); and
- an application record already marked terminating (`TEARDOWN`).

The 31-byte call stub is installed at fixed page-3 RAM
`0xC8E0-0xC8FE`. It saves the primary mapper segment on the fixed stack, maps
the validated secondary, makes `BANK_CUR` follow that mapping so ordinary
kernel/module calls restore the secondary correctly, and pushes the fixed
return address `0xC8F5`. On return it restores the saved segment atomically,
reenables interrupts, and returns through the untouched primary call word. The
fixed slot and transfer record are serialized with filesystem/module work; no
additional resident jump-table bytes are consumed.

Owner teardown already scans every general allocation. Closing or quitting the
application therefore releases its purpose-7 page together with its primary
page and invalidates both handles without a separate close API.

## FormRef proof and budgets

MSX2 FormRef is the first real client. Its window-summary renderer—surface,
saved name, two setting summaries, and the Open form button—is a 227-byte
data-free secondary image. Dynamic values are marshalled through 18 bytes of
the transfer record. The existing GBR form engine remains in the primary page.

Measured release budgets on 2026-08-30 are:

| Component | Bytes | Limit / margin |
| --- | ---: | ---: |
| FormRef linked primary | 15,799 | 16,128 / 329 free |
| FormRef secondary code | 227 | one owned 16 KiB page |
| Complete serialized package | 16,026 | 16,128 / 102 free |
| Screen 6 `GBMSX6.COM` | 14,547 | 16,128 / 1,581 free |
| Screen 7 `GBMSX7.COM` | 16,125 | 16,128 / 3 free |

The preceding M5 FormRef package was 16,120 bytes. M6 leaves the executable
primary ending 321 bytes earlier at 15,799 while moving a real 227-byte
component out of that page. The serialized package still carries those bytes
temporarily so the unchanged whole-file loader can copy them after startup;
storage-side segmented loading remains future work.

## Validation

```sh
make gembench-m6-manifest
python3 tools/test_appicon.py
make geobench-msx
make gembench-m5-openmsx
make gembench-m6-openmsx
```

Host tests round-trip the two-descriptor package and reject malformed secondary
flags, layout, prefix, and bounds. The M5 test retains valid publication and
transactional rejection coverage with a two-page package.

The dedicated M6 openMSX driver launches the normal packaged FormRef through
Desktop/File Manager. While its primary bank is mapped, a fixed-RAM test
trampoline exercises invalid-entry, nested-busy, stale-generation,
foreign-owner, and terminating-record rejection. FormRef then performs its
ordinary draw through the real secondary. Breakpoints require the exact
primary stack word and bank before/after the gate, the secondary mapper segment
at entry, purpose-7 metadata, two-page accounting, and complete owner/page
reclamation through the real close gadget.

## Portability boundary

The package descriptor, opaque handle, entry-offset rule, fixed transfer
record, and error taxonomy are suitable for later CPC/PCW providers. The
current mapper resolver, `PUT_P1` trampoline, page-3 addresses, and Screen 7
proof are MSX2 implementation details. A future provider must preserve the
same no-cross-bank-pointer rule and observable save/map/call/restore behavior;
it need not reproduce the MSX memory map.
