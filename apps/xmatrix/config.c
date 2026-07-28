/* XMATRIX.MOD - paged configuration companion for XMATRIX.SAV. */
#include "gb.h"
#include "gbcfg.h"
#include "gbsaver.h"
#include "gbsavercfg.h"

#define DLG_W 42
#define DLG_H2 78
#define DLG_H3 94
#define STEP_W 16
#define STEP_H 10

#ifdef GB_MSX2
#define MSX_SCRMOD (*(volatile unsigned char *)0xFCAF)
#define FS_SAVE_LEN_K (*(volatile unsigned int *)0x14FD)
#define COLOR_DEFAULT GB_XMATRIX_MSX_COLOR_DEFAULT
#define COLOR_MIN     GB_XMATRIX_MSX_COLOR_MIN
#define COLOR_MAX     GB_XMATRIX_MSX_COLOR_MAX
#elif !defined(GB_PCW)
#define COLOR_DEFAULT GB_XMATRIX_CPC_COLOR_DEFAULT
#define COLOR_MIN     GB_XMATRIX_CPC_COLOR_MIN
#define COLOR_MAX     GB_XMATRIX_CPC_COLOR_MAX
#endif

static unsigned char dlg_x, dlg_y, dlg_h;
static unsigned char glyphs, speed;
#ifndef GB_PCW
static unsigned char color;
#endif
#ifdef GB_MSX2
static unsigned char swatch[32];
#endif

static const gb_action_t actions[2] = {
    { "Save", 8 },
    { "Cancel", 11 }
};

static void u8_text(unsigned char value, char *text)
{
    unsigned char n = 0;
    if (value >= 10) text[n++] = (char)('0' + value / 10);
    text[n++] = (char)('0' + value % 10);
    text[n] = 0;
}

static const char *speed_name(void)
{
    if (speed == 1) return "Slow";
    if (speed == 3) return "Fast";
    return "Normal";
}

#ifdef GB_MSX2
static void draw_swatch(unsigned char y)
{
    unsigned char i;
    unsigned char packed = (unsigned char)((color << 4) | color);
    for (i = 0; i < sizeof(swatch); i++) swatch[i] = packed;
    gb_pic_edit_buf = (unsigned int)swatch;
    gb_pic_edit_off = (unsigned int)(dlg_x + 34) | ((unsigned int)y << 8);
    FS_SAVE_LEN_K = 2 | ((unsigned int)8 << 8);
    (void)gb_pic_edit(GB_PICEDIT_NATIVE16);
    gb_frame((unsigned char)(dlg_x + 34), y, 2, 8, 2);
}
#endif

static void draw_dialog(void)
{
    unsigned char glyph_y = (unsigned char)(dlg_y + 22);
    unsigned char speed_y = (unsigned char)(dlg_y + 38);
    gb_window(dlg_x, dlg_y, DLG_W, dlg_h, "XMatrix");
    gb_textbw((unsigned char)(dlg_x + 3), (unsigned char)(glyph_y + 1), "Glyphs");
    gb_stepper((unsigned char)(dlg_x + 16), glyph_y, STEP_W, STEP_H,
               glyphs ? "Kana" : "Binary", 0);
    gb_textbw((unsigned char)(dlg_x + 3), (unsigned char)(speed_y + 1), "Speed");
    gb_stepper((unsigned char)(dlg_x + 16), speed_y, STEP_W, STEP_H,
               speed_name(), 0);
#ifndef GB_PCW
    if (dlg_h == DLG_H3) {
        char text[4];
        unsigned char color_y = (unsigned char)(dlg_y + 54);
        u8_text(color, text);
        gb_textbw((unsigned char)(dlg_x + 3),
                  (unsigned char)(color_y + 1), "Color");
        gb_stepper((unsigned char)(dlg_x + 16), color_y,
                   STEP_W, STEP_H, text, 0);
#ifdef GB_MSX2
        draw_swatch((unsigned char)(color_y + 1));
#endif
    }
#endif
    gb_actions((unsigned char)(dlg_x + 3),
               (unsigned char)(dlg_y + dlg_h - 13),
               actions, 2, 2);
}

