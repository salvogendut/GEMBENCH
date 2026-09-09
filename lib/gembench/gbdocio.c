/* Bounded document transfers over the existing owned filesystem client. */
#include "gbdocio.h"

unsigned char gb_docio_busy(const gb_docio_t *job)
{
    return job && job->state >= GB_DOCIO_LOAD_REWIND &&
           job->state <= GB_DOCIO_SAVE;
}

static void begin(gb_docio_t *job, gb_fsctx_t context, unsigned int limit,
                  unsigned char state)
{
    job->context = context;
    job->limit = limit;
    job->transferred = 0;
    job->error = GB_FSCTX_OK;
    job->state = state;
}

unsigned char gb_docio_load(gb_docio_t *job, gb_fsctx_t context,
                            char *buffer, unsigned int capacity)
{
    if (!job || !context || (!buffer && capacity) || gb_docio_busy(job)) return 0;
    begin(job, context, capacity, GB_DOCIO_LOAD_REWIND);
    job->buffer.load = buffer;
    return 1;
}

unsigned char gb_docio_save(gb_docio_t *job, gb_fsctx_t context,
                            const char *buffer, unsigned int length)
{
    if (!job || !context || (!buffer && length) || gb_docio_busy(job)) return 0;
    begin(job, context, length, GB_DOCIO_SAVE_REWIND);
    job->buffer.save = buffer;
    return 1;
}

unsigned char gb_docio_step(gb_docio_t *job)
{
    unsigned int count, amount;
    unsigned char error = GB_FSCTX_OK;
    if (!job) return GB_DOCIO_IDLE;
    switch (job->state) {
    case GB_DOCIO_LOAD_REWIND:
    case GB_DOCIO_SAVE_REWIND:
        error = gb_fsctx_rewind(job->context);
        if (error) break;
        if (job->state == GB_DOCIO_SAVE_REWIND) job->state = GB_DOCIO_SAVE;
        else job->state = job->limit ? GB_DOCIO_LOAD : GB_DOCIO_LOAD_EOF;
        break;
    case GB_DOCIO_LOAD:
        amount = job->limit - job->transferred;
        if (amount > GB_FSCTX_TRANSFER_MAX) amount = GB_FSCTX_TRANSFER_MAX;
        count = gb_fsctx_read(job->context, job->buffer.load + job->transferred,
                             amount);
        error = gb_fsctx_status();
        if (error) break;          /* zero bytes with an error is not EOF */
        job->transferred += count;
        if (!count) job->state = GB_DOCIO_DONE;
        else if (job->transferred == job->limit) job->state = GB_DOCIO_LOAD_EOF;
        break;
    case GB_DOCIO_LOAD_EOF:
        /* Exact-capacity files succeed; larger ones must not be silently
         * truncated. Probe into owned state, never past the document buffer. */
        count = gb_fsctx_read(job->context, &job->probe, 1);
        error = gb_fsctx_status();
        if (error) break;
        if (count) error = GB_DOCIO_ERR_TOO_LARGE;
        else job->state = GB_DOCIO_DONE;
        break;
    case GB_DOCIO_SAVE:
        amount = job->limit - job->transferred;
        if (amount > GB_FSCTX_TRANSFER_MAX) amount = GB_FSCTX_TRANSFER_MAX;
        /* Avoid even NULL + 0 for an empty file. A zero-length first write
         * is intentional: rewind alone does not truncate an existing file. */
        error = gb_fsctx_write(job->context,
            amount ? job->buffer.save + job->transferred : job->buffer.save,
            amount);
        if (error) break;
        job->transferred += amount;
        if (job->transferred == job->limit) job->state = GB_DOCIO_DONE;
        break;
    default:
        return job->state;
    }
    if (error) {
        job->error = error;
        job->state = GB_DOCIO_ERROR;
    }
    return job->state;
}

unsigned char gb_docio_cancel(gb_docio_t *job)
{
    if (!gb_docio_busy(job)) return 0;
    job->state = GB_DOCIO_CANCELLED;
    return 1;
}
