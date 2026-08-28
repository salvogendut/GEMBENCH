/* SNDTEST.APP - non-blocking app-linked audio diagnostic (#452). */
#include "gb.h"

#define DEF_X   ((GB_COLS - WIN_W) / 2)
#define DEF_Y   38
#define WIN_W   43
#define WIN_H   82
#define TITLE_H 14
#define BTN_W   11
#define BTN_H   14
#define BTN_GAP 2

#define STATE_IDLE  0
#define STATE_SCALE 1
#define STATE_NOISE 2

static unsigned char win_x = DEF_X, win_y = DEF_Y;
static unsigned char state, step, ticks;
static const unsigned char scale[8] = {
    GB_NOTE_C4,
    GB_SOUND_NOTE(GB_PITCH_D, 4),
    GB_SOUND_NOTE(GB_PITCH_E, 4),
    GB_SOUND_NOTE(GB_PITCH_F, 4),
    GB_SOUND_NOTE(GB_PITCH_G, 4),
    GB_SOUND_NOTE(GB_PITCH_A, 4),
    GB_SOUND_NOTE(GB_PITCH_B, 4),
    GB_NOTE_C5
};

static unsigned char button_x(unsigned char index)
{
    return (unsigned char)(win_x + 3 + index * (BTN_W + BTN_GAP));
}

static void draw_status(void)
{
    gb_fill((unsigned char)(win_x + 3), (unsigned char)(win_y + 30),
            36, 10, 1);
    if (state == STATE_SCALE)
        gb_textbw((unsigned char)(win_x + 4), (unsigned char)(win_y + 31),
                  "Playing scale");
    else if (state == STATE_NOISE)
        gb_textbw((unsigned char)(win_x + 4), (unsigned char)(win_y + 31),
                  "Playing noise");
    else
        gb_textbw((unsigned char)(win_x + 4), (unsigned char)(win_y + 31),
                  "Stopped");
}

static void draw_app(void)
{
    win_x = gb_wm_x();
    win_y = gb_wm_y();
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), WIN_W,
            (unsigned char)(WIN_H - TITLE_H), 1);
#ifdef GB_PCW
    if (gb_sound_caps() & GB_SOUND_CAP_PITCH)
        gb_textbw((unsigned char)(win_x + 3), (unsigned char)(win_y + 18),
                  "DKsound AY channel A");
    else
        gb_textbw((unsigned char)(win_x + 3), (unsigned char)(win_y + 18),
                  "PCW fixed beeper");
#else
    gb_textbw((unsigned char)(win_x + 3), (unsigned char)(win_y + 18),
              "PSG channel A");
#endif
    draw_status();
    gb_button(button_x(0), (unsigned char)(win_y + 48),
              BTN_W, BTN_H, "Scale", 0);
    gb_button(button_x(1), (unsigned char)(win_y + 48),
              BTN_W, BTN_H, "Noise", 0);
    gb_button(button_x(2), (unsigned char)(win_y + 48),
              BTN_W, BTN_H, "Stop", 0);
}

static void redraw_status(void)
{
    gb_curhide();
    draw_status();
    gb_curshow();
}

static void stop_sound(void)
{
    gb_sound_stop();
    state = STATE_IDLE;
    ticks = 0;
}

static void start_scale(void)
{
    state = STATE_SCALE;
    step = 0;
    ticks = 7;
    gb_sound_tone(scale[0], 12);
}

static void start_noise(void)
{
    state = STATE_NOISE;
    ticks = 30;
    gb_sound_noise(5, 11);
}

static void choose_action(unsigned char action)
{
    if (action == 0) start_scale();
    else if (action == 1) start_noise();
    else stop_sound();
    redraw_status();
}

static void app_click(void)
{
    unsigned char mx = gb_mx(), my = gb_my();
    if (gb_widget_hit(button_x(0), (unsigned char)(win_y + 48),
                      BTN_W, BTN_H, mx, my))
        choose_action(0);
    else if (gb_widget_hit(button_x(1), (unsigned char)(win_y + 48),
                           BTN_W, BTN_H, mx, my))
        choose_action(1);
    else if (gb_widget_hit(button_x(2), (unsigned char)(win_y + 48),
                           BTN_W, BTN_H, mx, my))
        choose_action(2);
}

static void app_frame(void)
{
    unsigned char key;
    while ((key = gb_getkey()) != 0) {
        if (key == 't' || key == 'T') choose_action(0);
        else if (key == 'n' || key == 'N') choose_action(1);
        else if (key == 's' || key == 'S') choose_action(2);
    }
    if (state == STATE_IDLE || !ticks || --ticks) return;
    if (state == STATE_NOISE) {
        stop_sound();
        redraw_status();
        return;
    }
    step++;
    if (step >= 8) {
        stop_sound();
        redraw_status();
        return;
    }
    gb_sound_tone(scale[step], 12);
    ticks = 7;
}

static void app_drag(void)
{
    win_x = gb_wm_x();
    win_y = gb_wm_y();
    if (gb_drag_window(&win_x, &win_y, WIN_W, WIN_H)) {
        gb_wm_setpos(win_x, win_y);
        gb_restore_parent();
    }
}

static void app_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  draw_app();  break;
        case GB_MSG_CLICK: app_click(); break;
        case GB_MSG_FRAME: app_frame(); break;
        case GB_MSG_CLOSE:
            stop_sound();
            gb_wm_close();
            break;
        case GB_MSG_DRAG:  app_drag(); break;
    }
}

static const gb_mwin_t app_window = {
    DEF_X, DEF_Y, WIN_W, WIN_H, 0, 0, app_proc, "Sound Test", 0
};

void main(void)
{
    unsigned char n;
    gb_sound_stop();
    gb_wm_managed(&app_window);
    for (n = 64; n; n--) if (!gb_getkey()) break;
    gb_restore_parent();
}
