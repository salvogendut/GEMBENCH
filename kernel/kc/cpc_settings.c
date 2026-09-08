/* Settings-only binding of the existing native API to caller-owned contexts.
 * No firmware, global browse cursor, low-RAM copy buffer or best-effort save.
 * This profile admits one M4 volume and the root/GBENCH paths Settings needs. */
#include "gb.h"
#include "gbfsctx.h"
#include "../../apps/settings/platform/cpc.h"

static gb_fsctx_t context;
static gb_fsctx_entry_t entry;
static unsigned char in_assets, io_status;
volatile unsigned char settings_storage_claim;
extern void cpc_config_update(void);

static unsigned char record(unsigned char status)
{
    if (status && !io_status) io_status=status;
    return status;
}
void settings_io_reset(void) { io_status=0; }
unsigned char settings_io_failed(void) { return io_status; }

static unsigned char copy_config(char *text, unsigned int *length)
{
    unsigned int i,n=KCFG_LEN;
    if (!text || !length || !n || n>512) return 0;
    for (i=0;i<n;i++) if (!KCFG_TEXT[i]) return 0;
    for (i=0;i<n;i++) text[i]=KCFG_TEXT[i];
    *length=n;
    return 1;
}
unsigned char settings_begin(char *text, unsigned int *length)
{
    if (context) return 0;
    io_status=0;settings_storage_claim=0;in_assets=0;
    context=gb_fsctx_open(0); /* native M4 volume 0 is presented as Disk C */
    if (!context) { record(gb_fsctx_status());return 0; }
    if (record(gb_fsctx_set_path(context,"/")) || !copy_config(text,length)) {
        settings_end();return 0;
    }
    return 1;
}
void settings_end(void)
{
    if (context) record(gb_fsctx_close(context));
    context=0;settings_storage_claim=0;
}
unsigned char gb_drives(void) { return GB_DRV_C; }
unsigned char gb_get_drive(void) { return GB_DRIVE_C; }
void gb_set_drive(unsigned char drive)
{
    if (drive!=GB_DRIVE_C) record(GB_FSCTX_ERR_UNSUPPORTED);
}
void gb_back(void)
{
    if (!context) { record(GB_FSCTX_ERR_CONTEXT);return; }
    if (!record(gb_fsctx_set_path(context,"/"))) in_assets=0;
}
static char *directory(unsigned char first)
{
    unsigned char found;
    if (!context) { record(GB_FSCTX_ERR_CONTEXT);return 0; }
    if (io_status) return 0;
    found=first ? gb_fsctx_dir_first(context,&entry) : gb_fsctx_dir_next(context,&entry);
    if (record(gb_fsctx_status()) || !found) return 0;
    return entry.name;
}
char *gb_dir1(void) { return directory(1); }
char *gb_dirn(void) { return directory(0); }
char *gb_entname(void) { return entry.name; }
unsigned char gb_isdir(void) { return (entry.attributes & GB_FSCTX_ATTR_DIRECTORY)!=0; }
void gb_chdir(void)
{
    static const char name[]="GBENCH     ";
    unsigned char i;
    if (!context || io_status) { record(GB_FSCTX_ERR_CONTEXT);return; }
    for (i=0;i<11 && entry.name[i]==name[i];i++) ;
    if (in_assets || !gb_isdir() || i!=11) { record(GB_FSCTX_ERR_UNSUPPORTED);return; }
    if (!record(gb_fsctx_set_path(context,"/GBENCH"))) in_assets=1;
}
void gb_set_name(const char *name)
{
    if (!context) { record(GB_FSCTX_ERR_CONTEXT);return; }
    if (!io_status) record(gb_fsctx_set_name(context,name));
}
unsigned int gb_fs_load(char *buffer,unsigned int size)
{
    unsigned int got;
    if (!context || !buffer || !size || size>512) {
        record(GB_FSCTX_ERR_BADARG);return 0;
    }
    if (io_status || record(gb_fsctx_rewind(context))) return 0;
    got=gb_fsctx_read(context,buffer,size);
    return record(gb_fsctx_status()) ? 0 : got;
}
unsigned char settings_commit(const char *key,const char *value,
                              char *text,unsigned int *length)
{
    unsigned char i;
    if (!context || !key || !value || !text || !length) return 0;
    for (i=0;i<16 && key[i];i++) ;
    if (i==16) return 0;
    for (i=0;i<16 && value[i];i++) ;
    if (i==16) return 0;
    for (i=0;key[i];i++) UI_NAME[i]=key[i];
    UI_NAME[i]=0;
    for (i=0;value[i];i++) UI_TEXT[i]=value[i];
    UI_TEXT[i]=0;UI_OP=CPC_EDIT_OP;
    cpc_config_update(); /* validates key/value, writes, verifies, reloads */
    if (UI_RES!=1) return 0;
    return copy_config(text,length);
}
