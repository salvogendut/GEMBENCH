#ifndef TEST_DESKTOP_BINDINGS_H
#define TEST_DESKTOP_BINDINGS_H
extern unsigned char host_menu[37],host_fullscreen,host_hour,host_minute,host_binary;
extern unsigned char host_ui_op,host_ui_col,host_ui_line,host_focus,host_windows,host_pages;
extern volatile gb_msg_t host_message;
#define KCFG_MEMSTR "512K"
#define DESKTOP_MENU host_menu
#define DESKTOP_FULLSCREEN (&host_fullscreen)
#define DESKTOP_KERNEL_BYTES 15432u
#define FILEMGR_FOCUS host_focus
#define FILEMGR_WINDOW_COUNT host_windows
#define FILEMGR_WINDOW_LIMIT 8
#define FILEMGR_FREE_PAGES host_pages
#define UI_OP host_ui_op
#define UI_COL host_ui_col
#define UI_LINE host_ui_line
#undef gb_msg
#define gb_msg host_message
#undef gb_hour
#undef gb_min
#undef gb_binmode
#define gb_hour host_hour
#define gb_min host_minute
#define gb_binmode host_binary
#endif
