/* Exercise the actual Desktop fragment, with observable service/launch leaves. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_DEFER_MESSAGES 1
#define GB_DEFER_SHELL 1
#define GB_SHELL_ACTIVATE 2
#define GB_DESK_CATALOG_DATA
#include "../include/gembench/gbdesk_catalog.h"
typedef unsigned short gb_owner_t;
typedef struct { gb_owner_t receiver; unsigned char type,p0,p1,p2; } gb_defer_send_t;
static gb_owner_t found;
static unsigned char full, send_status, lookup_id;
static unsigned int finds,sends,capacity_checks,alerts,opens;
static gb_defer_send_t sent;
static char opened[12];
static gb_owner_t gb_defer_find_accessory(unsigned char id)
{ ++finds; lookup_id=id; return found; }
static unsigned char gb_defer_send(const gb_defer_send_t *m)
{ ++sends; sent=*m; return send_status; }
static unsigned char gb_wm_full(void) { ++capacity_checks; return full; }
static void gb_alert(const char *a,const char *b) { assert(a && b); ++alerts; }
static void gb_wm_open(const char *name) { ++opens; memcpy(opened,name,11); }
#include "../apps/desktop/core/accessory_open.inc"
static void reset(void) { finds=sends=capacity_checks=alerts=opens=0; }
int main(void)
{
    /* A full window table cannot prevent activation of an existing endpoint. */
    found=0x0302; full=1; open_accessory(GB_DESK_ACCESSORY_CALCULATOR_INDEX);
    assert(finds==1 && lookup_id==2 && sends==1 && !capacity_checks && !alerts && !opens);
    assert(sent.receiver==found && sent.type==1 && sent.p0==2 && !sent.p1 && !sent.p2);
    reset(); send_status=4; open_accessory(1);
    assert(sends==1 && !opens && !capacity_checks); /* FIFO full is not absence */
    reset(); found=0; open_accessory(1);
    assert(capacity_checks==1 && alerts==1 && !opens && !sends);
    reset(); full=0; open_accessory(1);
    assert(opens==1 && !strcmp(opened,"CALC    APP") && !alerts && !sends);
    reset(); open_accessory(GB_DESK_ACCESSORY_COUNT);
    assert(!finds && !sends && !opens && !capacity_checks);
    puts("shared Desktop accessory: exact identity, full table, failure, launch, bounds PASS");
    return 0;
}
