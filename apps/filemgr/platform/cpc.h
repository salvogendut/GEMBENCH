/* Native CPC system-app binding. This is NOT a universal application profile.
 * Fixed addresses are emitted/checked against the composed runtime symbols;
 * no APP is staged until native package/launch qualification is complete. */
#ifndef GB_FILEMGR_CPC_H
#define GB_FILEMGR_CPC_H
#ifndef GB_FILEMGR_BINDINGS
#error "File Manager requires checked CPC runtime bindings"
#endif
#include GB_FILEMGR_BINDINGS
#define GB_FILEMGR_PROVIDER_VERSION 1
#define FILEMGR_CONFIG_TEXT KCFG_TEXT
#define FILEMGR_CONFIG_LENGTH (KCFG_LEN<=512u ? KCFG_LEN : 0u)
extern unsigned char filemgr_save_view(unsigned char view);
/* 0 opened, 1 unqualified type/location, 2 failed launch. */
extern unsigned char filemgr_open_file(gb_fsctx_t context, const char *path,
                                      const char *name11);
#endif
