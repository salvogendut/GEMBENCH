#include <assert.h>
#include <string.h>
#include "../kernel/kc/kcfg.h"

int main(void)
{
    char icons[9],font[9],cursor[9],backdrop[9],name[11];
    unsigned char drive,inks[5],debug;
    const char *text="ICONS=REFINED.IST\r\nFONT=ALTERN.FNT\r\nCURSOR=ALTCURS.SPR\r\nBACKDROP=WAVES.BDP\r\n";
    gb_cfg_parse(text,(unsigned int)strlen(text),icons,font,cursor,backdrop,&drive,inks,&debug);
#ifdef GB_CFG_ASSET_EXTENSIONS
    assert(!strcmp(icons,"REFINED") && !strcmp(font,"ALTERN") && !strcmp(cursor,"ALTCURS"));
    gb_make_83(font,"FNT",name);assert(!memcmp(name,"ALTERN  FNT",11));
    gb_make_83(icons,"IST",name);assert(!memcmp(name,"REFINED IST",11));
#else
    assert(!strcmp(icons,"REFINED.") && !strcmp(font,"ALTERN.F") && !strcmp(cursor,"ALTCURS."));
    (void)name; /* legacy parser semantics remain unchanged */
#endif
    assert(!strcmp(backdrop,"WAVES"));
    text="ICONS=EIGHT888.IST\nFONT=DEFAULT\nCURSOR=THIN\n";
    gb_cfg_parse(text,(unsigned int)strlen(text),icons,font,cursor,backdrop,&drive,inks,&debug);
    assert(!strcmp(icons,"EIGHT888") && !strcmp(font,"DEFAULT") && !strcmp(cursor,"THIN"));
    return 0;
}
