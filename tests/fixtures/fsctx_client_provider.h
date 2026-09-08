/* Separate host-backed storage for the real client implementation. */
#ifndef TEST_FSCTX_CLIENT_PROVIDER_H
#define TEST_FSCTX_CLIENT_PROVIDER_H
#include <stdint.h>
#ifndef FIXTURE_BASE
#define FIXTURE_BASE 0x2000
#endif
#ifndef GB_FSCTX_REQUEST_ADDRESS
#define GB_FSCTX_REQUEST_ADDRESS FIXTURE_BASE
#endif
#ifndef GB_FSCTX_TRANSFER_ADDRESS
#define GB_FSCTX_TRANSFER_ADDRESS (FIXTURE_BASE + 0x100)
#endif
static union { uint16_t alignment; unsigned char bytes[65536]; } client_memory;
#define GB_FSCTX_REQUEST (client_memory.bytes + GB_FSCTX_REQUEST_ADDRESS)
#define GB_FSCTX_TRANSFER (client_memory.bytes + GB_FSCTX_TRANSFER_ADDRESS)
#define GB_FSCTX_WORD_AT(offset) (*(uint16_t *)(client_memory.bytes + GB_FSCTX_REQUEST_ADDRESS + (offset)))
#endif