static void save_result(void)
{
    char *p = GB_SSCFG_TEXT;
    p = gb_sscfg_emit_u8(p, GB_XMATRIX_GLYPHS_KEY, glyphs);
    p = gb_sscfg_emit_u8(p, GB_XMATRIX_SPEED_KEY, speed);
#ifndef GB_PCW
    if (dlg_h == DLG_H3)
        p = gb_sscfg_emit_u8(p, GB_XMATRIX_COLOR_KEY, color);
#endif
    *p = 0;
    GB_SSCFG_RESULT = GB_SSCFG_SAVE;
}

void main(void)
{
    unsigned char flags = 0, done = 0;
    glyphs = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                           GB_XMATRIX_GLYPHS_KEY,
                           GB_XMATRIX_GLYPHS_DEFAULT,
                           GB_XMATRIX_GLYPHS_MIN,
                           GB_XMATRIX_GLYPHS_MAX);
    speed = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                          GB_XMATRIX_SPEED_KEY, GB_XMATRIX_SPEED_DEFAULT,
                          GB_XMATRIX_SPEED_MIN, GB_XMATRIX_SPEED_MAX);
    dlg_h = DLG_H2;
#ifdef GB_MSX2
    color = COLOR_DEFAULT;
    if (MSX_SCRMOD == 7) {
        dlg_h = DLG_H3;
        color = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                              GB_XMATRIX_COLOR_KEY, COLOR_DEFAULT,
                              COLOR_MIN, COLOR_MAX);
    }
#elif !defined(GB_PCW)
    dlg_h = DLG_H3;
    color = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                          GB_XMATRIX_COLOR_KEY, COLOR_DEFAULT,
                          COLOR_MIN, COLOR_MAX);
#endif
    dlg_x = (unsigned char)(gb_wm_x() + (gb_wm_w() - DLG_W) / 2);
    dlg_y = (unsigned char)(gb_wm_y() + 37);
    GB_SSCFG_RESULT = GB_SSCFG_CANCEL;
    gb_curhide();
    draw_dialog();
    gb_curshow();

    while (!done) {
        unsigned char mx, my, part, changed = 0;
        flags = gb_poll();
        if (flags & GB_QUIT) break;
        if (!(flags & GB_CLICK)) continue;
        mx = gb_mx();
        my = gb_my();
        if (my >= dlg_y + 2 && my < dlg_y + 12 &&
            mx >= dlg_x + 1 && mx < dlg_x + 3)
            break;

        part = gb_actions_hit((unsigned char)(dlg_x + 3),
                              (unsigned char)(dlg_y + dlg_h - 13),
                              actions, 2, 2, mx, my);
        if (part != GB_ACTION_NONE) {
            if (part == 0) save_result();
            done = 1;
            continue;
        }

        part = gb_stepper_hit((unsigned char)(dlg_x + 16),
                              (unsigned char)(dlg_y + 22),
                              STEP_W, STEP_H, mx, my);
        if (part == GB_STEPPER_DEC || part == GB_STEPPER_INC) {
            glyphs = (unsigned char)!glyphs;
            changed = 1;
        } else {
            part = gb_stepper_hit((unsigned char)(dlg_x + 16),
                                  (unsigned char)(dlg_y + 38),
                                  STEP_W, STEP_H, mx, my);
            if (part == GB_STEPPER_DEC && speed > GB_XMATRIX_SPEED_MIN) {
                speed--;
                changed = 1;
            } else if (part == GB_STEPPER_INC &&
                       speed < GB_XMATRIX_SPEED_MAX) {
                speed++;
                changed = 1;
            }
#ifndef GB_PCW
            else if (dlg_h == DLG_H3) {
                part = gb_stepper_hit((unsigned char)(dlg_x + 16),
                                      (unsigned char)(dlg_y + 54),
                                      STEP_W, STEP_H, mx, my);
                if (part == GB_STEPPER_DEC && color > COLOR_MIN) {
                    color--;
                    changed = 1;
                } else if (part == GB_STEPPER_INC && color < COLOR_MAX) {
                    color++;
                    changed = 1;
                }
            }
#endif
        }
        if (changed) {
            gb_curhide();
            draw_dialog();
            gb_curshow();
        }
    }
    if (flags & GB_QUIT) while (gb_poll() & GB_QUIT) ;
}
