#include <stdio.h>
#include <string.h>

#include "gbshell.h"

static unsigned int failures;
static unsigned char mock_handle;
static unsigned char mock_result;
static unsigned char find_class;
static unsigned char send_handle;
static unsigned char send_request;
static const char *send_argument;
static unsigned char send_calls;

static void check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

unsigned char gb_shell_find(unsigned char service_class)
{
    find_class = service_class;
    return mock_handle;
}

unsigned char gb_shell_send(unsigned char handle, unsigned char request,
                            const char *argument11)
{
    send_calls++;
    send_handle = handle;
    send_request = request;
    send_argument = argument11;
    return mock_result;
}

static void reset(unsigned char handle, unsigned char result)
{
    mock_handle = handle;
    mock_result = result;
    find_class = 0;
    send_handle = 0;
    send_request = 0;
    send_argument = NULL;
    send_calls = 0;
}

int main(void)
{
    static const char name[11] = {
        'R', 'E', 'A', 'D', 'M', 'E', ' ', ' ', 'T', 'X', 'T'
    };
    unsigned char result;

    check(GB_MSG_SHELL == 11, "shell message appends after GEMBENCH-1 values");
    check((GB_SHELL_CLASS_TEXT_EDITOR & GB_SHELL_CLASS_MASK) ==
              GB_SHELL_CLASS_TEXT_EDITOR,
          "text-editor identity occupies only service-class bits");
    check(GB_SHELL_OPEN < GB_SHELL_ACTIVATE &&
              GB_SHELL_ACTIVATE < GB_SHELL_CLOSE &&
              GB_SHELL_CLOSE < GB_SHELL_QUIT,
          "standard request identities are stable and ordered");

    reset(0, GB_SHELL_OK);
    result = gb_shell_request(GB_SHELL_CLASS_TEXT_EDITOR, GB_SHELL_OPEN, name);
    check(result == GB_SHELL_NOT_FOUND, "missing provider is reported explicitly");
    check(find_class == GB_SHELL_CLASS_TEXT_EDITOR,
          "request discovers the requested service class");
    check(send_calls == 0, "missing provider never dispatches a stale handle");

    reset(4, GB_SHELL_OK);
    result = gb_shell_request(GB_SHELL_CLASS_TEXT_EDITOR, GB_SHELL_OPEN, name);
    check(result == GB_SHELL_OK, "target success is returned to the caller");
    check(send_calls == 1 && send_handle == 4 && send_request == GB_SHELL_OPEN,
          "discovered handle and request are forwarded exactly once");
    check(send_argument == name && memcmp(send_argument, name, 11) == 0,
          "the fixed 11-byte open argument is forwarded without copying");

    reset(2, GB_SHELL_REJECTED);
    result = gb_shell_request(GB_SHELL_CLASS_TEXT_EDITOR, GB_SHELL_QUIT, NULL);
    check(result == GB_SHELL_REJECTED,
          "target rejection remains distinct from provider absence");
    check(send_calls == 1 && send_argument == NULL,
          "argument-free lifecycle requests retain a null argument");

    if (failures) return 1;
    puts("gbshell contract tests: ok");
    return 0;
}
