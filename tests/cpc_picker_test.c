/* Actual shared chooser plus CPC native binding; only UI/device calls mocked. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_FSCTX_PLATFORM_HEADER "../../tests/fixtures/fsctx_client_provider.h"
#include "gbfsctx.h"
static unsigned char request[256], ui_status, pick_status, fs_status;
static char last_path[48], device_path[48];
static unsigned int last_owner, caller_owner;
static unsigned int opens, closes, enumerations, popups, active, cursor;
static unsigned int fail_enumeration, fail_activate, full;
#define GB_UI_PROVIDER "../../tests/cpc_picker_provider.h"
#define main picker_main
#include "../kernel/kc/cpc_picker_mod.c"
#undef main
#define GB_PICK_STATUS cpc_picker_error
#include "../lib/gb/gbpick.c"

struct row { const char *parent, *name; unsigned char directory; };
static const struct row rows[]={
    {"/","DIR        ",1},{"/","EMPTY      ",1},{"/","ROOT    TXT",0},
    {"/DIR","SUB        ",1},{"/DIR","NOTE    TXT",0},{"/DIR","IGNORE  BIN",0},
    {"/DIR/SUB","HELLO   TXT",0}
};
struct step { unsigned char choice,n; const char *labels[14]; };
static const struct step *script;
static unsigned int nsteps;

gb_fsctx_t gb_fsctx_open(unsigned char drive)
{ assert(!drive && !active);opens++;fs_status=full?GB_FSCTX_ERR_FULL:0;
  if(full)return 0;
  active=1;strcpy(device_path,"/");return 0x201; }
unsigned char gb_fsctx_close(gb_fsctx_t h)
{ assert(h==0x201 && active);active=0;closes++;fs_status=0;return 0; }
unsigned char gb_fsctx_set_path(gb_fsctx_t h,const char *p)
{ assert(h==0x201 && active && strlen(p)<48);strcpy(device_path,p);return fs_status=0; }
unsigned char gb_fsctx_activate(gb_fsctx_t h)
{ assert(h==0x201 && active);return fs_status=fail_activate?GB_FSCTX_ERR_IO:0; }
unsigned char gb_fsctx_status(void) { return fs_status; }
unsigned char gb_fsctx_dir_next(gb_fsctx_t h,gb_fsctx_entry_t *out)
{
    assert(h==0x201 && active);fs_status=0;
    if (fail_enumeration && enumerations==fail_enumeration) { fs_status=GB_FSCTX_ERR_IO;return 0; }
    if (strlen(device_path)==47) {
        if(cursor++)return 0;
        memcpy(out->name,"DIR        ",11);out->attributes=GB_FSCTX_ATTR_DIRECTORY;return 1;
    }
    if (!strcmp(device_path,"/MANY")) {
        char name[12];
        if(cursor==15)return 0;
        snprintf(name,sizeof(name),"F%07uTXT",cursor++);
        memcpy(out->name,name,11);out->attributes=0;out->size=7;return 1;
    }
    while(cursor<sizeof(rows)/sizeof(rows[0])) {
        const struct row *r=rows+cursor++;
        if (strcmp(r->parent,device_path)) continue;
        memcpy(out->name,r->name,11);out->attributes=r->directory?GB_FSCTX_ATTR_DIRECTORY:0;
        out->size=7;return 1;
    }
    return 0;
}
unsigned char gb_fsctx_dir_first(gb_fsctx_t h,gb_fsctx_entry_t *out)
{ cursor=0;enumerations++;return gb_fsctx_dir_next(h,out); }
unsigned char gb_popup(unsigned char x,unsigned char y,const char *const *labels,unsigned char n)
{
    const struct step *s;
    assert(active && x==10 && y==8 && popups<nsteps);s=script+popups++;
    assert(n==s->n);
    for(unsigned int i=0;i<n;i++) assert(!strcmp(labels[i],s->labels[i]));
    return s->choice;
}
static void reset(unsigned char op,const struct step *steps,unsigned int count)
{
    assert(!active);memset(request,0,sizeof(request));UI_OP=op;memcpy(UI_TEXT,"TXT\0",5);
    last_owner=caller_owner=0x107;strcpy(last_path,"/");
    opens=closes=enumerations=popups=fail_enumeration=fail_activate=full=0;
    ui_status=pick_status=fs_status=99;script=steps;nsteps=count;
}
static void finished(unsigned char accepted)
{ picker_main();assert(UI_RES==accepted && !ui_status && !pick_status && !active);
  assert(opens==1 && closes==1 && popups==nsteps && last_owner==caller_owner); }
int main(void)
{
    (void)GB_FSCTX_REQUEST; /* storage provider is explicit; wrappers are mocked */
    const struct step open[]={
        {1,4,{"..","DIR/","EMPTY/","ROOT.TXT"}},
        {1,3,{"..","SUB/","NOTE.TXT"}},
        {1,2,{"..","HELLO.TXT"}}
    };
    reset(3,open,3);finished(1);
    assert(!strcmp(last_path,"/DIR/SUB") && !memcmp(UI_NAME,"HELLO   TXT",11));
    const struct step dest[]={
        {2,3,{"..","[Save here]","HELLO.TXT"}}, /* file is not a destination */
        {0,3,{"..","[Save here]","HELLO.TXT"}},
        {1,4,{"..","[Save here]","SUB/","NOTE.TXT"}}
    };
    reset(4,dest,3);strcpy(last_path,"/DIR/SUB");finished(1);assert(!strcmp(last_path,"/DIR"));
    const struct step empty[]={
        {2,4,{"..","DIR/","EMPTY/","ROOT.TXT"}},
        {0,1,{".."}},
        {255,4,{"..","DIR/","EMPTY/","ROOT.TXT"}}
    };
    reset(3,empty,3);finished(0);assert(!strcmp(last_path,"/"));
    const struct step root[]={{255,4,{"..","DIR/","EMPTY/","ROOT.TXT"}}};
    reset(3,root,1);strcpy(last_path,"/DIR/SUB");finished(0); /* Open starts at root */
    const struct step rootdest[]={{1,5,{"..","[Save here]","DIR/","EMPTY/","ROOT.TXT"}}};
    reset(4,rootdest,1);strcpy(last_path,"/DIR/SUB");last_owner++;finished(1);
    assert(!strcmp(last_path,"/")); /* no other owner's implicit path */
    reset(4,rootdest,1);memset(last_path,'X',sizeof(last_path));finished(1);
    reset(4,rootdest,1);strcpy(last_path,"bad");finished(1);
    const struct step folders[]={{255,3,{"..","DIR/","EMPTY/"}}};
    reset(3,folders,1);UI_TEXT[0]=0;finished(0); /* retained native empty-list semantics */
    const struct step both[]={{255,5,{"..","[Save here]","SUB/","NOTE.TXT","IGNORE.BIN"}}};
    reset(4,both,1);strcpy(last_path,"/DIR");memcpy(UI_TEXT,"TXT\0BIN\0",9);finished(0);
    reset(4,both,1); /* Direct shared API supports NULL = all; native transport does not. */
    context=gb_fsctx_open(0);strcpy(path,"/DIR");gb_fsctx_set_path(context,path);
    failed=0;assert(!gb_pickdir(0));gb_fsctx_close(context);
    const struct step capped[]={{255,14,{"..","[Save here]",
        "F0000000.TXT","F0000001.TXT","F0000002.TXT","F0000003.TXT",
        "F0000004.TXT","F0000005.TXT","F0000006.TXT","F0000007.TXT",
        "F0000008.TXT","F0000009.TXT","F0000010.TXT","F0000011.TXT"}}};
    reset(4,capped,1);strcpy(last_path,"/MANY");finished(0); /* unchanged 12-entry cap */
    for(unsigned int i=0;i<8;i++) {
        reset(3,0,0);
        if(i==0)UI_OP=2;
        if(i==1)memset(UI_TEXT,'X',232);
        if(i==2)strcpy(UI_TEXT,"TOOLONG");
        if(i==3)strcpy(UI_TEXT,"txT");
        if(i==4)strcpy(UI_TEXT,"T/T");
        if(i==5) { for(unsigned int j=0;j<8;j++)memcpy(UI_TEXT+j*4,"TXT",4); }
        if(i==6)strcpy(UI_TEXT,"TX");
        if(i==7)strcpy(UI_TEXT,"TXT.");
        picker_main();assert(!UI_RES && ui_status==2 && !opens && !popups && !active);
    }
    reset(3,0,0);full=1;picker_main();
    assert(!UI_RES && ui_status==4 && pick_status==GB_FSCTX_ERR_FULL && !active && !closes);
    reset(3,0,0);fail_enumeration=1;picker_main();
    assert(!UI_RES && ui_status==4 && pick_status==GB_FSCTX_ERR_IO && closes==1 && !active && !popups);
    reset(3,open,1);fail_enumeration=2;picker_main(); /* replay fails before chdir */
    assert(!UI_RES && ui_status==4 && pick_status==GB_FSCTX_ERR_IO && closes==1 && !active && popups==1);
    reset(3,open,1);fail_activate=1;picker_main();
    assert(!UI_RES && ui_status==4 && pick_status==GB_FSCTX_ERR_IO && closes==1 && !active);
    assert(!strcmp(last_path,"/")); /* failed CD cannot publish a partial path */
    const struct step depth[]={{2,3,{"..","[Save here]","DIR/"}}};
    const char *longpath="/AAAAAAA/BBBBBBB/CCCCCCC/DDDDDDD/EEEEEEE/FFFFFF";
    assert(strlen(longpath)==47);
    reset(4,depth,1);strcpy(last_path,longpath);picker_main();
    assert(!UI_RES && ui_status==4 && pick_status==GB_FSCTX_ERR_BADARG && closes==1 && !active);
    assert(!strcmp(last_path,longpath)); /* appending another component exceeds 48 bytes */
    puts("native picker: shared navigation, filtering, owner handoff, bounds and cleanup PASS");
    return 0;
}
