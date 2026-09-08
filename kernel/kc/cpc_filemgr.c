/* Binding only: the real File Manager owns navigation, menus and drawing.
 * Use the existing serialized config module and shared launch transaction. */
#include "gb.h"
#include "gbfsctx.h"
#include GB_FILEMGR_BINDINGS

extern void cpc_config_update(void);

unsigned char filemgr_save_view(unsigned char view)
{
    const char *key="VIEW=", *value=view ? "DEFAULT" : "LIST";
    unsigned char i;
    if (view>1) return 0;
    for (i=0;key[i];i++) UI_NAME[i]=key[i];
    UI_NAME[i]=0;
    for (i=0;value[i];i++) UI_TEXT[i]=value[i];
    UI_TEXT[i]=0;UI_OP=CPC_EDIT_OP;
    cpc_config_update();
    return UI_RES==1;
}

unsigned char filemgr_open_file(gb_fsctx_t context, const char *path,
                               const char *name11)
{
    static const char names[3][12]={"CLOCK   APP","CALC    APP","ABIPROBEAPP"};
    static const char directory[]="/GBENCH";
    unsigned char i,k,focus;
    /* This receiver currently loads only from the system directory. Never
     * silently launch a same-named file there when the user selected another
     * directory. Data-file handoff and other applications stay explicit gates. */
    if (!path || !name11) return 1;
    for (i=0;directory[i];i++) if (path[i]!=directory[i]) return 1;
    if (path[i]) return 1;
    for (k=0;k<3;k++) {
        for (i=0;i<11 && name11[i]==names[k][i];i++) ;
        if (i==11) break;
    }
    if (k==3) return 1;
    if (gb_fsctx_activate(context)!=GB_FSCTX_OK) return 2;
    if (FILEMGR_WINDOW_COUNT>=FILEMGR_WINDOW_LIMIT || !FILEMGR_FREE_PAGES) return 2;
    focus=FILEMGR_FOCUS;
    gb_wm_open(name11);
    /* The qualified apps must open/focus or activate a window. The shared
     * transaction restores our page and cleans up a non-registering load.
     * Do not infer success from the native void trampoline's leftover A. */
    return FILEMGR_FOCUS==focus ? 2 : 0;
}
