#include <stdio.h>
#include <string.h>

#include "gburl.h"

static int failures;

static void check_url(const char *base, const char *link,
                      const char *expected, const char *name)
{
    strcpy(GB_URL_BASE, base);
    strcpy(GB_URL_LINK, link);
    if (gb_url_resolve() && !strcmp(GB_URL_RESULT, expected))
        printf("ok   %s\n", name);
    else {
        printf("FAIL %s: got '%s'\n", name, GB_URL_RESULT);
        failures++;
    }
}

int main(void)
{
    check_url("http://example.com/a/page.htm", "/search?q=x",
              "http://example.com/search?q=x", "root-relative URL");
    check_url("http://example.com/a/page.htm?old=1", "?q=x",
              "http://example.com/a/page.htm?q=x", "query-only URL");
    check_url("http://example.com/a/page.htm", "next.htm",
              "http://example.com/a/next.htm", "path-relative URL");
    check_url("http://example.com", "next.htm",
              "http://example.com/next.htm", "relative URL on host root");
    check_url("http://example.com/a", "//other.example/x",
              "http://other.example/x", "protocol-relative URL");
    check_url("http://example.com/a", "HTTP://other.example/x#part",
              "HTTP://other.example/x", "absolute URL and fragment removal");
    if (failures) {
        printf("\n%d URL test(s) FAILED\n", failures);
        return 1;
    }
    puts("\nall URL tests passed");
    return 0;
}
