/* Diagnostic-only GBEDIT client, linked only onto a disposable Settings card.
 * Preserve real M4 reads/writes and corrupt one byte in a verification reply.
 * Initial config read is 512 bytes; verification reads are at most 128 bytes. */
#define gb_fsctx_read settings_actual_read
#include "../lib/gembench/gbfsctx.c"
#undef gb_fsctx_read

unsigned int gb_fsctx_read(gb_fsctx_t context, char *buffer, unsigned int size)
{
    unsigned int got = settings_actual_read(context, buffer, size);
    if (got && size > 1 && size <= 128) ((unsigned char *)buffer)[0] ^= 1;
    return got;
}
