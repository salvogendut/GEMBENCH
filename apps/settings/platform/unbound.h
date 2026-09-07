/* Compile-only contract for the CPC restart audit, also used by host tests.
 * These are unresolved requirements, NOT live CPC addresses or stub services.
 * Nothing built with this profile may be packaged or admitted as an APP. */
#ifndef GB_SETTINGS_UNBOUND_H
#define GB_SETTINGS_UNBOUND_H
#define GB_SETTINGS_PROVIDER_VERSION 1

extern char settings_font_name[11], settings_icon_name[11];
extern char settings_cursor_name[11], settings_backdrop_name[11];
extern char settings_config_text[512], settings_backdrop_tile[64];
extern volatile unsigned int settings_config_length;
extern volatile unsigned char settings_backdrop_solid, settings_backdrop_drive;
extern volatile unsigned char settings_inks[5], settings_framepen;
extern volatile unsigned char settings_saver_op, settings_saver_result;
extern char settings_saver_text[GB_SSCFG_TEXT_CAP], settings_saver_modname[11];
extern char settings_copybuf[GB_COPYMAX];
extern volatile unsigned char settings_storage_claim;
extern volatile gb_msg_t settings_message;

#define SETTINGS_FONT_NAME settings_font_name
#define SETTINGS_ICON_NAME settings_icon_name
#define SETTINGS_CURSOR_NAME settings_cursor_name
#define SETTINGS_BACKDROP_NAME settings_backdrop_name
#define SETTINGS_CONFIG_TEXT settings_config_text
#define SETTINGS_CONFIG_LENGTH settings_config_length
#define SETTINGS_BACKDROP_SOLID settings_backdrop_solid
#define SETTINGS_BACKDROP_DRIVE settings_backdrop_drive
#define SETTINGS_BACKDROP_TILE settings_backdrop_tile
#define KCFG_INKS_ADDR settings_inks
#define KCFG_FRAMEPEN_ADDR settings_framepen
#define SETTINGS_SAVER_OP settings_saver_op
#define SETTINGS_SAVER_RESULT settings_saver_result
#define SETTINGS_SAVER_TEXT settings_saver_text
#define SETTINGS_SAVER_MODNAME settings_saver_modname

#undef gb_copybuf
#define gb_copybuf settings_copybuf
#undef gb_drop_claim
#undef gb_drop_release
#undef gb_drop_claimed
#define gb_drop_claim() (settings_storage_claim |= 0x80)
#define gb_drop_release() (settings_storage_claim &= 0x7F)
#define gb_drop_claimed() ((settings_storage_claim & 0x80) != 0)
#undef gb_msg
#define gb_msg settings_message

extern void settings_set_ink(unsigned char pen, unsigned char ink);
extern unsigned char settings_run_saver(void);
#define GB_SETTINGS_INK_IMPLEMENTATION "platform/ink_unbound.inc"
#define GB_SETTINGS_SAVER_IMPLEMENTATION "platform/saver_unbound.inc"
#endif
