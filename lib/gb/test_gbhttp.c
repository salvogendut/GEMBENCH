/* Host tests for the bounded streaming HTTP response parser. */
#include <stdio.h>
#include <string.h>

#define TEST_INVALID_RESPONSE 1
#define TEST_INVALID_STATUS   2
#define TEST_BAD_CHUNK        3
#define TEST_BAD_SIZE         4
#define TEST_TOO_LARGE        5
#define TEST_DONE             6

static unsigned char test_error;
static unsigned char test_finished;
static char *test_body;
static unsigned int test_body_used;
static char test_header_line[160];
static char test_location[16];

static unsigned char test_write(const unsigned char *buf, unsigned int len);
#define GB_HTTP_INVALID_RESPONSE() (test_error = TEST_INVALID_RESPONSE)
#define GB_HTTP_INVALID_STATUS() (test_error = TEST_INVALID_STATUS)
#define GB_HTTP_BODY_WRITE(buf, len) test_write((buf), (len))
#define GB_HTTP_FINISH() (test_finished = 1)
#define GB_HTTP_BAD_CHUNK() (test_error = TEST_BAD_CHUNK)
#define GB_HTTP_BAD_CHUNK_SIZE() (test_error = TEST_BAD_SIZE)
#define GB_HTTP_CHUNK_TOO_LARGE() (test_error = TEST_TOO_LARGE)
#define GB_HTTP_HEADER_LINE test_header_line
#define GB_HTTP_LOCATION test_location
#define GB_HTTP_LOCATION_MAX 15
#define GB_HTTP_ENABLE_RANGE 1
#include "gbhttp.h"

static int failures;

static void check(int ok, const char *name)
{
    if (ok) printf("ok   %s\n", name);
    else { printf("FAIL %s\n", name); failures++; }
}

static void header(const char *text)
{
    strcpy(test_header_line, text);
    gb_http_line_len = (unsigned char)strlen(test_header_line);
    gb_http_process_header_line();
}

static void test_headers(void)
{
    gb_http_response_init();
    test_error = 0;
    header("HTTP/1.1 206 Partial Content");
    check(!test_error && gb_http_status_code == 206,
          "status line is parsed");
    header("content-length: 256");
    check(!test_error && gb_http_have_length &&
              gb_http_content_length == 256,
          "Content-Length is case insensitive");
    header("Transfer-Encoding: gzip, chunked");
    check(!test_error && gb_http_chunked,
          "chunked transfer coding is detected");
    header("Location: /next  ");
    check(!test_error && gb_http_have_location == 1 &&
              !strcmp(test_location, "/next"),
          "Location uses caller-owned bounded storage");
    header("Content-Range: bytes 1536-4095/4096");
    check(!test_error && gb_http_have_content_range &&
              gb_http_range_start == 1536 && gb_http_range_total == 4096 &&
              gb_http_range_total_known && !gb_http_range_unsatisfied,
          "satisfied Content-Range is validated");

    gb_http_response_init();
    test_error = 0;
    header("HTTP/1.0 416 Range Not Satisfiable");
    header("Content-Range: bytes */4096");
    check(!test_error && gb_http_have_content_range &&
              gb_http_range_unsatisfied && gb_http_range_total_known &&
              gb_http_range_total == 4096,
          "unsatisfied Content-Range retains total length");

    gb_http_response_init();
    test_error = 0;
    header("NOT-HTTP 200 OK");
    check(test_error == TEST_INVALID_RESPONSE,
          "invalid status protocol is rejected");
    gb_http_response_init();
    test_error = 0;
    header("HTTP/1.1 xyz");
    check(test_error == TEST_INVALID_STATUS,
          "invalid status code is rejected");
    gb_http_response_init();
    header("HTTP/1.1 200 OK");
    header("Content-Length: 16777216");
    check(!gb_http_have_length, "oversized Content-Length is ignored");
    header("Location: /this/path/is/too/long");
    check(gb_http_have_location == 2, "oversized Location is reported");
}

static unsigned char test_write(const unsigned char *buf, unsigned int len)
{
    while (len--) test_body[test_body_used++] = (char)*buf++;
    return 1;
}

static unsigned char decode(const char *wire, char *body)
{
    gb_http_response_init();
    test_error = test_finished = 0;
    test_body = body;
    test_body_used = 0;
    while (*wire && !test_error && !test_finished)
        (void)gb_http_chunk_byte((unsigned char)*wire++);
    body[test_body_used] = 0;
    return test_finished ? TEST_DONE : test_error;
}

static void test_chunks(void)
{
    char body[32];
    check(decode("4\r\nWiki\r\n5;name=value\r\npedia\r\n0\r\nX-Test: 1\r\n\r\n",
                 body) == TEST_DONE && !strcmp(body, "Wikipedia"),
          "chunk extensions and trailers stream correctly");
    check(decode("\r\n", body) == TEST_BAD_CHUNK,
          "empty chunk size is rejected");
    check(decode("z\r\n", body) == TEST_BAD_SIZE,
          "non-hexadecimal chunk size is rejected");
    check(decode("1000000\r\n", body) == TEST_TOO_LARGE,
          "chunk size over 24 bits is rejected");
}

int main(void)
{
    test_headers();
    test_chunks();
    if (failures) {
        printf("\n%d HTTP test(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall HTTP tests passed\n");
    return 0;
}
