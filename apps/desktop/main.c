/* desktop - the GEOBENCH desktop, in C (the last app to leave assembly).
 *
 * Boots into PAGE_APP0. Draws the backdrop (below the kernel's top bar) and the
 * Disk / Clock / Trash icons, lets you DRAG icons (hold fire, a red outline
 * follows, release to drop), and opens an icon on double-click: Disk -> the file
 * manager, Clock -> the C demo.
 *
 * Issue #45: the desktop no longer owns a for(;;) loop - it registers a window
 * (gb_wm_run) and the KERNEL drives the master loop, calling on_frame each frame.
 * It is the single, permanent root window; app windows layer on top of it.
 *
 * A press over an icon both arms a double-click and starts a drag; releasing
 * drops the icon at its new spot (no movement => it was just a click). The
 * backdrop is a solid colour, so the drag outline erases by redrawing in the
 * backdrop pen - no save-under needed. */
#include "gb.h"

#define IC_W    8             /* icon width  (byte cols) = 32 px */
#define IC_H    32            /* icon height (lines)             */
#define BOX_H   44            /* icon + label box (hit-test/lift) */
#define XMAX    (80 - IC_W)   /* drag clamps */
#define YMIN    9
#define YMAX    (200 - BOX_H)
#define DCLICK  40
#define NONE    0xFF

/* The desktop icons: drives (C = IDE, A/B = floppies) + Clock + Trash (#65). The
   drive icons appear only when that drive is present (gb_drives poll); Clock and
   Trash are always shown. Positions are mutable (drag updates them). */
#define N_ICONS  5
#define IDX_C    0            /* Disk C = IDE */
#define IDX_A    1            /* Disk A = floppy A */
#define IDX_B    2            /* Disk B = floppy B */
#define IDX_CLOCK 3
#define IDX_TRASH 4

static unsigned char ic_x[N_ICONS]     = {  0,  0,  0, 72, 72 };
static unsigned char ic_y[N_ICONS]     = { 35, 80, 125, 35, 160 };
static const unsigned char ic_slot[N_ICONS] = { 1, 0, 0, 2, 3 };  /* ide,flp,flp,clk,trash */
static const char *const ic_lbl[N_ICONS] = { "Disk C","Disk A","Disk B","Clock","Trash" };
static const unsigned char ic_drive[N_ICONS] = { 1, 1, 1, 0, 0 };  /* opens the file mgr */
static unsigned char ic_present[N_ICONS] = { 1, 0, 0, 1, 1 };      /* drives set by poll */

static unsigned char drag_active, drag_idx, out_x, out_y, grab_dx, grab_dy;
static unsigned char dc_timer, dc_idx, held_prev;
static unsigned char want_menu, show_ram;   /* System menu (#74) */

#define DRIVE_TOP  20         /* drive icons stack down the left column, packed */
#define DRIVE_STEP 46         /* (BOX_H 44 + 2 gap), in detection order */

/* drive_poll: probe the drives, show an icon per present one and pack them down
   the left column in detection order (C, A, B) - no gaps for absent drives (#65). */
static void drive_poll(void)
{
    unsigned char d = gb_drives(), i, n = 0;
    ic_present[IDX_C] = (d & GB_DRV_C) ? 1 : 0;
    ic_present[IDX_A] = (d & GB_DRV_A) ? 1 : 0;
    ic_present[IDX_B] = (d & GB_DRV_B) ? 1 : 0;
    for (i = 0; i < 3; i++)               /* the three drive icons are indices 0..2 */
        if (ic_present[i]) {
            ic_x[i] = 0;
            ic_y[i] = DRIVE_TOP + n * DRIVE_STEP;
            n++;
        }
}

static void draw_icon(unsigned char i)
{
    gb_icon(ic_slot[i], ic_x[i], ic_y[i]);
    gb_text(ic_x[i], ic_y[i] + 34, ic_lbl[i]);
}

static void paint(void)
{
    unsigned char i;
    gb_fill(0, 8, 80, 192, 0);                 /* backdrop, below the top bar */
    for (i = 0; i < N_ICONS; i++)
        if (ic_present[i]) draw_icon(i);
    gb_curshow();
}

