#include <stdio.h>
#include <string.h>

#include "gbform.h"

static int failures;

static void check(int ok, const char *name)
{
    if (ok) printf("ok   %s\n", name);
    else { printf("FAIL %s\n", name); failures++; }
}

static void test_frogfind(void)
{
    gb_form_process(GB_FORM_OPEN, " action=\"/\" method=\"get\"");
    check(GB_FORM_ACTIVE && !strcmp(GB_FORM_ACTION, "/"),
          "FrogFind GET form is accepted");
    check(gb_form_process(GB_FORM_INPUT,
                         " type=\"text\" size=\"30\" name=\"q\"") &&
              !strcmp(GB_FORM_NAME, "q") && !GB_FORM_VALUE[0],
          "FrogFind search field is captured");
    check(!gb_form_process(GB_FORM_INPUT,
                          " type=\"radio\" name=\"region\" value=\"au-en\""),
          "non-text controls are ignored");
    strcpy(GB_FORM_VALUE, "amstrad cpc&pcw");
    check(gb_form_build_url() &&
              !strcmp(GB_FORM_URL, "/?q=amstrad+cpc%26pcw"),
          "search values are encoded into the GET URL");
    check(!gb_form_process(GB_FORM_INPUT, " type=submit value='Ribbbit!'") &&
              !GB_FORM_ACTIVE && !strcmp(GB_FORM_VALUE, "amstrad cpc&pcw"),
          "non-text controls preserve the field value and terminate on submit");
    gb_form_process(GB_FORM_OPEN, " action=\"/\" method=\"get\"");
    gb_form_process(GB_FORM_CLOSE, "");
    check(!GB_FORM_ACTIVE, "closing form clears its state");
}

static void test_method_and_bounds(void)
{
    gb_form_process(GB_FORM_OPEN, " action='/post' method=POST");
    check(!GB_FORM_ACTIVE &&
              !gb_form_process(GB_FORM_INPUT, " name=q"),
          "POST forms are not exposed as GET controls");
    gb_form_process(GB_FORM_OPEN, "");
    check(GB_FORM_ACTIVE && !GB_FORM_ACTION[0] &&
              gb_form_process(GB_FORM_INPUT, " NAME=query VALUE='hello world'") &&
              !strcmp(GB_FORM_NAME, "query") &&
              !strcmp(GB_FORM_VALUE, "hello world"),
          "missing method/action and case-insensitive attributes are supported");
}

int main(void)
{
    test_frogfind();
    test_method_and_bounds();
    if (failures) {
        printf("\n%d form test(s) FAILED\n", failures);
        return 1;
    }
    puts("\nall form tests passed");
    return 0;
}
