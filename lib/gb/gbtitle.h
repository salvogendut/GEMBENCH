#ifndef GBTITLE_H
#define GBTITLE_H

/* Install the paged title renderer. A current 56-byte TBR replaces only the
 * repeated background; a legacy 106-byte TBR also replaces both gadget tiles. */
void gb_titlebar_install(unsigned int size);

/* Boot-time entry: force installation of the renderer and composed fallback. */
void gb_titlebar_init(unsigned int size);

/* Replace the close/maximize pair from a canonical 50-byte GDT. */
void gb_gadgets_install(unsigned int size);

#endif
