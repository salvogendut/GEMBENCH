/* Run the actual Settings C and widgets with host-owned state/device leaves.
 * This does not emulate CPC execution or qualify its native SDK providers. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define GB_PREEMPTIVE
#define GB_CPC_RESTART
#define GB_SETTINGS_PROVIDER "platform/unbound.h"
#define main settings_app_main
#include "../apps/settings/main.c"
#undef main

char settings_font_name[11], settings_icon_name[11];
char settings_cursor_name[11], settings_backdrop_name[11];
char settings_config_text[512], settings_backdrop_tile[64];
volatile unsigned int settings_config_length;
volatile unsigned char settings_backdrop_solid, settings_backdrop_drive;
volatile unsigned char settings_inks[5], settings_framepen;
volatile unsigned char settings_saver_op, settings_saver_result;
char settings_saver_text[GB_SSCFG_TEXT_CAP], settings_saver_modname[11];
char settings_copybuf[GB_COPYMAX];
volatile unsigned char settings_storage_claim;
volatile gb_msg_t settings_message;

static char disk[512], selected_name[11], labels[80][64];
static unsigned int disk_len, label_count, saves, reloads, back_calls;
static unsigned char selected_drive, last_pen, last_ink, draw_x, draw_y;
static const void *tile_source;

unsigned char gb_drives(void) { return GB_DRV_C; }
unsigned char gb_get_drive(void) { return selected_drive; }
void gb_set_drive(unsigned char drive) { selected_drive=drive; }
void gb_back(void) { back_calls++; }
char *gb_dir1(void) { return 0; }
char *gb_dirn(void) { return 0; }
unsigned char gb_isdir(void) { return 0; }
char *gb_entname(void) { return selected_name; }
void gb_chdir(void) { assert(0); }
void gb_set_name(const char *name) { memcpy(selected_name,name,11); }
unsigned int gb_fs_load(char *buf,unsigned int max)
{
    unsigned int n=disk_len<max?disk_len:max;
    memcpy(buf,disk,n);return n;
}
unsigned char gb_fs_save(char *buf,unsigned int len)
{
    assert(len<=sizeof(disk));memcpy(disk,buf,len);disk_len=len;saves++;return 1;
}
void gb_reload(void) { reloads++; }
void gb_titlebar_install(unsigned int size) { (void)size; }
void gb_gadgets_install(unsigned int size) { (void)size; }
void settings_set_ink(unsigned char pen,unsigned char ink) { last_pen=pen;last_ink=ink; }
unsigned char settings_run_saver(void) { return GB_SSCFG_CANCEL; }
unsigned char gb_wm_x(void) { return draw_x; }
unsigned char gb_wm_y(void) { return draw_y; }
unsigned char gb_wm_w(void) { return DEF_W; }
unsigned char gb_wm_h(void) { return DEF_H; }
void gb_textbw(unsigned char x,unsigned char y,const char *text)
{
    assert(x<GB_COLS && y+8<=GB_LINES);
    assert(label_count<80 && strlen(text)<sizeof(labels[0]));
    strcpy(labels[label_count++],text);
}
void gb_fill(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{
    assert(x+w<=GB_COLS && y+h<=GB_LINES && pen<4);
}
void gb_frame(unsigned char x,unsigned char y,unsigned char w,unsigned char h,unsigned char pen)
{
    gb_fill(x,y,w,h,pen);
}
void gb_restorerect(unsigned char x,unsigned char y,unsigned char w,unsigned char h,const void *buf)
{
    gb_fill(x,y,w,h,0);tile_source=buf;
}

static unsigned char has_label(const char *text)
{
    unsigned int i;
    for (i=0;i<label_count;i++) if (!strcmp(labels[i],text)) return 1;
    return 0;
}
static void load_text(const char *text)
{
    memset(cfgbuf,0,sizeof(cfgbuf));cfglen=(unsigned int)strlen(text);
    memcpy(cfgbuf,text,cfglen);
}

int main(void)
{
    unsigned char i;
    char text[16];
    assert(GB_COLS==80 && GB_LINES==200 && sizeof(rows)/sizeof(rows[0])==7);
    assert(rows[0].tfr==settings_font_name && rows[1].tfr==settings_icon_name);
    assert(rows[2].tfr==settings_cursor_name && rows[5].tfr==settings_backdrop_name);

    load_text("# preserved\r\nFONT=DEFAULT\r\nUNKNOWN=42\r\n");
    cfg_set("FONT=","CLASSIC");
    cfg_get("FONT=",text);assert(!strcmp(text,"CLASSIC"));
    assert(saves==1 && back_calls==4 && selected_drive==GB_DRIVE_C);
    assert(!memcmp(selected_name,"GEOBENCHCFG",11));
    assert(disk_len==cfglen && settings_config_length==cfglen);
    assert(!memcmp(disk,cfgbuf,cfglen) && !memcmp(settings_config_text,cfgbuf,cfglen));
    assert(!memcmp(cfgbuf,"# preserved\r\n",13));
    cfg_get("UNKNOWN=",text);assert(!strcmp(text,"42"));

    live_apply(0,"CLASSIC",GB_DRIVE_C);
    assert(!memcmp(settings_font_name,"CLASSIC FNT",11) && reloads==1);
    for (i=0;i<NPEN;i++) ink_cur[i]=i;
    apply_colour(0,7);assert(last_pen==0 && last_ink==7 && settings_inks[0]==7);
    apply_colour(4,12);assert(last_pen==4 && last_ink==12 && settings_inks[4]==12);
    apply_colour(2,7);assert(settings_framepen==1);
    apply_colour(1,7);assert(settings_framepen==3);

    load_text("FONT=CLASSIC\r\nICONS=REFINED\r\nCURSOR=DEFAULT\r\n"
              "TITLEBAR=WEAVE\r\nGADGETS=ORIGINAL\r\nBACKDROP=SOLID\r\n"
              "WALLPAPER=NONE\r\nSAVERTIME=5\r\n");
    draw_x=DEF_X;draw_y=DEF_Y;settings_backdrop_solid=1;
    picker_state=PICK_IDLE;label_count=0;s_draw();
    for (i=0;i<NROWS;i++) assert(has_label(rows[i].label));
    assert(has_label("CLASSIC") && has_label("REFINED") && has_label("WEAVE"));
    assert(has_label("Colours...") && has_label("Screensaver") && has_label("Configure"));
    assert(has_label("SQUARES") && has_label("5 min") && has_label("Return to Defaults..."));
    assert(!has_label("Video mode") && !has_label("Input device"));
    settings_backdrop_solid=0;label_count=0;s_draw();
    assert(tile_source==settings_backdrop_tile);

    picker_state=PICK_SCAN_FIRST;picker_row=ROW_TITLEBAR;picker_flags=0;
    label_count=0;s_draw();assert(has_label("Reading...") && !has_label("WEAVE"));
    picker_state=PICK_COLOURS;label_count=0;s_draw();
    assert(has_label("Desktop colours") && has_label("Border"));
    assert(has_label("Save") && has_label("Cancel") && !has_label("Screensaver"));
    puts("Actual Settings: relocated state, config, palette and shared widgets PASS");
    return 0;
}