/* The top bar is now drawn here, not in the kernel (experiment #77). The WM runs
   bar_draw() every frame in our page regardless of focus, so the clock + the focused
   window's menu titles stay live behind any window. Nothing else touches lines 0-7
   (windows start at line 8), so each element is drawn once and only repainted when it
   changes (clock minute, menu def). Kernel state we read: KCFG_MEMSTR (RAM size, set
   by the GBCFG module) and MENU_DEF (the focused window's menu, kept by the WM). */
#define KCFG_MEMSTR ((const char *)0x121A)
#define MENU_DEF    ((volatile unsigned char *)0x1310)
#define CLK_COL     68            /* clock column (matches the old kernel bar) */

static unsigned char bar_init, bar_min, bar_msig;

static unsigned char bin(unsigned char v)   /* raw RTC reg -> binary (gb_time) */
{
    return gb_binmode ? v : (unsigned char)((v >> 4) * 10 + (v & 15));
}
static void put2(char *p, unsigned char v) { p[0] = '0' + v / 10; p[1] = '0' + v % 10; }

/* bar_menu: the focused window's menu titles (MENU_DEF: count, then {col, 8-byte
   label}*count). Clear the title region first so a previous app's titles are gone. */
static void bar_menu(void)
{
    unsigned char n = MENU_DEF[0], i, j;
    char lbl[9];
    gb_curhide();
    gb_fill(8, 0, 46, 8, 1);                  /* white, cols 8..53 (RAM/footprint/clock kept) */
    for (i = 0; i < n && i < 4; i++) {
        for (j = 0; j < 8; j++) lbl[j] = MENU_DEF[2 + i * 9 + j];
        lbl[8] = 0;
        gb_textbw(MENU_DEF[1 + i * 9], 0, lbl);
    }
    gb_curshow();
}

static void bar_clock(void)
{
    char t[6];
    gb_time();
    put2(t, bin(gb_hour)); t[2] = ':'; put2(t + 3, bin(gb_min)); t[5] = 0;
    gb_curhide(); gb_textbw(CLK_COL, 0, t); gb_curshow();
}

static void bar_draw(void)
{
    unsigned char msig, i;
    if (!bar_init) {                          /* first frame: white strip + RAM size */
        gb_curhide();
        gb_fill(0, 0, 80, 8, 1);
        gb_textbw(1, 0, KCFG_MEMSTR);
        gb_curshow();
        bar_init = 1; bar_min = 0xFF; bar_msig = 0xFF;
    }
    msig = 0;                                  /* menu titles: redraw when MENU_DEF changes */
    for (i = 0; i < (unsigned char)(MENU_DEF[0] * 9 + 1) && i < 40; i++) msig += MENU_DEF[i];
    if (msig != bar_msig) { bar_msig = msig; bar_menu(); }
    gb_time();                                 /* clock: redraw when the minute changes */
    if (bin(gb_min) != bar_min) { bar_min = bin(gb_min); bar_clock(); }
}

static unsigned char hit_icon(unsigned char mx, unsigned char my)
{
    unsigned char i;
    for (i = 0; i < N_ICONS; i++)
        if (ic_present[i] &&
            mx >= ic_x[i] && mx < ic_x[i] + IC_W &&
            my >= ic_y[i] && my < ic_y[i] + BOX_H)
            return i;
    return NONE;
}

/* dragstart: lift the icon (paint its box in the backdrop) and show a red
   outline at its position; remember where in the icon we grabbed it. */
static void dragstart(unsigned char idx, unsigned char mx, unsigned char my)
{
    drag_idx = idx;
    out_x = ic_x[idx];
    out_y = ic_y[idx];
    grab_dx = mx - out_x;
    grab_dy = my - out_y;
    drag_active = 1;
    gb_curhide();
    gb_fill(out_x, out_y, IC_W + 2, BOX_H, 0); /* erase icon + label */
    gb_frame(out_x, out_y, IC_W, IC_H, 3);     /* red outline */
    gb_curshow();
}

static void dragmove(unsigned char mx, unsigned char my)
{
    unsigned char nx, ny;
    nx = (mx >= grab_dx) ? (unsigned char)(mx - grab_dx) : 0;
    if (nx > XMAX) nx = XMAX;
    ny = (my >= grab_dy) ? (unsigned char)(my - grab_dy) : 0;
    if (ny < YMIN) ny = YMIN;
    if (ny > YMAX) ny = YMAX;
    if (nx == out_x && ny == out_y) return;    /* nothing moved */
    gb_curhide();
    gb_frame(out_x, out_y, IC_W, IC_H, 0);     /* erase old outline */
    out_x = nx;
    out_y = ny;
    gb_frame(out_x, out_y, IC_W, IC_H, 3);     /* draw new outline */
    gb_curshow();
}

