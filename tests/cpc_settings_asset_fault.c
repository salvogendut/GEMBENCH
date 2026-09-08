/* Test-only race fixture: an enumerated icon disappears before it is opened.
 * Redirect only BROKEN.IST to an absent file; the resulting error comes from
 * the actual M4 FOPEN path. Other reads and the Settings provider are unchanged. */
#define gb_fsctx_set_name settings_actual_name
#include "../lib/gembench/gbfsctx.c"
#undef gb_fsctx_set_name

unsigned char gb_fsctx_set_name(gb_fsctx_t context, const char *name)
{
    static const char trigger[] = "BROKEN  IST";
    unsigned char i;
    for (i=0; i<11 && name[i]==trigger[i]; i++) ;
    return settings_actual_name(context, i==11 ? "ABSENT  IST" : name);
}
