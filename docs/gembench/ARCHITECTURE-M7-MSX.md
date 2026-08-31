# Architecture Milestone 7: MSX2 shared-service manager

Status: **implemented on the MSX2 target in issue
[#43](https://github.com/salvogendut/GEMBENCH/issues/43)**.

Milestone 7 implements improvement 8 from the SymbOS-inspired architecture
review: bounded application-owned services with discovery, first-client start,
deferred requests, reference-counted release, stale-owner reconciliation, and
final unload. CPC and PCW do not advertise this contract yet.

## Contract and scope

The platform-neutral API is `include/gembench/gbservice.h`. A client acquires a
functional 16-bit service ID and supplies an 11-byte fallback provider name:

```c
gb_service_t service;

if (gb_service_acquire(GB_SERVICE_NETWORK, GB_SERVICE_NETWORK_APP,
                       &service) == GB_SERVICE_OK) {
    gb_service_request(service, GB_SERVICE_NET_PROBE, 0);
    /* consume the later GB_SERVICE_MSG_RESPONSE in a deferred handler */
    gb_service_release(service);
}
```

Handles are generation-tagged and valid only for the acquiring application.
The first runtime has two provider records and three simultaneous client
leases. Duplicate acquisition by one client, a fourth lease, a foreign handle,
a stale generation, a missing provider, a full deferred FIFO, and worker-task
entry all return distinct status values.

`GB_SYSINFO` v5 retains the complete 32-byte v4 layout and its zero reserved
bytes. It adds only `GB_CAP_SERVICE_MANAGER` (`0x4000`). The capability denotes
service API v1; fixed capacities remain public header constants rather than
silently changing old reserved fields.

## Lifecycle

The manager is deliberately application-linked because the Screen 7 child COM
has only three resident bytes free. A small fixed page-3 table is shared by the
client, provider, and Desktop collector:

| Range | Contents |
| --- | --- |
| `0xC884-0xC891` | two 7-byte provider records: ID, owner, state, refs, generation |
| `0xC892-0xC89D` | three 4-byte leases: client owner, provider slot, generation |
| `0xC89E` | root-context serialization byte |
| `0xC89F` | last status diagnostic |

This consumes the unused tail of the Milestone-4 diagnostic reservation. It
does not move the active filesystem FIB at `0xC8A0`, the secondary-code gate at
`0xC8E0`, or the scheduler at `0xC900`.

The first acquire performs provider discovery and, if absent, opens its guarded
application. Registration must complete before `gb_wm_open()` returns. Only
then does the client lease become visible and its acquire notification enter
the existing deferred FIFO. A failed load or registration leaves no lease or
provider record; the ordinary pending-owner transaction reclaims the failed
application page.

Requests and lifecycle notifications use reserved deferred type 2. Sending
never calls or maps the provider synchronously. Providers are windowless
published applications with an ordinary deferred handler. A provider accepts a
request only when the sender owns a current lease. Replies are equally
deferred.

Explicit release clears the lease and decrements the reference count. Desktop
calls `gb_service_collect()` from its always-live bar turn, including while
another application owns the screen. The bounded collector scans three leases,
removes stale client owners, recomputes both reference counts, and queues at
most one final stop per turn. A provider unloads only after zero references;
provider death also clears its associated leases. No nested callback or
unbounded cleanup loop is introduced.

## First provider and production client

`NETSVC.APP` is a guarded GBAP v3, windowless MSX2 provider for functional
service ID 1. Its first request is a real TCP/IP UNAPI availability probe.
Telnet now acquires the provider, sends that probe asynchronously, waits for
the response in its deferred handler, and releases the lease when the session
closes or setup fails.

This is intentionally a shared **control plane**. Telnet's connected socket and
bulk receive/send buffers remain client-local; the four-byte deferred payload
is not misrepresented as a multi-session data transport. Browser migration and
a page-backed/bounded bulk-session contract remain future work.

The service-aware Telnet image is 13,823 bytes. Its MSX-only unused fullscreen
grid was removed and UNAPI pulls are bounded to 128 bytes so code, terminal
state, and client library still fit the lower 16 KiB application window.
`NETSVC.APP` is 4,781 bytes and Desktop is 15,688 bytes. Screen 6/7 child COMs
remain 14,547/16,125 bytes; the Screen 7 margin is still three bytes.

## Build integration

`tools/build_capp.sh` exposes three MSX2-only profiles:

- `GB_SERVICE_CLIENT=1` links discovery/acquire/request/release;
- `GB_SERVICE_PROVIDER=1` links provider registration and reply helpers; and
- `GB_SERVICE_COLLECTOR=1` links the root reconciliation policy.

Each profile also enables the existing sysinfo and deferred-message bindings.
The provider profile should use a v3 manifest declaring `service-manager`, a
stable `service_id`, and windowless/service lifecycle flags.

## Validation

```sh
python3 -m unittest tests.test_service_manager -v
make geobench-msx
make gembench-m7-service-openmsx
```

The host model checks the fixed layout, capacity, duplicate/full policy,
foreign and stale generations, stale-owner collection, provider generations,
and the network provider manifest.

The openMSX test boots a disposable network-free 512 KiB image through the
normal Desktop/File Manager path. Four real client applications and the actual
windowless provider prove:

- failed first-provider start returns `START` and restores pages/owners;
- A/B/C acquire references 1/2/3 and D gets deterministic `FULL`;
- a duplicate A acquire and B's use of A's handle are rejected;
- three deferred UNAPI probes reach the provider and return `PROVIDER` without
  the optional openMSXnet extension;
- B quits without release and Desktop reduces references from 3 to 2;
- B's old handle becomes stale;
- C and A explicitly release, producing references 1 then 0; and
- the final stop unloads `NETSVC.APP`, leaving zero leases/providers and the
  original owner count.

The reference run on 2026-08-30 ended with `STATUS=PASS`, reference sequence
`3,2,1,0`, two surviving windows/owners (Desktop and controller), an empty
service table, and an unlocked manager.

## Portability boundary

Service IDs, handle ownership, lifecycle states, error taxonomy, deferred
request/reply rules, provider manifests, and final-release behavior are the
portable contract. The fixed addresses, mapper-aware application loader, MSX
UNAPI probe, and Desktop bar hook are MSX2 implementation details. CPC and PCW
providers may use M4/Albireo and PerryNet, but must preserve deterministic
capacity, rollback, asynchronous delivery, and teardown behavior.
