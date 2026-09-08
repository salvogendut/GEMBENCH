/* Build-matched native CPC profile, not a universal APP. Bindings must be
 * generated from the composed runtime; never inherit legacy low-RAM services. */
#ifndef GB_SETTINGS_CPC_H
#define GB_SETTINGS_CPC_H
#if !defined(GB_CPC_RESTART) || !defined(GB_PREEMPTIVE) || !defined(GB_NATIVE_WINDOW_KIND)
#error "CPC Settings requires the native preemptive managed-window profile"
#endif
#ifndef GB_SETTINGS_BINDINGS
#error "Settings requires checked CPC runtime bindings"
#endif
#include GB_SETTINGS_BINDINGS
#define GB_SETTINGS_PROVIDER_VERSION 1
#define GB_SETTINGS_APPEARANCE_ONLY 1
/* At most 16 prefixed eight-character stems plus SOLID fit UI_TEXT (232 B). */
#define GB_SETTINGS_MAX_STEMS 16
#define SETTINGS_FONT_NAME KCFG_FONTNAME
#define SETTINGS_ICON_NAME KCFG_ICONNAME
#define SETTINGS_CURSOR_NAME KCFG_CURSORNAME
#define SETTINGS_BACKDROP_NAME KCFG_BDPNAME
#define SETTINGS_BACKDROP_SOLID KCFG_BD_SOLID

/* Picker re-entry state belongs to this app. Owned filesystem contexts, not
 * the retired global copy-buffer claim, isolate it from other applications. */
extern volatile unsigned char settings_storage_claim;
#undef gb_drop_claim
#undef gb_drop_release
#undef gb_drop_claimed
#define gb_drop_claim() (settings_storage_claim=1)
#define gb_drop_release() (settings_storage_claim=0)
#define gb_drop_claimed() (settings_storage_claim!=0)

unsigned char settings_begin(char *text, unsigned int *length);
void settings_end(void);
void settings_io_reset(void);
unsigned char settings_io_failed(void);
unsigned char settings_commit(const char *key, const char *value,
                              char *text, unsigned int *length);
#endif
