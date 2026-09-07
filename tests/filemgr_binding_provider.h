#ifndef TEST_FILEMGR_BINDINGS_H
#define TEST_FILEMGR_BINDINGS_H
extern char fm_test_config[512],fm_test_ui_name[16],fm_test_ui_text[232];
extern unsigned int fm_test_config_length;
extern unsigned char fm_test_ui_op,fm_test_ui_result,fm_test_focus,fm_test_windows,fm_test_pages;
#define KCFG_TEXT fm_test_config
#define KCFG_LEN fm_test_config_length
#define UI_NAME fm_test_ui_name
#define UI_TEXT fm_test_ui_text
#define UI_OP fm_test_ui_op
#define UI_RES fm_test_ui_result
#define CPC_EDIT_OP 26
#define FILEMGR_FOCUS fm_test_focus
#define FILEMGR_WINDOW_COUNT fm_test_windows
#define FILEMGR_FREE_PAGES fm_test_pages
#define FILEMGR_WINDOW_LIMIT 8
#endif
