# Architecture Milestone 4: MSX2 filesystem contexts

Status: **implemented on the MSX2 target in issue
[#37](https://github.com/salvogendut/GEMBENCH/issues/37)**.

Milestone 4 implements improvement 5 from the SymbOS-inspired architecture
review. Native MSX-DOS2/Nextor calls remain serialized, but applications no
longer have to treat the process-wide drive, current directory, directory FIB,
file name, and stream offset as their own state. CPC and PCW do not export or
advertise this API yet.

## Public contract

`GB_FSCTX` is appended at `0x80D2`. Its C binding exposes four opaque,
generation-tagged contexts:

```c
gb_fsctx_t gb_fsctx_open(unsigned char drive);
unsigned char gb_fsctx_close(gb_fsctx_t context);
unsigned char gb_fsctx_set_path(gb_fsctx_t context, const char *path);
unsigned char gb_fsctx_set_name(gb_fsctx_t context, const char *name11);
unsigned char gb_fsctx_activate(gb_fsctx_t context);
unsigned char gb_fsctx_dir_first(gb_fsctx_t context, gb_fsctx_entry_t *entry);
unsigned char gb_fsctx_dir_next(gb_fsctx_t context, gb_fsctx_entry_t *entry);
unsigned char gb_fsctx_dir_batch(gb_fsctx_t context, unsigned char first);
unsigned char gb_fsctx_rewind(gb_fsctx_t context);
unsigned int gb_fsctx_read(gb_fsctx_t context, char *buffer,
                           unsigned int length);
unsigned char gb_fsctx_write(gb_fsctx_t context, const char *buffer,
                             unsigned int length);
unsigned char gb_fsctx_free_kib(gb_fsctx_t context, unsigned int *kib);
unsigned char gb_fsctx_cancel(gb_fsctx_t context);
```

Each live record retains its owner, drive, normalized absolute path, raw
space-padded 8.3 name, 32-bit sequential offset, and a private 64-byte
directory-enumeration snapshot. A handle is valid only for the application
generation that allocated it. Reuse advances the handle generation; stale and
foreign handles are rejected separately. Application teardown invalidates all
of its contexts even when it exits without closing them explicitly.

`gb_fsctx_dir_batch()` returns up to four packed 16-byte entries in the fixed
transfer buffer. This amortizes module loading and native enumeration while
retaining the same context-private FIB. The result remains valid only until the
next filesystem-context call.

The hardware backend is still atomic and single-threaded. Each read or write
advances at most 512 bytes and returns before another application operation is
dispatched. There is no persistent DOS file handle, background I/O task,
unbounded request queue, or pointer retained across page mappings. `cancel`
rewinds the pending sequential transfer state; applications schedule later
chunks from their normal root-task callbacks.

File-launch handoff is represented by `gb_fsctx_prepare_launch()` and
`gb_fsctx_adopt_launch()`. It copies drive/path/name through one fixed resident
record so a loader can give the new owner an equivalent context without sharing
the caller's handle. The first production consumer does not need this handoff
yet, but the contract is available for the next Notepad/Browser migration.

## Capability record v4

The complete v1, v2, and v3 prefixes are unchanged. `GB_SYSINFO` v4 is 32 bytes
and advertises `GB_CAP_FS_CONTEXTS` (`0x1000`). Its suffix is:

| Offset | Bytes | v4 field |
| ---: | ---: | --- |
| 28 | 1 | global context capacity (`4`) |
| 29 | 2 | maximum transfer advanced per call (`512`) |
| 31 | 1 | filesystem-context API version (`1`) |

Consumers must check the record size, version, and capability bit before using
the appended jump.

## Resident and paged placement

Only the small owner/context gate and teardown scan are resident. The branchy
filesystem implementation is built as `GBFSCTX.MOD` and loaded into the normal
`0x6000` data-module window on demand. Its current payload is 2,024 bytes.

The v4 sysinfo suffix moves the Milestone-2 application block to
`0xC310-0xC365` and the Milestone-3 deferred-message block to
`0xC366-0xC3C9`. Filesystem marshalling and state occupy fixed page-3 RAM:

- `0xC3D0-0xC3EF`: request/result record;
- `0xC400-0xC5FF`: one 512-byte bounded transfer buffer;
- `0xC600-0xC83F`: four 144-byte context records;
- `0xC840-0xC87F`: pending launch-context transfer;
- `0xC880-0xC89F`: reserved diagnostic space; and
- `0xC8A0-0xC8DF`: active native directory FIB.

The native FIB previously occupied 64 bytes in both mode-specific kernel
images. Relocating it to the fixed architecture area offsets the new resident
gate. The Screen 7 child COM remains within the enforced 16,128-byte DOS load
window at 16,125 bytes (three bytes of enforced headroom).

## File Manager migration

Every MSX2 File Manager instance allocates one context. Its incremental
directory scan fetches four entries per module call and uses the context-owned
FIB, so pausing one scan while another storage operation runs cannot silently
replace its enumeration position. Path changes update the explicit context,
and all inherited file/copy operations activate that context immediately
before using the legacy backend. If the four-slot global pool is exhausted, a
new File Manager reports the condition and terminates instead of opening a
window whose directory state cannot meet the M4 isolation contract.

The application links a generated exact `gblib` subset plus the directory-only
filesystem binding. This keeps `FILEMGR.APP` within its 16 KiB bank while CPC
and PCW retain their existing source path and binary contract. Notepad and
Browser remain on their existing bounded jobs and are the next candidate
clients; this milestone does not claim that they have already migrated.

## Validation

```sh
make gbfsctx-check
make geobench-msx
make gembench-m4-openmsx
```

The host contract test checks the public constants, structure layout, appended
jump, module build, and the guarded MSX-only build option. The architecture
diagnostic verifies the v4 suffix, global exhaustion, independent sequential
offsets, bounded write/read, stale-generation rejection, handle reuse, and
owner cleanup. It opens alongside File Manager, whose own live context reduces
the diagnostic's available global pool from four slots to three; a deliberately
leaked diagnostic context would reduce the second launch to two and fail the
test.

The openMSX lifecycle test launches the diagnostic twice through the real File
Manager, observes both owners' context counts, and requires File Manager's one
context to survive while each diagnostic context is reclaimed. The existing
two-mode boot, Paint lifecycle, and Desk-accessory checks guard the shifted
private page-3 tables.

## Target boundary and deferred work

`GB_FSCTX=1` currently rejects non-MSX builds. CPC and PCW must implement their
own serialized backends and equivalent M4/Albireo/floppy tests before
advertising `GB_CAP_FS_CONTEXTS`.

Arbitrary seek, rename/delete/query operations, asynchronous service workers,
larger page-backed transfers, and conversion of Notepad, Browser, and every
legacy File Manager copy path remain incremental work. The next architecture
milestone can build GBAP v3 packaging on this explicit storage ownership rather
than reintroducing global launch state.