static void drop(void)
{
    ic_x[drag_idx] = out_x;                     /* commit the new position */
    ic_y[drag_idx] = out_y;
    drag_active = 0;
    gb_curhide();
    gb_restore_parent();                        /* repaint desktop + restack any windows
                                                   on top, so they stay (one layer up) and
                                                   aren't erased by our backdrop fill (#65) */
}

/* a "System" menu title in the top bar (#74), right next to the RAM size; clicking
   it drops a menu (Ram Usage / Refresh Media / Exit to DOS). The Ram-Usage footprint
   shows separately, on the left of the clock. */
#define MENU_COL  8
#define MENU_END  18
#define FP_COL    54          /* footprint column - left of the clock (CLK_COL 68) */
static const unsigned char dt_menu[] = { 1, MENU_COL, 'S','y','s','t','e','m',0,0 };

/* popup: a frameless white menu (a seamless drop from the white top bar), black
   ink; returns the clicked row or 0xFF. Self-polling, like the apps' modals. */
static unsigned char popup(unsigned char x, unsigned char y,
                           const char *const *labels, unsigned char n)
{
    unsigned char i, flags, row, sel = 0xFF;
    gb_curhide();
    gb_fill(x, y, 26, n * 10 + 2, 1);
    for (i = 0; i < n; i++) gb_textbw(x + 1, y + 1 + i * 10, labels[i]);
    gb_curshow();
    for (;;) {
        flags = gb_poll();
        if (flags & GB_QUIT) break;
        if (!(flags & GB_CLICK)) continue;
        if (gb_my() >= y + 1 && gb_my() < y + 1 + n * 10 && gb_mx() >= x && gb_mx() < x + 26) {
            row = (gb_my() - (y + 1)) / 10;
            if (row < n) { sel = row; break; }
        }
        break;
    }
    if (sel == 0xFF) while (gb_poll() & GB_QUIT) ;
    gb_curhide();
    gb_fill(x, y, 26, n * 10 + 2, 0);          /* erase (backdrop) */
    gb_curshow();
    return sel;
}

/* draw_footprint: the resident kernel size on the top bar, left of the clock, as
   "<n>K used", black-on-white like the bar. */
static char fp[12];
static void draw_footprint(void)
{
    unsigned int k = (gb_ksize + 512) / 1024;  /* bytes -> KB, rounded */
    unsigned char n = 0, i = 0;
    char tmp[4];
    if (!k) tmp[n++] = '0';
    while (k) { tmp[n++] = '0' + k % 10; k /= 10; }
    while (n) fp[i++] = tmp[--n];
    fp[i++] = 'K'; fp[i++] = ' ';
    fp[i++] = 'u'; fp[i++] = 's'; fp[i++] = 'e'; fp[i++] = 'd'; fp[i] = 0;
    gb_textbw(FP_COL, 0, fp);
}

/* tidy_icons: snap every icon back to its boot position - drives packed down the
   left column (detection order), Clock/Trash on the right - then repaint (#74). */
static void tidy_icons(void)
{
    unsigned char i, n = 0;
    for (i = 0; i < 3; i++)
        if (ic_present[i]) { ic_x[i] = 0; ic_y[i] = DRIVE_TOP + n * DRIVE_STEP; n++; }
    ic_x[IDX_CLOCK] = 72; ic_y[IDX_CLOCK] = 35;     /* the boot positions (see ic_x/ic_y) */
    ic_x[IDX_TRASH] = 72; ic_y[IDX_TRASH] = 160;
    gb_curhide();
    gb_restore_parent();
}

static void run_menu(void)
{
    static const char *const items[4] = {
        "Ram Usage", "Refresh Media", "Tidy Icons", "Exit to DOS"
    };
    unsigned char sel = popup(MENU_COL, 8, items, 4);
    if (sel == 0) {                            /* Ram Usage: toggle the footprint (it then
                                                  persists - nothing else touches the bar) */
        show_ram ^= 1;
        gb_curhide();
        if (show_ram) draw_footprint();
        else gb_fill(FP_COL, 0, 13, 8, 1);
        gb_curshow();
    } else if (sel == 1) {                     /* Refresh Media (the old "Media") */
        gb_curhide();
        drive_poll();
        gb_restore_parent();
    } else if (sel == 2) {                     /* Tidy Icons */
        tidy_icons();
    } else if (sel == 3) {                     /* Exit to DOS */
        gb_exit();                              /* does not return */
    }
}

