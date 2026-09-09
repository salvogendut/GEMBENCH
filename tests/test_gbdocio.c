/* Exercise the actual document helper AND shared filesystem client. Only the
 * synchronous storage gate is fake. This does not qualify either emulator or
 * the universal GB_PARAMS transport. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_FSCTX_PLATFORM_HEADER "fsctx_client_provider.h"
#include "../lib/gembench/gbfsctx.c"
#include "gbdocio.h"

static struct {
    char bytes[5000];
    unsigned int length, offset;
} files[2];
static unsigned int calls, fail_at, read_max;
static unsigned char failure;

unsigned char gb_fsctx_call(unsigned char op)
{
    unsigned int index, count;
    calls++;
    F_STATUS = GB_FSCTX_OK;
    if (calls == fail_at) return F_STATUS = failure;
    if (F_HANDLE != 0x0101 && F_HANDLE != 0x0102)
        return F_STATUS = GB_FSCTX_ERR_STALE;
    index = F_HANDLE - 0x0101;
    switch (op) {
    case OP_REWIND:
        files[index].offset = 0;
        break;
    case OP_READ:
        assert(F_LENGTH && F_LENGTH <= 512);
        assert(files[index].offset <= files[index].length);
        count = files[index].length - files[index].offset;
        if (count > F_LENGTH) count = F_LENGTH;
        if (count > read_max) count = read_max;
        memcpy((void *)F_TRANSFER, files[index].bytes + files[index].offset, count);
        files[index].offset += count;
        F_ACTUAL = count;
        break;
    case OP_WRITE:
        assert(F_LENGTH <= 512);
        assert(files[index].offset + F_LENGTH <= sizeof(files[index].bytes));
        if (!files[index].offset) files[index].length = 0;
        memcpy(files[index].bytes + files[index].offset, (void *)F_TRANSFER, F_LENGTH);
        files[index].offset += F_LENGTH;
        files[index].length = files[index].offset;
        break;
    default:
        assert(!"document helper must not allocate/close/change borrowed context");
    }
    return F_STATUS;
}

static void reset(void)
{
    memset(files, 0, sizeof(files));
    calls = fail_at = 0;
    read_max = 512;
    failure = GB_FSCTX_ERR_IO;
}

static void step(gb_docio_t *job)
{
    unsigned int before = calls;
    unsigned char was_busy = gb_docio_busy(job);
    assert(gb_docio_step(job) == job->state);
    assert(calls == before + was_busy); /* exactly one operation per active step */
}

static void finish(gb_docio_t *job)
{
    unsigned int guard = 100;
    while (gb_docio_busy(job)) {
        assert(guard--);
        step(job);
    }
    step(job); /* all terminal states stay quiet */
}

static void pattern(char *buffer, unsigned int size)
{
    unsigned int i;
    /* Includes NUL, LF, CR and high-bit bytes: no implicit string conversion. */
    for (i = 0; i < size; i++) buffer[i] = (char)(i * 31u + i / 251u);
}

static void roundtrips(void)
{
    static const unsigned int sizes[] = {0, 1, 511, 512, 513, 4095, 4096};
    char input[4096], output[4098];
    unsigned int i, n;
    gb_docio_t job = {0};
    pattern(input, sizeof(input));
    for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        reset(); n = sizes[i];
        files[0].length = sizeof(files[0].bytes); /* replace, never append */
        files[0].offset = 100;
        assert(gb_docio_save(&job, 0x0101, n ? input : NULL, n));
        assert(!calls);
        finish(&job);
        assert(job.state == GB_DOCIO_DONE && !job.error && job.transferred == n);
        assert(files[0].length == n && !memcmp(files[0].bytes, input, n));
        assert(calls == 1u + (n ? (n + 511u) / 512u : 1u));
        memset(output, 0x69, sizeof(output));
        calls = 0;
        assert(gb_docio_load(&job, 0x0101, output + 1, n));
        finish(&job);
        assert(job.state == GB_DOCIO_DONE && job.transferred == n);
        assert(calls == 2u + (n + 511u) / 512u); /* rewind + payload + EOF */
        assert(output[0] == 0x69 && output[n + 1] == 0x69);
        assert(!memcmp(output + 1, input, n));
        assert(!memcmp(input, files[0].bytes, n));
    }
    reset();
    memcpy(files[0].bytes, "10 PRINT\r\n20 END\r\n", 18);
    files[0].length = 18;
    assert(gb_docio_load(&job, 0x0101, output, sizeof(output)));
    finish(&job);
    assert(job.state == GB_DOCIO_DONE && job.transferred == 18);
    assert(!memcmp(output, "10 PRINT\r\n20 END\r\n", 18));
}

static void load_limits(void)
{
    char output[4098];
    gb_docio_t job = {0};
    reset();
    memset(output, 0x69, sizeof(output));
    pattern(files[0].bytes, 4097); files[0].length = 4097;
    assert(gb_docio_load(&job, 0x0101, output + 1, 4096));
    finish(&job);
    assert(job.state == GB_DOCIO_ERROR && job.error == GB_DOCIO_ERR_TOO_LARGE);
    assert(job.transferred == 4096 && calls == 10);
    assert(output[0] == 0x69 && output[4097] == 0x69);
    assert(!memcmp(output + 1, files[0].bytes, 4096));
    assert(gb_docio_load(&job, 0x0101, NULL, 0));
    finish(&job);
    assert(job.state == GB_DOCIO_ERROR && job.error == GB_DOCIO_ERR_TOO_LARGE);
    files[0].length = 0;
    assert(gb_docio_load(&job, 0x0101, NULL, 0));
    finish(&job);
    assert(job.state == GB_DOCIO_DONE && !job.transferred && !job.error);

    reset();
    pattern(files[0].bytes, 513); files[0].length = 513;
    read_max = 127; /* nonzero short reads are not assumed to be EOF */
    assert(gb_docio_load(&job, 0x0101, output, sizeof(output)));
    finish(&job);
    assert(job.state == GB_DOCIO_DONE && job.transferred == 513);
    assert(!memcmp(output, files[0].bytes, 513));
}

