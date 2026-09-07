/* Existing native Settings bindings. Keep this profile byte-preserving;
 * the CPC restart must supply a complete, separately qualified provider. */
#ifndef GB_SETTINGS_LEGACY_H
#define GB_SETTINGS_LEGACY_H

#define GB_SETTINGS_PROVIDER_VERSION 1
#define SETTINGS_FONT_NAME ((char *)0x120D)
#define SETTINGS_ICON_NAME ((char *)0x1202)
#define SETTINGS_CURSOR_NAME ((char *)0x1221)
#define SETTINGS_BACKDROP_NAME ((char *)0x1231)
#define SETTINGS_CONFIG_TEXT ((char *)0x1000)
#define SETTINGS_CONFIG_LENGTH (*(volatile unsigned int *)0x1200)
#define SETTINGS_BACKDROP_SOLID (*(volatile unsigned char *)0x1290)
#define SETTINGS_BACKDROP_DRIVE (*(unsigned char *)0x123C)
#define SETTINGS_BACKDROP_TILE ((char *)0x1250)
#define KCFG_INKS_ADDR ((volatile unsigned char *)0x122C)
#define KCFG_FRAMEPEN_ADDR (*(volatile unsigned char *)0x133C)

#define SETTINGS_SAVER_OP GB_SSCFG_OP
#define SETTINGS_SAVER_RESULT GB_SSCFG_RESULT
#define SETTINGS_SAVER_TEXT GB_SSCFG_TEXT
#define SETTINGS_SAVER_MODNAME GB_SSCFG_MODNAME
#define GB_SETTINGS_INK_IMPLEMENTATION "platform/ink_legacy.inc"
#define GB_SETTINGS_SAVER_IMPLEMENTATION "platform/saver_legacy.inc"

#endif
