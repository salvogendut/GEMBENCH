/* Serialized native root calls only. Provider supplies a fixed 32-byte request
 * and a separate 512-byte transfer buffer. GB_FSCTX_WORD_AT is a 16-bit lvalue
 * on the target. The public GB_FSCTX gate captures owner identity and completes
 * synchronously; no provider may retain pointers to caller buffers.
 * Transfer contents (including batch entries) expire at the next context call.
 * Keep wrappers' existing pointer preconditions and error/partial-copy behavior.
 * This is not a new universal filesystem capability; the frozen gate remains
 * 0x80D2. Local span checks do not prove the full platform/stack/ROM map. */
#ifndef GEMBENCH_FSCTX_CLIENT_CONTRACT_H
#define GEMBENCH_FSCTX_CLIENT_CONTRACT_H
#if GB_FSCTX_CAPACITY != 4 || GB_FSCTX_TRANSFER_MAX != 512 || GB_FSCTX_PATH_MAX != 47 || GB_FSCTX_DIRECTORY_BATCH != 4
#error "Keep the frozen filesystem-client capacities synchronized"
#endif
#define GB_FSCTX_FIXED(a, n) (((a) >= 0 && (a)+(n) <= 0x4000L) || ((a) >= 0x8000L && (a)+(n) <= 0x10000L))
#if !GB_FSCTX_FIXED(GB_FSCTX_REQUEST_ADDRESS, 32)
#error "Filesystem request must remain fixed"
#endif
#if !GB_FSCTX_FIXED(GB_FSCTX_TRANSFER_ADDRESS, 512)
#error "Filesystem transfer must remain fixed"
#endif
#if !((GB_FSCTX_REQUEST_ADDRESS+32 <= GB_FSCTX_TRANSFER_ADDRESS) || (GB_FSCTX_TRANSFER_ADDRESS+512 <= GB_FSCTX_REQUEST_ADDRESS))
#error "Filesystem request overlaps transfer"
#endif
#undef GB_FSCTX_FIXED
#endif