static void errors(void)
{
    unsigned int i;
    unsigned char error;
    char buffer[4096];
    gb_docio_t job = {0};
    for (error = GB_FSCTX_ERR_UNSUPPORTED; error <= GB_FSCTX_ERR_CONTEXT; error++) {
        for (i = 1; i <= 10; i++) {
            reset(); fail_at = i; failure = error;
            pattern(files[0].bytes, 4096); files[0].length = 4096;
            memset(buffer, 0, sizeof(buffer));
            assert(gb_docio_load(&job, 0x0101, buffer, sizeof(buffer)));
            finish(&job);
            assert(job.state == GB_DOCIO_ERROR && job.error == error && calls == i);
            assert(job.transferred == (i <= 2 ? 0 : (i - 2u) * 512u));
            assert(!memcmp(buffer, files[0].bytes, job.transferred));
            /* An unrelated operation cannot overwrite this job's error. */
            assert(!gb_fsctx_rewind(0x0102));
            step(&job);
            assert(job.error == error && job.state == GB_DOCIO_ERROR);
        }
        for (i = 1; i <= 9; i++) {
            reset(); fail_at = i; failure = error;
            pattern(buffer, sizeof(buffer));
            assert(gb_docio_save(&job, 0x0101, buffer, sizeof(buffer)));
            finish(&job);
            assert(job.state == GB_DOCIO_ERROR && job.error == error && calls == i);
            assert(job.transferred == (i <= 2 ? 0 : (i - 2u) * 512u));
            assert(files[0].length == job.transferred);
            assert(!memcmp(files[0].bytes, buffer, job.transferred));
        }
    }
    reset();
    assert(gb_docio_load(&job, 0x0201, buffer, sizeof(buffer)));
    finish(&job);
    assert(job.state == GB_DOCIO_ERROR && job.error == GB_FSCTX_ERR_STALE);
}

static void lifecycle(void)
{
    gb_docio_t job = {0}, other = {0}, snapshot;
    char first[513], second[513];
    reset();
    assert(!gb_docio_busy(NULL) && !gb_docio_cancel(NULL));
    assert(gb_docio_step(NULL) == GB_DOCIO_IDLE);
    assert(!gb_docio_load(NULL, 0x0101, first, sizeof(first)));
    assert(!gb_docio_save(NULL, 0x0101, first, sizeof(first)));
    assert(!gb_docio_load(&job, 0, first, sizeof(first)));
    assert(!gb_docio_save(&job, 0, first, sizeof(first)));
    assert(!gb_docio_load(&job, 0x0101, NULL, 1));
    assert(!gb_docio_save(&job, 0x0101, NULL, 1));
    step(&job);
    assert(!calls && !gb_docio_cancel(&job));

    assert(gb_docio_load(&job, 0x0101, first, sizeof(first)));
    memcpy(&snapshot, &job, sizeof(job));
    assert(!gb_docio_save(&job, 0x0102, second, sizeof(second)));
    assert(!gb_docio_load(&job, 0x0102, second, sizeof(second)));
    assert(!memcmp(&snapshot, &job, sizeof(job)) && !calls);
    assert(gb_docio_cancel(&job));
    assert(job.state == GB_DOCIO_CANCELLED && !job.transferred);
    step(&job);
    assert(!calls && !gb_docio_cancel(&job));

    pattern(first, sizeof(first));
    assert(gb_docio_save(&job, 0x0101, first, sizeof(first)));
    step(&job); step(&job);
    assert(job.transferred == 512 && files[0].length == 512);
    assert(gb_docio_cancel(&job));
    step(&job);
    assert(calls == 2 && files[0].length == 512); /* no rollback promise */
    assert(gb_docio_save(&job, 0x0101, "OK", 2));
    finish(&job);
    assert(job.state == GB_DOCIO_DONE && job.transferred == 2);
    assert(files[0].length == 2 && !memcmp(files[0].bytes, "OK", 2));

    reset();
    pattern(files[0].bytes, 513); files[0].length = 513;
    assert(gb_docio_load(&job, 0x0101, first, sizeof(first)));
    step(&job); step(&job);
    assert(gb_docio_cancel(&job));
    assert(job.transferred == 512 && !memcmp(first, files[0].bytes, 512));
    step(&job);
    assert(calls == 2);

    /* Different jobs keep their own progress and borrowed context identities. */
    memset(second, 'B', sizeof(second));
    assert(gb_docio_load(&job, 0x0101, first, sizeof(first)));
    assert(gb_docio_save(&other, 0x0102, second, sizeof(second)));
    while (gb_docio_busy(&job) || gb_docio_busy(&other)) {
        step(&job); step(&other);
    }
    assert(job.state == GB_DOCIO_DONE && other.state == GB_DOCIO_DONE);
    assert(job.transferred == 513 && other.transferred == 513);
    assert(!memcmp(first, files[0].bytes, 513));
    assert(!memcmp(second, files[1].bytes, 513));
}

int main(void)
{
    roundtrips(); load_limits(); errors(); lifecycle();
    puts("document I/O: boundary roundtrips, raw bytes, oversize, short reads, "
         "133 injected faults and borrowed-context lifecycle PASS");
    return 0;
}
