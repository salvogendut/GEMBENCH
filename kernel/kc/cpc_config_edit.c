/* Native config persistence binding. Text editing is the actual Settings
 * implementation; only request admission, owned I/O and publication differ. */
#include "gb.h"
#include "gbfsctx.h"
#include GB_UI_PROVIDER

static char cfgbuf[512], verify[128];
static unsigned int cfglen;
static gb_fsctx_t context;
static unsigned char value_length;

#include "../../apps/settings/core/config_keypos.inc"

static unsigned char equal(const char *a,const char *b)
{
    while (*a && *a==*b) { a++;b++; }
    return *a==*b;
}
static unsigned char valid_request(void)
{
    static const char *const keys[]={"FONT=","ICONS=","CURSOR=","TITLEBAR=","GADGETS=","BACKDROP="};
    static const char *const exts[]={"FNT","IST","SPR","TBR","GDT","BDP"};
    unsigned char i,k,stem=0;
    const char *p=UI_TEXT;
    if (UI_OP!=CPC_EDIT_OP) return 0;
    for (i=0;i<16 && UI_NAME[i];i++) ;
    if (i==16) return 0;
    for (k=0;k<6 && !equal(UI_NAME,keys[k]);k++) ;
    if (k==6) return 0;
    while (stem<8 && ((*p>='A' && *p<='Z') || (*p>='0' && *p<='9') ||
                     *p=='_' || *p=='-' || *p=='~')) { stem++;p++; }
    if (!stem) return 0;
    if (*p=='.') {
        p++;
        for (i=0;i<3;i++) if (*p++!=exts[k][i]) return 0;
    }
    if (*p) return 0;
    value_length=(unsigned char)(p-UI_TEXT);
    return 1;
}
static unsigned char io_error(void)
{
    unsigned char status=gb_fsctx_status();
    if (status) { CPC_EDIT_ERROR=status;return 1; }
    /* FSCTX's inherited zero-read ambiguity is not safe for config writes.
     * The native provider can additionally inspect its transport result. */
    if (CPC_EDIT_IO_STATUS>=2) { CPC_EDIT_ERROR=16+CPC_EDIT_IO_STATUS;return 1; }
    return 0;
}
static void persist(void)
{
    unsigned int offset=0,got;
    unsigned char i,amount,status;
    CPC_EDIT_STATUS=5;
    status=gb_fsctx_rewind(context);
    if (!status) status=gb_fsctx_write(context,cfgbuf,cfglen);
    if (status) { CPC_EDIT_ERROR=status;return; }
    CPC_EDIT_STATUS=6;
    status=gb_fsctx_rewind(context);
    if (status) { CPC_EDIT_ERROR=status;return; }
    while (offset<cfglen) {
        amount=(cfglen-offset>128)?128:(unsigned char)(cfglen-offset);
        got=gb_fsctx_read(context,verify,amount);
        if (io_error() || got!=amount) return;
        for (i=0;i<amount;i++) if (verify[i]!=cfgbuf[offset+i]) return;
        offset+=amount;
    }
    got=gb_fsctx_read(context,verify,1);
    if (io_error() || got) return; /* replacement must not leave an old tail */
    CPC_EDIT_CHANGED=1;
    CPC_EDIT_STATUS=0;
    UI_RES=1;
}
static void cfg_set(const char *key,const char *val)
{
#include "../../apps/settings/core/config_edit.inc"
    persist();
}

void main(void)
{
    unsigned int i,p,end,got;
    unsigned char status;
    UI_RES=0;GB_UI_STATUS=2;
    CPC_EDIT_STATUS=2;CPC_EDIT_CHANGED=0;CPC_EDIT_ERROR=0;
    if (!valid_request()) return;
    CPC_EDIT_STATUS=7;
    context=gb_fsctx_open(0);
    if (!context) { CPC_EDIT_ERROR=gb_fsctx_status();GB_UI_STATUS=4;return; }
    status=gb_fsctx_set_path(context,"/");
    if (!status) status=gb_fsctx_set_name(context,"GEOBENCHCFG");
    if (status) { CPC_EDIT_ERROR=status;goto done; }
    CPC_EDIT_STATUS=3;
    cfglen=gb_fsctx_read(context,cfgbuf,sizeof(cfgbuf));
    if (io_error() || !cfglen) goto done;
    if (cfglen==sizeof(cfgbuf)) {
        got=gb_fsctx_read(context,verify,1);
        if (io_error() || got) goto done;
    }
    for (i=0;i<cfglen;i++) if (!cfgbuf[i]) goto done;
    CPC_EDIT_STATUS=4;
    p=cfg_keypos(UI_NAME);
    if (p!=0xFFFF) {
        end=p;
        while (end<cfglen && cfgbuf[end]!='\r' && cfgbuf[end]!='\n') end++;
        /* The shared legacy editor's value-length arithmetic is u8. Keep
         * malformed long values outside it without changing MSX behavior. */
        if (end-p>255) goto done;
        if (end-p==value_length) {
            for (i=0;i<value_length && cfgbuf[p+i]==UI_TEXT[i];i++) ;
            if (i==value_length) { CPC_EDIT_STATUS=0;UI_RES=1;goto done; }
        }
    } else if (cfgbuf[cfglen-1]!='\r' && cfgbuf[cfglen-1]!='\n') {
        goto done; /* legacy append needs a preceding line terminator */
    }
    cfg_set(UI_NAME,UI_TEXT);
done:
    status=gb_fsctx_close(context);
    if (status) { CPC_EDIT_STATUS=7;CPC_EDIT_ERROR=status;UI_RES=0; }
    GB_UI_STATUS=UI_RES?0:4;
}
