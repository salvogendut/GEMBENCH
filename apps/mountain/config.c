/* MOUNTAIN.MOD - paged configuration companion for MOUNTAIN.SAV. */
#include "gb.h"
#include "gbcfg.h"
#include "gbsaver.h"
#include "gbsavercfg.h"

#define DLG_W 44
#define DLG_H 94
#define STEP_W 18
#define STEP_H 10

static unsigned char dlg_x, dlg_y;
static unsigned char speed, peaks, hold;

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

static const char *speed_name(void)
{
    if (speed == 1) return "Slow";
    if (speed == 3) return "Fast";
    return "Normal";
}

static void draw_number(unsigned char y, unsigned char value)
{
    char text[4];
    u8_text(value, text);
    gb_stepper((unsigned char)(dlg_x + 18), y,
               STEP_W, STEP_H, text, 0);
}

static void draw_dialog(void)
{
    unsigned char speed_y = (unsigned char)(dlg_y + 22);
    unsigned char peaks_y = (unsigned char)(dlg_y + 38);
    unsigned char hold_y = (unsigned char)(dlg_y + 54);
    gb_window(dlg_x, dlg_y, DLG_W, DLG_H, "Mountain");
    gb_textbw((unsigned char)(dlg_x + 3),
              (unsigned char)(speed_y + 1), "Speed");
    gb_stepper((unsigned char)(dlg_x + 18), speed_y,
               STEP_W, STEP_H, speed_name(), 0);
    gb_textbw((unsigned char)(dlg_x + 3),
              (unsigned char)(peaks_y + 1), "Peaks");
    draw_number(peaks_y, peaks);
    gb_textbw((unsigned char)(dlg_x + 3),
              (unsigned char)(hold_y + 1), "Hold");
    draw_number(hold_y, hold);
    gb_actions((unsigned char)(dlg_x + 3),
               (unsigned char)(dlg_y + DLG_H - 13),
               actions, 2, 2);
}

static void save_result(void)
{
    char *p = GB_SSCFG_TEXT;
    p = gb_sscfg_emit_u8(p, GB_MOUNTAIN_SPEED_KEY, speed);
    p = gb_sscfg_emit_u8(p, GB_MOUNTAIN_PEAKS_KEY, peaks);
    p = gb_sscfg_emit_u8(p, GB_MOUNTAIN_HOLD_KEY, hold);
    *p = 0;
    GB_SSCFG_RESULT = GB_SSCFG_SAVE;
}

void main(void)
{
    unsigned char flags = 0, done = 0;
    speed = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                          GB_MOUNTAIN_SPEED_KEY,
                          GB_MOUNTAIN_SPEED_DEFAULT,
                          GB_MOUNTAIN_SPEED_MIN,
                          GB_MOUNTAIN_SPEED_MAX);
    peaks = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                          GB_MOUNTAIN_PEAKS_KEY,
                          GB_MOUNTAIN_PEAKS_DEFAULT,
                          GB_MOUNTAIN_PEAKS_MIN,
                          GB_MOUNTAIN_PEAKS_MAX);
    hold = gbcfg_u8_from(GB_SSCFG_CONFIG, GB_SSCFG_CFGLEN,
                         GB_MOUNTAIN_HOLD_KEY,
                         GB_MOUNTAIN_HOLD_DEFAULT,
                         GB_MOUNTAIN_HOLD_MIN,
                         GB_MOUNTAIN_HOLD_MAX);
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

        part = gb_stepper_hit((unsigned char)(dlg_x + 18),
                              (unsigned char)(dlg_y + 22),
                              STEP_W, STEP_H, mx, my);
        if (part == GB_STEPPER_DEC && speed > GB_MOUNTAIN_SPEED_MIN) {
            speed--;
            changed = 1;
        } else if (part == GB_STEPPER_INC &&
                   speed < GB_MOUNTAIN_SPEED_MAX) {
            speed++;
            changed = 1;
        } else {
            part = gb_stepper_hit((unsigned char)(dlg_x + 18),
                                  (unsigned char)(dlg_y + 38),
                                  STEP_W, STEP_H, mx, my);
            if (part == GB_STEPPER_DEC && peaks > GB_MOUNTAIN_PEAKS_MIN) {
                peaks--;
                changed = 1;
            } else if (part == GB_STEPPER_INC &&
                       peaks < GB_MOUNTAIN_PEAKS_MAX) {
                peaks++;
                changed = 1;
            } else {
                part = gb_stepper_hit((unsigned char)(dlg_x + 18),
                                      (unsigned char)(dlg_y + 54),
                                      STEP_W, STEP_H, mx, my);
                if (part == GB_STEPPER_DEC &&
                    hold > GB_MOUNTAIN_HOLD_MIN) {
                    hold = hold <= GB_MOUNTAIN_HOLD_MIN +
                                   GB_MOUNTAIN_HOLD_STEP
                         ? GB_MOUNTAIN_HOLD_MIN
                         : (unsigned char)(hold - GB_MOUNTAIN_HOLD_STEP);
                    changed = 1;
                } else if (part == GB_STEPPER_INC &&
                           hold < GB_MOUNTAIN_HOLD_MAX) {
                    hold = hold >= GB_MOUNTAIN_HOLD_MAX -
                                   GB_MOUNTAIN_HOLD_STEP
                         ? GB_MOUNTAIN_HOLD_MAX
                         : (unsigned char)(hold + GB_MOUNTAIN_HOLD_STEP);
                    changed = 1;
                }
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
