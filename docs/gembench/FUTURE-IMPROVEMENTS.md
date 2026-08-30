# Future architecture improvements

The original eight-item SymbOS-inspired MSX2 roadmap has reached its planned
first useful implementation. The following work remains available for later
milestones.

## Application ownership

- Generalize Milestone 8's one coalesced, generation-safe visual timer mailbox
  only when another production application requires multiple registrations or
  periodic control messages.
- Keep worker callbacks pure and retain deterministic teardown through their
  owning application/window records.
- Keep acquired and provided service state visible through the application
  lifecycle.

## Deferred messages

- Add optional page-backed bulk payload handles.
- Add delivery acknowledgements where callers require completion reporting.
- Migrate the remaining synchronous Notepad-open path once filenames can be
  carried safely through a bulk or filesystem-handle contract.
- Consider bounded priority or coalescing only where measurements justify it.

## Filesystem contexts

- Add arbitrary seek, rename, delete, and metadata/query operations.
- Add bounded asynchronous transfer workers and larger page-backed transfers.
- Migrate Notepad, Browser, and remaining legacy File Manager operations to
  explicit contexts.

## GBAP v3 packages

- Inspect manifests from storage before allocating and publishing an
  application.
- Add measured optional compression support.
- Activate resource and data segment descriptors.
- Validate and load every segment transactionally, rolling back the complete
  application on failure.

## Secondary code

- Load secondary segments directly from storage instead of temporarily
  carrying the complete serialized package through the primary application
  page.
- Move additional measured components only when doing so recovers useful
  primary-bank headroom.

## Shared services

- Extend `NETSVC` from its bounded control plane to shared socket sessions and
  page-backed or otherwise bounded bulk data transfer.
- Migrate Browser to the shared network service while retaining deterministic
  capacity, cancellation, failure rollback, and final-release cleanup.
- Consider later sound and printing providers after the network data-plane
  contract is proven.

The recommended next MSX2 milestone is a bounded network-session/data service
plus Browser adoption.

## CPC and PCW parity

Backport the portable contracts for all eight improvements to CPC and PCW,
assuming at least 512 KiB RAM while retaining their native graphics, storage,
banking, and network backends. This includes:

- capability queries and general owned-page allocation;
- application/window ownership and deferred messages;
- explicit filesystem contexts;
- GBAP v3 loading and the secondary-code call gate; and
- shared-service providers using CPC M4/Albireo networking and PCW PerryNet.

Each target must advertise a capability only after equivalent lifecycle,
failure, cleanup, packaging, and emulator tests pass on that target.
