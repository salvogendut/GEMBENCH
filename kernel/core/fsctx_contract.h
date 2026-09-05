/* Shared FSCTX contract (#74).
 * Execute only through the serialized root/module gate. REQ_OWNER is captured
 * from the mapped caller; this core validates handles, not the caller itself.
 * Request/transfer/context/pending/diagnostic/cursor storage stays fixed while
 * providers restore the exact module bank and stack after native calls.
 * 16-bit unsigned int and 8-bit unsigned char are required on the Z80 target.
 * Hooks run synchronously, keep no caller pointers and never invoke apps.
 * SELECT_CONTEXT must preserve XFER (including a pending write payload).
 * Directory hooks expose canonical 11-byte names, attr and 32-bit size, and an
 * opaque bounded cursor; NEXT resumes the restored cursor, not a global scan.
 * READ returns at most REQ_LENGTH; WRITE returns success/failure. Activation
 * and error precedence, partial path writes on rejection, zero read ambiguity,
 * append semantics and pending-launch one-shot behavior are unchanged.
 * CANCEL rewinds only; teardown invalidates owned records but does not purge
 * pending launch state. No persistent native handles survive calls. Providers
 * with persistent handles require an explicitly reviewed cleanup adaptation.
 * These checks prove local fixed spans/non-overlap, not the complete platform
 * map, native scratch reservations, call latency or maximum stack depth.
 */
#ifndef GEMBENCH_FSCTX_CONTRACT_H
#define GEMBENCH_FSCTX_CONTRACT_H
#if CTX_MAX != 4 || CTX_SIZE != 144 || CTX_ACTIVE != 0 || CTX_OWNER != 2
#error "Keep FSCTX public capacity and resident cleanup layout synchronized"
#endif
#if FSCTX_DRIVE_MAX < 1 || FSCTX_DRIVE_MAX > 255
#error "Invalid FSCTX drive capacity"
#endif
#if FSCTX_CURSOR_SIZE < CTX_PATH_CAP || CTX_CURSOR + FSCTX_CURSOR_SIZE > CTX_SIZE
#error "FSCTX cursor/path workspace exceeds its reservation"
#endif
#if P_PATH + CTX_PATH_CAP > 64 || CTX_PATH + CTX_PATH_CAP > CTX_CURSOR
#error "FSCTX path exceeds its reservation"
#endif
#define FSCTX_FIXED(a, n) (((a) >= 0 && (a) + (n) <= 0x4000L) || ((a) >= 0x8000L && (a) + (n) <= 0x10000L))
#if !FSCTX_FIXED(FSCTX_REQUEST_ADDRESS, 32)
#error "FSCTX_REQUEST_ADDRESS must fit fixed address space"
#endif
#if !FSCTX_FIXED(FSCTX_TRANSFER_ADDRESS, 512)
#error "FSCTX_TRANSFER_ADDRESS must fit fixed address space"
#endif
#if !FSCTX_FIXED(FSCTX_TABLE_ADDRESS, CTX_SIZE * CTX_MAX)
#error "FSCTX_TABLE_ADDRESS must fit fixed address space"
#endif
#if !FSCTX_FIXED(FSCTX_PENDING_ADDRESS, 64)
#error "FSCTX_PENDING_ADDRESS must fit fixed address space"
#endif
#if !FSCTX_FIXED(FSCTX_DIAG_ADDRESS, 4)
#error "FSCTX_DIAG_ADDRESS must fit fixed address space"
#endif
#if !FSCTX_FIXED(FSCTX_CURSOR_ADDRESS, FSCTX_CURSOR_SIZE)
#error "FSCTX_CURSOR_ADDRESS must fit fixed address space"
#endif
#define FSCTX_DISJOINT(a, n, b, m) ((a) + (n) <= (b) || (b) + (m) <= (a))
#if !FSCTX_DISJOINT(FSCTX_REQUEST_ADDRESS, 32, FSCTX_TRANSFER_ADDRESS, 512)
#error "FSCTX_REQUEST_ADDRESS overlaps FSCTX_TRANSFER_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_REQUEST_ADDRESS, 32, FSCTX_TABLE_ADDRESS, CTX_SIZE * CTX_MAX)
#error "FSCTX_REQUEST_ADDRESS overlaps FSCTX_TABLE_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_REQUEST_ADDRESS, 32, FSCTX_PENDING_ADDRESS, 64)
#error "FSCTX_REQUEST_ADDRESS overlaps FSCTX_PENDING_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_REQUEST_ADDRESS, 32, FSCTX_DIAG_ADDRESS, 4)
#error "FSCTX_REQUEST_ADDRESS overlaps FSCTX_DIAG_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_REQUEST_ADDRESS, 32, FSCTX_CURSOR_ADDRESS, FSCTX_CURSOR_SIZE)
#error "FSCTX_REQUEST_ADDRESS overlaps FSCTX_CURSOR_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_TRANSFER_ADDRESS, 512, FSCTX_TABLE_ADDRESS, CTX_SIZE * CTX_MAX)
#error "FSCTX_TRANSFER_ADDRESS overlaps FSCTX_TABLE_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_TRANSFER_ADDRESS, 512, FSCTX_PENDING_ADDRESS, 64)
#error "FSCTX_TRANSFER_ADDRESS overlaps FSCTX_PENDING_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_TRANSFER_ADDRESS, 512, FSCTX_DIAG_ADDRESS, 4)
#error "FSCTX_TRANSFER_ADDRESS overlaps FSCTX_DIAG_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_TRANSFER_ADDRESS, 512, FSCTX_CURSOR_ADDRESS, FSCTX_CURSOR_SIZE)
#error "FSCTX_TRANSFER_ADDRESS overlaps FSCTX_CURSOR_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_TABLE_ADDRESS, CTX_SIZE * CTX_MAX, FSCTX_PENDING_ADDRESS, 64)
#error "FSCTX_TABLE_ADDRESS overlaps FSCTX_PENDING_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_TABLE_ADDRESS, CTX_SIZE * CTX_MAX, FSCTX_DIAG_ADDRESS, 4)
#error "FSCTX_TABLE_ADDRESS overlaps FSCTX_DIAG_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_TABLE_ADDRESS, CTX_SIZE * CTX_MAX, FSCTX_CURSOR_ADDRESS, FSCTX_CURSOR_SIZE)
#error "FSCTX_TABLE_ADDRESS overlaps FSCTX_CURSOR_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_PENDING_ADDRESS, 64, FSCTX_DIAG_ADDRESS, 4)
#error "FSCTX_PENDING_ADDRESS overlaps FSCTX_DIAG_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_PENDING_ADDRESS, 64, FSCTX_CURSOR_ADDRESS, FSCTX_CURSOR_SIZE)
#error "FSCTX_PENDING_ADDRESS overlaps FSCTX_CURSOR_ADDRESS"
#endif
#if !FSCTX_DISJOINT(FSCTX_DIAG_ADDRESS, 4, FSCTX_CURSOR_ADDRESS, FSCTX_CURSOR_SIZE)
#error "FSCTX_DIAG_ADDRESS overlaps FSCTX_CURSOR_ADDRESS"
#endif
#undef FSCTX_FIXED
#undef FSCTX_DISJOINT
#endif
