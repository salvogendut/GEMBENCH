#ifndef TEST_SETTINGS_CPC_BINDINGS_H
#define TEST_SETTINGS_CPC_BINDINGS_H
extern char st_config[512], st_ui_name[16], st_ui_text[232];
extern char st_font[11], st_icons[11], st_cursor[11], st_backdrop[11];
extern unsigned int st_config_length;
extern unsigned char st_solid, st_ui_op, st_ui_result;
extern volatile gb_msg_t st_message;
#define KCFG_TEXT st_config
#define KCFG_LEN st_config_length
#define KCFG_FONTNAME st_font
#define KCFG_ICONNAME st_icons
#define KCFG_CURSORNAME st_cursor
#define KCFG_BDPNAME st_backdrop
#define KCFG_BD_SOLID st_solid
#define UI_NAME st_ui_name
#define UI_TEXT st_ui_text
#define UI_OP st_ui_op
#define UI_RES st_ui_result
#define CPC_EDIT_OP 26
#undef gb_msg
#define gb_msg st_message
#endif
