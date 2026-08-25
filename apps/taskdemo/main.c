/* TASKDEMO.APP - non-yielding preemption diagnostic (#477).
 *
 * This app is deliberately not staged in release distributions. Its worker
 * never returns or calls a kernel API, so a responsive desktop proves that the
 * platform timer has preempted app code. Build only with TASK=1 and a kernel
 * configured with PREEMPTIVE_CONTEXT=1.
 */
#include "gb.h"

#define WIN_Y 44
#define WIN_W 37
#define WIN_H 82

#define SCHED_RUNNABLE (*(volatile unsigned char *)0x1344)
#define SCHED_STACK_MAX (*(volatile unsigned char *)0x1346)
#define SCHED_FAULT (*(volatile unsigned char *)0x1347)

static volatile unsigned int spins;
static unsigned char task_id;
static unsigned char win_x;

static const unsigned char menu_def[] = {
    1,
    10, 'S','t','o','p',0,0,0,0
};

static char hex_digit(unsigned char value)
{
    value &= 15;
    return (char)(value < 10 ? '0' + value : 'A' + value - 10);
}

static void worker(void)
{
    for (;;) spins++;
}

static void repaint(void)
{
    unsigned int sample = spins;
    char count[5];
    char status[19] = "Tasks: 0 Stack: 00";
    char fault[20] = "Fault: 0  Stop menu";

    count[0] = hex_digit((unsigned char)(sample >> 12));
    count[1] = hex_digit((unsigned char)(sample >> 8));
    count[2] = hex_digit((unsigned char)(sample >> 4));
    count[3] = hex_digit((unsigned char)sample);
    count[4] = 0;
    status[7] = hex_digit(SCHED_RUNNABLE);
    status[16] = hex_digit((unsigned char)(SCHED_STACK_MAX >> 4));
    status[17] = hex_digit(SCHED_STACK_MAX);
    fault[7] = hex_digit(SCHED_FAULT);

    gb_window(win_x, WIN_Y, WIN_W, WIN_H,
              task_id ? "Preempt task B" : "Preempt task A");
    gb_textbw(win_x + 2, WIN_Y + 20, "Worker never yields");
    gb_textbw(win_x + 2, WIN_Y + 33, "Counter:");
    gb_textbw(win_x + 19, WIN_Y + 33, count);
    gb_textbw(win_x + 2, WIN_Y + 46, status);
    gb_textbw(win_x + 2, WIN_Y + 59, fault);
}

static void on_event(void)
{
    if (gb_msg.type == GB_MSG_CLOSE ||
        (gb_msg.type == GB_MSG_MENU && gb_msg.p0 >= 10 && gb_msg.p0 < 18))
        gb_wm_close();
}

static const gb_win_t task_window_a = {
    2, WIN_Y, WIN_W, WIN_H, worker, repaint, on_event, menu_def
};

static const gb_win_t task_window_b = {
    41, WIN_Y, WIN_W, WIN_H, worker, repaint, on_event, menu_def
};

void main(void)
{
    spins = 0;
    task_id = SCHED_RUNNABLE > 1;
    win_x = task_id ? 41 : 2;
    gb_wm_add(task_id ? &task_window_b : &task_window_a);
    gb_menu(menu_def);
    repaint();
    gb_task_enable();
}
