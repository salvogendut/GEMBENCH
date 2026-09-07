/* Actual Settings edit + native CPC persistence module, mocked device only. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_FSCTX_PLATFORM_HEADER "../../tests/fixtures/fsctx_client_provider.h"
#include "gbfsctx.h"
static unsigned char request[256],ui_status,edit_status,edit_changed,edit_error;
static unsigned char fs_status,active,missing,full,fail_write,fail_verify;
static unsigned int opens,closes,writes,reads,fail_read,disklen,offset;
static char disk[1024];
#define GB_UI_PROVIDER "../../tests/config_edit_provider.h"
#define main config_edit_main
#include "../kernel/kc/cpc_config_edit.c"
#undef main

gb_fsctx_t gb_fsctx_open(unsigned char drive)
{ assert(!drive && !active);opens++;fs_status=full?GB_FSCTX_ERR_FULL:0;
  if(full)return 0;
  active=1;offset=0;return 0x201; }
unsigned char gb_fsctx_close(gb_fsctx_t h)
{ assert(h==0x201 && active);active=0;closes++;return fs_status=0; }
unsigned char gb_fsctx_set_path(gb_fsctx_t h,const char *p)
{ assert(h==0x201 && active && !strcmp(p,"/"));return fs_status=0; }
unsigned char gb_fsctx_set_name(gb_fsctx_t h,const char *p)
{ assert(h==0x201 && active && !memcmp(p,"GEOBENCHCFG",11));return fs_status=0; }
unsigned char gb_fsctx_status(void) { return fs_status; }
unsigned char gb_fsctx_rewind(gb_fsctx_t h)
{ assert(h==0x201 && active);offset=0;return fs_status=0; }
unsigned int gb_fsctx_read(gb_fsctx_t h,char *p,unsigned int n)
{
    unsigned int got;
    assert(h==0x201 && active);reads++;fs_status=0;
    if(missing || reads==fail_read) { fs_status=GB_FSCTX_ERR_IO;return 0; }
    got=disklen-offset;if(got>n)got=n;
    memcpy(p,disk+offset,got);offset+=got;
    if(fail_verify && writes && got)p[0]^=1;
    return got;
}
unsigned char gb_fsctx_write(gb_fsctx_t h,const char *p,unsigned int n)
{
    assert(h==0x201 && active && !offset && n<=512);writes++;
    disklen=fail_write?1:n;memcpy(disk,p,disklen);offset=disklen;
    return fs_status=fail_write?GB_FSCTX_ERR_IO:0;
}
static void reset(const char *text,const char *key,const char *value)
{
    assert(!active);memset(request,0,sizeof(request));memset(disk,0,sizeof(disk));
    disklen=(unsigned int)strlen(text);memcpy(disk,text,disklen);
    UI_OP=CPC_EDIT_OP;strcpy(UI_NAME,key);strcpy(UI_TEXT,value);
    ui_status=edit_status=edit_changed=edit_error=99;
    opens=closes=writes=reads=fail_read=missing=full=fail_write=fail_verify=0;
}
static void accepted(const char *expected,unsigned int n,unsigned char changed)
{
    config_edit_main();
    assert(UI_RES==1 && !ui_status && !edit_status && !edit_error && edit_changed==changed);
    assert(!active && opens==1 && closes==1 && writes==changed);
    assert(disklen==n && !memcmp(disk,expected,n));
}
static void rejected(unsigned char phase)
{
    char before[1024];unsigned int n=disklen;
    memcpy(before,disk,n);config_edit_main();
    assert(!UI_RES && ui_status && edit_status==phase && !active && !edit_changed);
    assert(closes==(opens && !full));
    if(phase!=5 && phase!=6)assert(!writes && disklen==n && !memcmp(before,disk,n));
}
int main(void)
{
    (void)GB_FSCTX_REQUEST;
    const char *base="# keep\r\nTITLEBAR=ORIGINAL\r\nUNKNOWN=42\r\n";
    const char *changed="# keep\r\nTITLEBAR=WEAVE\r\nUNKNOWN=42\r\n";
    reset(base,"TITLEBAR=","WEAVE");accepted(changed,(unsigned int)strlen(changed),1);
    reset(changed,"TITLEBAR=","ORIGINAL");accepted(base,(unsigned int)strlen(base),1);
    reset(changed,"TITLEBAR=","WEAVE");accepted(changed,(unsigned int)strlen(changed),0);
    reset("TITLEBAR=ORIGINAL\nTITLEBAR=SOLID\n","TITLEBAR=","WEAVE");
    accepted("TITLEBAR=WEAVE\nTITLEBAR=SOLID\n",30,1);
    reset("# TITLEBAR=UNCHANGED\nX=1\n","TITLEBAR=","WEAVE");
    const char *appended="# TITLEBAR=UNCHANGED\nX=1\nTITLEBAR=WEAVE\r\n";
    accepted(appended,(unsigned int)strlen(appended),1);
    reset("TITLEBAR=ORIGINAL","TITLEBAR=","WEAVE");accepted("TITLEBAR=WEAVE",14,1);
    reset("X=1","TITLEBAR=","WEAVE");rejected(4); /* don't append onto another value */
    const char *keys[]={"FONT=","ICONS=","CURSOR=","TITLEBAR=","GADGETS=","BACKDROP="};
    const char *values[]={"DEFAULT.FNT","REFINED.IST","DEFAULT.SPR","WEAVE.TBR","IMPROVED.GDT","WAVES.BDP"};
    for(unsigned int i=0;i<6;i++) {
        char expected[64];snprintf(expected,sizeof(expected),"X=1\r\n%s%s\r\n",keys[i],values[i]);
        reset("X=1\r\n",keys[i],values[i]);accepted(expected,(unsigned int)strlen(expected),1);
    }
    const char *view_base="# VIEW=LIST\r\nVIEW=DEFAULT\r\nUNKNOWN=42\r\n";
    const char *view_list="# VIEW=LIST\r\nVIEW=LIST\r\nUNKNOWN=42\r\n";
    reset(view_base,"VIEW=","LIST");accepted(view_list,(unsigned int)strlen(view_list),1);
    reset(view_list,"VIEW=","DEFAULT");accepted(view_base,(unsigned int)strlen(view_base),1);
    reset(view_list,"VIEW=","LIST");accepted(view_list,(unsigned int)strlen(view_list),0);
    reset("X=1\r\n","VIEW=","LIST");accepted("X=1\r\nVIEW=LIST\r\n",16,1);
    const char *bad_view[]={"","list","ICONS","DEFAULT.FNT","LIST\r\nX=1","LISTX"};
    for(unsigned int i=0;i<sizeof(bad_view)/sizeof(bad_view[0]);i++) {
        reset(view_base,"VIEW=",bad_view[i]);rejected(2);assert(!opens);
    }
    reset(view_list,"VIEW=","DEFAULT");fail_write=1;rejected(5);
    reset(view_list,"VIEW=","DEFAULT");fail_verify=1;rejected(6);
    const char *bad[]={"","../WEAVE","C:WEAVE","ABCDEFGHI","weave","WEAVE.GDT","WEAVE.TBR.X","WEAVE\r\nX"};
    for(unsigned int i=0;i<sizeof(bad)/sizeof(bad[0]);i++) {
        reset(base,"TITLEBAR=",bad[i]);rejected(2);assert(!opens);
    }
    reset(base,"OTHER=","WEAVE");rejected(2);assert(!opens);
    reset(base,"TITLEBAR=","WEAVE");memset(UI_NAME,'X',16);rejected(2);assert(!opens);
    reset(base,"TITLEBAR=","WEAVE");UI_OP=3;rejected(2);assert(!opens);
    reset("","TITLEBAR=","WEAVE");rejected(3);
    reset(base,"TITLEBAR=","WEAVE");missing=1;rejected(3);assert(edit_error==GB_FSCTX_ERR_IO);
    reset(base,"TITLEBAR=","WEAVE");full=1;rejected(7);assert(edit_error==GB_FSCTX_ERR_FULL);
    reset(base,"TITLEBAR=","WEAVE");disk[1]=0;rejected(3);
    reset(base,"TITLEBAR=","WEAVE");fail_read=1;rejected(3);assert(edit_error==GB_FSCTX_ERR_IO);
    reset(base,"TITLEBAR=","WEAVE");fail_write=1;rejected(5);
    reset(base,"TITLEBAR=","WEAVE");fail_verify=1;rejected(6);
    reset(base,"TITLEBAR=","WEAVE");fail_read=2;rejected(6);assert(edit_error==GB_FSCTX_ERR_IO);
    reset(base,"TITLEBAR=","WEAVE");fail_read=3;rejected(6);assert(edit_error==GB_FSCTX_ERR_IO); /* EOF verification */
    reset("TITLEBAR=ORIGINAL\r\n","TITLEBAR=","WEAVE");
    memset(disk+disklen,'#',512-disklen);disklen=512;
    char expected[512];memcpy(expected,"TITLEBAR=WEAVE\r\n",16);memset(expected+16,'#',493);
    accepted(expected,509,1);
    reset("TITLEBAR=X\r\n","TITLEBAR=","ORIGINAL");
    memset(disk+disklen,'#',512-disklen);disklen=512;rejected(4);
    reset(base,"TITLEBAR=","WEAVE");memset(disk+disklen,'#',513-disklen);disklen=513;rejected(3);
    reset("TITLEBAR=","TITLEBAR=","WEAVE");memset(disk+disklen,'X',300);disklen+=300;rejected(4);
    puts("Settings edit/CPC persistence: preservation, bounds, no-op, write/readback errors and cleanup PASS");
    return 0;
}
