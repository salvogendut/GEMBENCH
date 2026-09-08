/* Boot-only native root binding; never select the legacy CPC startup path. */
#ifndef GB_DESKTOP_CPC_H
#define GB_DESKTOP_CPC_H
#ifndef GB_DESKTOP_BINDINGS
#error "Desktop requires checked CPC runtime bindings"
#endif
#include GB_DESKTOP_BINDINGS
#define GB_DESKTOP_PROVIDER_VERSION 1
#define MENU_DEF DESKTOP_MENU
#define WM_FS DESKTOP_FULLSCREEN
#define UI_OP_K UI_OP
#define UI_COL_K UI_COL
#define UI_LINE_K UI_LINE
#undef gb_ksize
#define gb_ksize DESKTOP_KERNEL_BYTES
#define gb_wm_full desktop_capacity
#define gb_wm_open desktop_open_app
extern unsigned char desktop_capacity(void);
extern void desktop_open_disk(unsigned char drive);
extern void desktop_open_app(const char *name);
extern void desktop_start(const gb_win_t *desc, void (*bar)(void));
extern void desktop_collect(void);
extern unsigned char gb_ui(void);
#endif
