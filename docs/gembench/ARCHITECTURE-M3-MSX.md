# Architecture Milestone 3: MSX2 deferred application messages

Status: **implemented on the MSX2 target in issue
[#35](https://github.com/salvogendut/GEMBENCH/issues/35)**.

Milestone 3 implements improvement 4 from the SymbOS-inspired architecture
review. It adds a deliberately small asynchronous control-message layer on top
of the generation-tagged application records from Milestones 1 and 2. CPC and
PCW do not export or advertise this API yet.

## Contract

`GB_DEFER` is appended at `0x80CF`. An application registers one application-
level handler and sends to a `gb_owner_t` endpoint. Sending validates the
sender, receiver generation, lifecycle state, and handler, copies four inline
bytes into resident RAM, and returns. It never maps or calls the recipient.
The caller's six-byte send record may be mapped application data or a normal
fixed-stack C local; its complete range is checked against the application page
or GEMBENCH's fixed-RAM copy of the boot-time DOS TPA ceiling before it is
copied. The kernel does not depend on page 0 remaining mapped while validating.

The WM root loop removes and delivers at most one FIFO entry per turn. It maps
the recipient's primary code page, publishes `GB_MSG_DEFER`, calls the
registered handler, restores the exact caller page, and only then performs an
optional activation/repaint requested by the handler. A recipient can enqueue
a reply because the current record is separate from the already-removed FIFO
entry. Delivery never recurses.

The public records are:

```c
typedef struct {
    gb_owner_t receiver;
    unsigned char type, p0, p1, p2;
} gb_defer_send_t;

typedef struct {
    gb_owner_t sender, receiver;
    unsigned char type, p0, p1, p2;
} gb_defer_message_t;
```

Applications opt in with `GB_DEFER=1` and include `gbdefer.h`:

```c
unsigned char gb_defer_register(void (*handler)(void));
unsigned char gb_defer_send(const gb_defer_send_t *message);
const gb_defer_message_t *gb_defer_current(void);
unsigned char gb_defer_slots_free(void);
unsigned char gb_defer_cancel_all(void);
gb_owner_t gb_defer_find_service(unsigned char service_class);
gb_owner_t gb_defer_find_accessory(unsigned char accessory_id);
void gb_defer_activate(void);
```

`gb_defer_current()` is non-null only in the registered receiver's active
handler. `gb_defer_activate()` is also handler-only: it records a request to
raise the recipient's primary window after the handler returns, avoiding a
nested repaint callback.

## Bounded behavior

The queue contains exactly eight records of eight bytes. It has no allocation,
bulk payload, priority, or implicit retry. Application control messages are not
coalesced; repaint and pointer movement remain outside this queue and retain
their existing compositor coalescing.

Enqueue results are explicit:

- `GB_DEFER_OK`: accepted for later delivery;
- `GB_DEFER_ERR_STALE`: the receiver generation is no longer active;
- `GB_DEFER_ERR_NO_HANDLER`: the live application has no endpoint;
- `GB_DEFER_ERR_FULL`: all eight records are occupied;
- `GB_DEFER_ERR_BADARG`: invalid pointer, zero type, or operation; and
- `GB_DEFER_ERR_CONTEXT`: no current application or a handler-only call made
  outside delivery.

`gb_defer_cancel_all()` removes every queued message sent by the caller and
returns the number removed. Unregistering or terminating an application
compacts away all entries in which it is sender or receiver. An entry that
becomes invalid at the final delivery boundary is removed and dropped without
calling recycled code. Generation validation therefore exists both at enqueue
and delivery.

Preemptible compute-worker contexts cannot register, enqueue, or cancel. These
operations remain root-task application work until shared kernel services are
made re-entrant.

## Capability record v3

The complete 20-byte v1 and 24-byte v2 prefixes are unchanged. Milestone 3
introduced a 28-byte `GB_SYSINFO` v3 record advertising
`GB_CAP_DEFERRED_MSG` (`0x0800`). Milestone 4 now returns v4 with this complete
v3 prefix unchanged. Its v3 suffix is:

| Offset | Bytes | v3 field |
| ---: | ---: | --- |
| 24 | 1 | queue capacity (`8`) |
| 25 | 1 | inline payload bytes (`4`) |
| 26 | 1 | deferred-message API version (`1`) |
| 27 | 1 | reserved, zero |

Consumers must check size, version, and the capability bit before using the
new jump.

## Resident storage

The later v4 suffix moves the private Milestone-2 application block to
`0xC310-0xC365`. The deferred layer now occupies `0xC366-0xC3C9`: sixteen handler
bytes, count/guard state, the stable current record, 64 FIFO bytes, and bounded
compaction scratch. All addresses are private implementation details below the
existing page-3 glue ceiling at `0xC900`; no mapper page or frozen window field
is consumed.

The preemptive Screen 6 and Screen 7 kernels are 14,156 and 15,734 bytes. Their
loader images are 14,492 and 16,070 bytes. The build now enforces the 16,128-byte
`0x0100..0x3FFF` DOS child-COM window; Screen 7 retains 58 bytes of loader
headroom. Deferred code is emitted after the screen driver's aligned lookup
tables so its size is not lost to padding. The fixed scheduler remains 503/512
bytes.

## Production migration

Desk accessory activation is the first production deferred shell interaction.
Desktop resolves Clock or Calculator to an application endpoint and queues a
`GB_DEFER_SHELL` / `GB_SHELL_ACTIVATE` message. A live target requests activation
from its handler; the root raises and repaints it after return. Absence still
launches the normal `.APP`, and a full/error result never launches a duplicate.

Clock and Calculator keep their synchronous shell registrations for older
clients. Desktop no longer links the synchronous accessory client and is 42
bytes smaller than its Milestone-2 build despite adding deferred activation.
The existing synchronous text-editor open path remains until a later bulk-page
or filesystem-handle contract can carry its 11-byte document name safely.

## Validation

```sh
make gbdefer-check
make geobench-msx
make gembench-m3-openmsx
make gembench-m3-boot-openmsx  # faster loader smoke only: Screen 6 and Screen 7
MSX_HEADLESS=1 tools/test_desk_accessories_openmsx.sh
```

The architecture diagnostic proves registration, no callback during enqueue,
exact capacity/full behavior, explicit cancellation, FIFO order, current-record
identity, and later root delivery. It deliberately keeps eight self-messages
pending; closing the app proves queue purge and handler teardown before the same
application slot/generation is reused.

The Desk lifecycle probe records deferred registrations, exact endpoint finds,
two queued activations, no duplicate applications, clean close/relaunch, and an
empty/non-busy queue at completion.

The mode smoke boots separate network-free images through `GBMSX6.COM` and
`GBMSX7.COM`, then checks a live Desktop, the current sysinfo record, mapper capacity, and an
empty deferred queue. This catches child-loader truncation independently of the
queue contract diagnostic.

## Deferred work

Bulk payload page handles, delivery acknowledgements, priority, coalescing of
application-defined traffic, cross-page filesystem requests, and the shared
service manager remain later milestones. The synchronous shell API stays
available and unchanged. CPC and PCW must implement equivalent lifecycle,
bank-mapping, and emulator tests before advertising `GB_CAP_DEFERRED_MSG`.
