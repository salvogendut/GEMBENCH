/* STARFLD.MOD - paged configuration companion for STARFLD.SAV. */
#include "gb.h"
#include "gbcfg.h"
#include "gbsaver.h"
#include "gbsavercfg.h"

#define DLG_W 42
#define DLG_H 78
#define STEP_W 16
#define STEP_H 10

static unsigned char dlg_x, dlg_y;
static unsigned char speed, stars;

static const gb_action_t actions[2] = {
    { "Save", 8 },
    { "Cancel", 11 }
};

static void u8_text(unsigned char value, char *text)
{
    unsigned char n = 0;
    if (value >= 100) {
        text[n++] = (char)('0' + value / 100);
        value %= 100;
        text[n++] = (char)('0' + value / 10);
    } else if (value >= 10) {
        text[n++] = (char)('0' + value / 10);
    }
    text[n++] = (char)('0' + value % 10);
    text[n] = 0;
}

static void draw_stepper(unsigned char y, unsigned char value)
{
    char text[4];
    u8_text(value, text);
    gb_stepper((unsigned char)(dlg_x + 16), y, STEP_W, STEP_H, text, 0);
}

static void draw_dialog(void)
{
    unsigned char speed_y = (unsigned char)(dlg_y + 22);
    unsigned char stars_y = (unsigned char)(dlg_y + 38);
    gb_window(dlg_x, dlg_y, DLG_W, DLG_H, "Starfield");
    gb_textbw((unsigned char)(dlg_x + 3), (unsigned char)(speed_y + 1), "Speed");
    draw_stepper(speed_y, speed);
    gb_textbw((unsigned char)(dlg_x + 3), (unsigned char)(stars_y + 1), "Stars");
    draw_stepper(stars_y, stars);
    gb_actions((unsigned char)(dlg_x + 3),
               (unsigned char)(dlg_y + DLG_H - 13),
               actions, 2, 2);
}

static void save_result(void)
{
    char *p = GB_SSCFG_TEXT;
    p = gb_sscfg_emit_u8(p, GB_STARFLD_SPEED_KEY, speed);
    p = gb_sscfg_emit_u8(p, GB_STARFLD_STARS_KEY, stars);
    *p = 0;
    GB_SSCFG_RESULT = GB_SSCFG_SAVE;
}

void main(void)
{
    unsigned char flags = 0, done = 0;
    speed = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                          GB_STARFLD_SPEED_KEY, GB_STARFLD_SPEED_DEFAULT,
                          GB_STARFLD_SPEED_MIN, GB_STARFLD_SPEED_MAX);
    stars = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                          GB_STARFLD_STARS_KEY, GB_STARFLD_STARS_DEFAULT,
                          GB_STARFLD_STARS_MIN, GB_STARFLD_STARS_MAX);
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
                              (unsigned char)(dlg_y + DLG_H - 13),
                              actions, 2, 2, mx, my);
        if (part != GB_ACTION_NONE) {
            if (part == 0) save_result();
            done = 1;
            continue;
        }

        part = gb_stepper_hit((unsigned char)(dlg_x + 16),
                              (unsigned char)(dlg_y + 22),
                              STEP_W, STEP_H, mx, my);
        if (part == GB_STEPPER_DEC && speed > GB_STARFLD_SPEED_MIN) {
            speed--;
            changed = 1;
        } else if (part == GB_STEPPER_INC && speed < GB_STARFLD_SPEED_MAX) {
            speed++;
            changed = 1;
        } else {
            part = gb_stepper_hit((unsigned char)(dlg_x + 16),
                                  (unsigned char)(dlg_y + 38),
                                  STEP_W, STEP_H, mx, my);
            if (part == GB_STEPPER_DEC && stars > GB_STARFLD_STARS_MIN) {
                stars = (unsigned char)(stars - GB_STARFLD_STARS_STEP);
                if (stars < GB_STARFLD_STARS_MIN)
                    stars = GB_STARFLD_STARS_MIN;
                changed = 1;
            } else if (part == GB_STEPPER_INC &&
                       stars <= GB_STARFLD_STARS_MAX - GB_STARFLD_STARS_STEP) {
                stars = (unsigned char)(stars + GB_STARFLD_STARS_STEP);
                changed = 1;
            }
        }
        if (changed) {
            gb_curhide();
            draw_dialog();
            gb_curshow();
        }
    }
    if (flags & GB_QUIT) while (gb_poll() & GB_QUIT) ;
}
