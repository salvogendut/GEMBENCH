#ifndef GEMBENCH_GBR_GEOMETRY_H
#define GEMBENCH_GBR_GEOMETRY_H

/* Keep legacy target extents out of universal resource source. The universal
 * profile obtains both values from the receiver's v6 sysinfo at runtime. */
#ifdef GB_UNIVERSAL
#include "gbuniversal.h"
static unsigned int gbr_screen_width(void)
{
    return gb_screen_width_pixels();
}
static unsigned int gbr_screen_height(void)
{
    return gb_screen_lines();
}
#else
#include "gb.h"
#define gbr_screen_width() ((unsigned int)GB_XPIX)
#define gbr_screen_height() ((unsigned int)GB_LINES)
#endif

#endif
