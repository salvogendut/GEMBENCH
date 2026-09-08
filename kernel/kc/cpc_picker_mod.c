/* Native file picker: the existing gbpick/gbdlg UI and FSCTX policy, bound to
 * an owned temporary context. No desktop/file-manager policy lives here. */
#include "gb.h"
#include "gbfsctx.h"
#include GB_UI_PROVIDER

#define UI_OP_PICKFILE 3
#define UI_OP_PICKDIR 4
static gb_fsctx_t context;
static gb_fsctx_entry_t entry;
static char path[48], candidate[48];
static unsigned char failed;

unsigned char cpc_picker_error(void) { return failed; }
static void check(unsigned char status)
{
    if (status && !failed) failed=status;
}
static void copy_path(char *to, const char *from)
{
    unsigned char i;
    for (i=0;i<48;i++) { to[i]=from[i]; if (!from[i]) break; }
}
static void change_path(void)
{
    unsigned char status=gb_fsctx_set_path(context,candidate);
    if (!status) status=gb_fsctx_activate(context);
    if (!status) copy_path(path,candidate);
    else {
        check(status);
        /* Rejected activation must not leave the context on a partial path. */
        gb_fsctx_set_path(context,path);
    }
}
void gb_back(void)
{
    unsigned char i=0;
    if (failed) return;
    if (path[0]=='/' && !path[1]) return;
    copy_path(candidate,path);
    while (candidate[i]) i++;
    while (i>1 && candidate[i-1]!='/') i--;
    if (i>1) i--;
    candidate[i]=0;
    change_path();
}
void gb_chdir(void)
{
    unsigned char i=0,j=0;
    if (failed || !(entry.attributes & GB_FSCTX_ATTR_DIRECTORY)) return;
    copy_path(candidate,path);
    while (candidate[i]) i++;
    if (i>1) candidate[i++]='/';
    while (j<8 && entry.name[j]!=' ') {
        if (i>=47) { failed=GB_FSCTX_ERR_BADARG; return; }
        candidate[i++]=entry.name[j++];
    }
    candidate[i]=0;
    change_path();
}
char *gb_entname(void) { return entry.name; }
unsigned char gb_isdir(void) { return (entry.attributes & GB_FSCTX_ATTR_DIRECTORY)!=0; }
char *gb_dir1(void)
{
    unsigned char got;
    if (failed) return 0;
    got=gb_fsctx_dir_first(context,&entry);
    check(gb_fsctx_status());
    return got ? entry.name : 0;
}
char *gb_dirn(void)
{
    unsigned char got;
    if (failed) return 0;
    got=gb_fsctx_dir_next(context,&entry);
    check(gb_fsctx_status());
    return got ? entry.name : 0;
}

static unsigned char valid_request(void)
{
    const char *p=UI_TEXT;
    unsigned char n=0,i;
    if (UI_OP!=UI_OP_PICKFILE && UI_OP!=UI_OP_PICKDIR) return 0;
    while (p<GB_UI_TEXT_END && *p) {
        if (++n>7) return 0;
        for (i=0;i<3;i++) {
            if (p>=GB_UI_TEXT_END || !((*p>='A' && *p<='Z') || (*p>='0' && *p<='9'))) return 0;
            p++;
        }
        if (p>=GB_UI_TEXT_END || *p++) return 0;
    }
    return p<GB_UI_TEXT_END;
}

void main(void)
{
    unsigned char i;
    char *p=UI_TEXT;
    UI_RES=0;
    GB_UI_STATUS=2;
    CPC_PICK_STATUS=0;
    if (!valid_request()) return;
    for (i=0;i<16;i++) UI_NAME[i]=0;
    failed=0;
    context=gb_fsctx_open(0);
    if (!context) { CPC_PICK_STATUS=gb_fsctx_status(); GB_UI_STATUS=4; return; }
    /* The private native handoff is caller-tagged, never borrowed across
     * owners. Complete per-application implicit FS views are a later gate. */
    path[0]='/';path[1]=0;
    if (CPC_PICK_OWNER==CPC_UI_OWNER) {
        for (i=0;i<48;i++) { path[i]=CPC_PICK_PATH[i]; if (!path[i]) break; }
        if (i==48 || path[0]!='/') { path[0]='/';path[1]=0; }
    }
    check(gb_fsctx_set_path(context,path));
    GB_UI_STATUS=0;
#include "../core/ui_picker.inc"
    copy_path(CPC_PICK_PATH,path);
    CPC_PICK_OWNER=CPC_UI_OWNER;
    gb_fsctx_close(context);
    CPC_PICK_STATUS=failed;
    if (failed) { UI_RES=0; GB_UI_STATUS=4; }
}