/* on_event: kernel callback (issue #32). Fires when the user clicks the
   kernel-owned top bar; proves the kernel->app round-trip by showing the
   message payload (the clicked column) in the hint line. */
/* trash_label: "Trash: NAME.EXT" from the dragged 11-byte 8.3 name (#62 phase 1). */
static char *trash_label(void)
{
    static char m[20] = "Trash: ";
    const char *e = gb_dragname;
    unsigned char i, j = 7;
    for (i = 0; i < 8 && e[i] != ' '; i++) m[j++] = e[i];
    if (e[8] != ' ') { m[j++] = '.'; for (i = 8; i < 11 && e[i] != ' '; i++) m[j++] = e[i]; }
    m[j] = 0;
    return m;
}

static void on_event(void)
{
    if (gb_msg.type == GB_MSG_DROP) {                  /* a file dropped on the desktop (#62) */
        if (hit_icon(gb_mx(), gb_my()) == IDX_TRASH) { /* on Trash -> delete the file */
            gb_file_delete(gb_dragname);               /* (the source window then re-lists) */
            gb_curhide();
            gb_text(1, 10, trash_label());             /* "Trash: NAME" confirmation */
            gb_curshow();
        }
        return;
    }
    if (gb_msg.type != GB_MSG_MENU) return;
    if (gb_msg.p0 < MENU_COL || gb_msg.p0 >= MENU_END) return;
    want_menu = 1;                                      /* "System" clicked -> drop the menu */
}

/* on_frame: one frame of the desktop, called by the kernel's window-manager loop
   (issue #45). The kernel polls before calling, so read input with gb_flags/mx/my
   - never gb_poll here. What used to be the body of a for(;;) loop, with each
   'continue' now a 'return' (end this frame). */
static void on_frame(void)
{
    unsigned char flags = gb_flags(), mx = gb_mx(), my = gb_my(), held, icon;

    if (dc_timer) dc_timer--;
    /* the desktop is the permanent root - ESC doesn't exit GEOBENCH (use System >
       Exit to DOS to leave); ESC only closes apps launched on top of it */

    if (want_menu) { want_menu = 0; run_menu(); return; }

    held = flags & GB_FIRE;
    if (held_prev && !held && drag_active) {   /* fire released -> drop */
        drop();
        held_prev = 0;
        return;
    }
    held_prev = held;

    if (drag_active) {                     /* follow the pointer */
        dragmove(mx, my);
        return;
    }

    if (!(flags & GB_CLICK)) return;       /* a fresh press? */
    icon = hit_icon(mx, my);
    if (icon == NONE) return;

    if (dc_timer && dc_idx == icon) {      /* second click -> open */
        if (ic_drive[icon]) {                                /* browse that drive (#65): */
            gb_set_drive(icon);                              /* icon idx 0/1/2 = C/A/B   */
            gb_wm_open("FILEMGR APP");
        }
        else if (icon == IDX_CLOCK) gb_wm_open("CLOCK   APP"); /* analog clock window (#72) */
        dc_timer = 0;
        held_prev = 0;
    } else {                               /* first click: arm + start drag */
        dc_idx = icon;
        dc_timer = DCLICK;
        dragstart(icon, mx, my);
    }
}

/* the desktop is the root window: full screen below the top bar, on_repaint = the
   full paint() (restacked behind any window), on_event = the top-bar click demo,
   menu = the "Disk" title. Its rect spans the screen so it is the bottom catch-all
   for click-to-focus; the kernel installs its menu when it has focus. */
static const gb_win_t deskwin = { 0, 8, 80, 192, on_frame, paint, on_event, dt_menu };

void main(void)
{
    drive_poll();                               /* drives present at boot -> icons (#65) */
    paint();
    drag_active = 0;
    dc_timer = 0;
    held_prev = 0;
    gb_on_bar(bar_draw);                        /* top-bar handler runs every frame (#77) */
    gb_wm_run(&deskwin);                        /* register + run the kernel WM (#45) */
}
