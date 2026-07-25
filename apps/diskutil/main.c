/*
 * DISKUTIL.APP - a floppy-disk formatter for GEOBENCH (both platforms).
 *
 * Reuses the existing floppy icon (DEFAULT.IST slot 0; the File Manager maps
 * DISKUTIL.APP -> that slot). A kernel-managed window (like apps/settings): pick a
 * drive + a disk format from a list, press FORMAT, confirm the (destructive!) op,
 * and watch a progress/result line. All format code is carried IN this app's bank
 * (inline __asm), so the resident kernel pays nothing.
 *
 * CPC: a TRUE physical format straight to the uPD765 FDC (ports FB7E/FB7F/FA7E),
 *   the same controller lib/fs_amsdos_core.asm reads - here we drive its FORMAT
 *   TRACK (0x4D) command per track (and per side for the exotic 80-track double-
 *   sided geometry). Filler 0xE5 leaves an empty AMSDOS catalog -> usable at once.
 * MSX2: a FAT12 quick-format - MSX-DOS owns the drive, so we rewrite the file
 *   system (boot sector + 2 FATs + root dir) with absolute-sector writes (BDOS
 *   WRABS, fn 0x30) into an empty native 720K disk. A real physical / geometry-
 *   changing format needs the interface-specific disk-ROM DSKFMT (deferred).
 */
#include "gb.h"

#define TITLE_H 14
#define DEF_X   20
#define DEF_Y   40
#define WIN_W   40
#define WIN_H   96

static unsigned char win_x, win_y, win_w, win_h;
static void d_draw(void);           /* forward: dialogs repaint the window on exit */

/* ---- format table ---------------------------------------------------------- */
typedef struct {
    const char   *name;
    unsigned char tracks;   /* cylinders */
    unsigned char sides;    /* 1 or 2 (heads) */
    unsigned char spt;      /* sectors per track */
    unsigned char base;     /* first physical sector id (CPC); unused on MSX */
} fmt_t;

#ifdef GB_MSX2
static const fmt_t formats[] = {
    { "FAT12 720K (native)", 80, 2, 9, 0 },
};
#define N_FMT 1
static unsigned char drive = 0;     /* MSX: format drive A */
#else
static const fmt_t formats[] = {
    { "AMSDOS Data 178K",    40, 1, 9, 0xC1 },  /* native default */
    { "AMSDOS System 169K",  40, 1, 9, 0x41 },  /* reserves 2 tracks for CP/M */
    { "Data DS 80trk 711K",  80, 2, 9, 0xC1 },  /* exotic - needs a 3.5\"/80-trk drive */
};
#define N_FMT 3
static unsigned char drive = 0;     /* 0 = A, 1 = B */
#endif

static unsigned char sel = 0;       /* selected format row */
static char statusmsg[22] = "Select a format.";

/* row geometry (win_x/win_y are refreshed before use) */
#define DRV_Y      (unsigned char)(win_y + TITLE_H + 3)
#define LIST_Y0    (unsigned char)(win_y + TITLE_H + 17)
#define ROW_H      10
#define ROW_Y(i)   (unsigned char)(LIST_Y0 + (i) * ROW_H)
#define BTN_Y      (unsigned char)(LIST_Y0 + N_FMT * ROW_H + 5)
#define BTN_W      16                 /* "[ FORMAT ]" hit width, byte columns */
#define STAT_Y     (unsigned char)(win_y + win_h - 9)

/* ---- little decimal helper -------------------------------------------------- */
static unsigned char putdec(char *d, unsigned char v)
{
    unsigned char n = 0;
    if (v >= 100) { d[n++] = (char)('0' + v / 100); v = (unsigned char)(v % 100);
                    d[n++] = (char)('0' + v / 10);  d[n++] = (char)('0' + v % 10); return n; }
    if (v >= 10)  { d[n++] = (char)('0' + v / 10);  d[n++] = (char)('0' + v % 10); return n; }
    d[n++] = (char)('0' + v);
    return n;
}

/* ---- status line ------------------------------------------------------------ */
static void set_status(const char *s)
{
    unsigned char i;
    for (i = 0; i < 21 && s[i]; i++) statusmsg[i] = s[i];
    statusmsg[i] = 0;
    gb_curhide();
    gb_fill((unsigned char)(win_x + 1), STAT_Y, (unsigned char)(win_w - 2), 8, 1);
    gb_textbw((unsigned char)(win_x + 1), STAT_Y, statusmsg);
    gb_curshow();
}

/* =====================================================================
 * CPC backend - uPD765 FDC FORMAT TRACK.  Ports: MSR FB7E, DATA FB7F, MOTOR FA7E.
 * The C loop fills f_idbuf with the C,H,R,N id list per track and calls the asm.
 * ===================================================================== */
#ifndef GB_MSX2
static volatile unsigned char f_unit;    /* (head<<2)|drive - FDC unit/head byte */
static volatile unsigned char f_track;   /* cylinder to format */
static volatile unsigned char f_spt;     /* sectors this track */
static volatile unsigned char f_st0;     /* result ST0 */
static volatile unsigned char f_st1;     /* result ST1 */
static unsigned char f_idbuf[36];        /* up to 9 sectors * (C,H,R,N) */

/* send A to the FDC data reg (wait RQM=1, DIO=0); recv a byte (wait RQM=1, DIO=1). */
static void fdc_send(void) __naked
{
__asm
fdc__sw:
    push af
fdc__sw1:
    ld   bc,#0xFB7E
    in   a,(c)
    bit  7,a
    jr   z,fdc__sw1        ; RQM must be 1
    bit  6,a
    jr   nz,fdc__sw1       ; DIO must be 0 (host -> FDC)
    pop  af
    ld   bc,#0xFB7F
    out  (c),a
    ret
__endasm;
}
static void fdc_recv(void) __naked
{
__asm
fdc__rw:
    ld   bc,#0xFB7E
    in   a,(c)
    bit  7,a
    jr   z,fdc__rw
    bit  6,a
    jr   z,fdc__rw         ; DIO must be 1 (FDC -> host)
    ld   bc,#0xFB7F
    in   a,(c)
    ret
__endasm;
}
/* wait for the seek/recalibrate to finish, then SENSE INTERRUPT STATUS. */
static void fdc_waitseek(void) __naked
{
__asm
    ld   hl,#0
fdc__ws:
    ld   bc,#0xFB7E
    in   a,(c)
    and  #0x0F             ; any drive still seeking?
    jr   z,fdc__wsd
    dec  hl
    ld   a,h
    or   l
    jr   nz,fdc__ws
fdc__wsd:
    ld   a,#0x08           ; SENSE INTERRUPT STATUS
    call _fdc_send
    call _fdc_recv         ; ST0
    ld   (_f_st0),a
    call _fdc_recv         ; PCN
    ret
__endasm;
}
/* motor on + spin-up + RECALIBRATE (seek to track 0) on f_unit. */
static void fdc_motor_on(void) __naked
{
__asm
    di
    ld   bc,#0xFA7E
    ld   a,#1
    out  (c),a
    ld   de,#0            ; spin-up delay
fdc__spin:
    dec  de
    ld   a,d
    or   e
    jr   nz,fdc__spin
    ld   a,#0x07          ; RECALIBRATE
    call _fdc_send
    ld   a,(_f_unit)
    call _fdc_send
    call _fdc_waitseek
    ei
    ret
__endasm;
}
static void fdc_motor_off(void) __naked
{
__asm
    ld   bc,#0xFA7E
    xor  a
    out  (c),a
    ret
__endasm;
}
/* SEEK f_unit to cylinder f_track. */
static void fdc_seek(void) __naked
{
__asm
    di
    ld   a,#0x0F          ; SEEK
    call _fdc_send
    ld   a,(_f_unit)
    call _fdc_send
    ld   a,(_f_track)
    call _fdc_send
    call _fdc_waitseek
    ei
    ret
__endasm;
}
/* FORMAT TRACK: re-assert motor on, issue 0x4D, stream f_idbuf, drain 7 result bytes. */
static void fdc_format_track(void) __naked
{
__asm
    di
    ld   bc,#0xFA7E       ; keep the motor on (defeat the firmware motor-off timer)
    ld   a,#1
    out  (c),a
    ld   a,#0x4D          ; FORMAT TRACK, MFM
    call _fdc_send
    ld   a,(_f_unit)
    call _fdc_send
    ld   a,#0x02          ; N = 512 bytes/sector
    call _fdc_send
    ld   a,(_f_spt)       ; SC = sectors/track
    call _fdc_send
    ld   a,#0x52          ; GPL = format gap
    call _fdc_send
    ld   a,#0xE5          ; D = filler byte
    call _fdc_send
    ld   hl,#_f_idbuf
fdc__ftx:
    ld   bc,#0xFB7E
    in   a,(c)
    bit  7,a
    jr   z,fdc__ftx       ; wait RQM
    bit  5,a
    jr   z,fdc__ftxr      ; left execution phase -> result
    bit  6,a
    jr   nz,fdc__ftx      ; DIO must be 0 to accept a byte
    ld   a,(hl)
    inc  hl
    ld   bc,#0xFB7F
    out  (c),a
    jr   fdc__ftx
fdc__ftxr:
    call _fdc_recv        ; ST0
    ld   (_f_st0),a
    call _fdc_recv        ; ST1
    ld   (_f_st1),a
    call _fdc_recv        ; ST2
    call _fdc_recv        ; C
    call _fdc_recv        ; H
    call _fdc_recv        ; R
    call _fdc_recv        ; N
    ei
    ret
__endasm;
}

/* result: 0=fail(FDC), 1=ok, 2=aborted */
static unsigned char run_format(void)
{
    const fmt_t *f = &formats[sel];
    unsigned char t, s, k, n, ok = 1;
    char m[20];

    f_unit = drive;                 /* head 0 for motor-on/recalibrate */
    fdc_motor_on();
    for (t = 0; t < f->tracks; t++) {
        for (s = 0; s < f->sides; s++) {
            f_unit  = (unsigned char)(drive | (s << 2));
            f_track = t;
            f_spt   = f->spt;
            n = 0;
            for (k = 0; k < f->spt; k++) {          /* C,H,R,N id list for this track */
                f_idbuf[n++] = t;
                f_idbuf[n++] = s;
                f_idbuf[n++] = (unsigned char)(f->base + k);
                f_idbuf[n++] = 2;
            }
            fdc_seek();
            fdc_format_track();
            if (f_st0 & 0xC0) { ok = 0; goto done; } /* IC bits set = error */
        }
        n = 0;                                       /* "Trk t/total" progress */
        m[n++] = 'T'; m[n++] = 'r'; m[n++] = 'k'; m[n++] = ' ';
        n += putdec(&m[n], (unsigned char)(t + 1));
        m[n++] = '/';
        n += putdec(&m[n], f->tracks);
        m[n] = 0;
        set_status(m);
        if (gb_getkey() == 27) { ok = 2; goto done; } /* ESC aborts */
    }
done:
    fdc_motor_off();
    return ok;
}
#endif  /* CPC backend */

/* =====================================================================
 * MSX2 backend - FAT12 quick-format via MSX-DOS absolute-sector write.
 * The 512-byte sector image is built in gb_copybuf (#2200, page-0 low RAM, always
 * mapped) so the DOS driver reads it regardless of the app segment in page 1.
 * ===================================================================== */
#ifdef GB_MSX2
static volatile unsigned int  w_sec;     /* logical sector for WRABS (DE) */
static volatile unsigned char w_drive;   /* 0 = A: (L) */
static volatile unsigned char w_count;   /* sectors (H) */
static volatile unsigned char w_err;     /* BDOS error (A) */

/* WRABS w_count sectors from the DTA (=#2200=gb_copybuf) to w_sec on w_drive. */
static void msx_wrabs(void) __naked
{
__asm
    push ix
    ei
    ld   c,#0x1A          ; _SETDTA
    ld   de,#0x2200       ; gb_copybuf
    call 0x0005
    ld   c,#0x30          ; _WRABS
    ld   de,(_w_sec)      ; sector number
    ld   a,(_w_drive)
    ld   l,a              ; L = drive
    ld   a,(_w_count)
    ld   h,a              ; H = sector count
    call 0x0005
    ld   (_w_err),a       ; A = error code (0 = ok)
    pop  ix
    ret
__endasm;
}

static void buf_zero(void)
{
    unsigned int i;
    for (i = 0; i < 512; i++) gb_copybuf[i] = 0;
}
/* a standard 720K FAT12 boot sector / BPB (1440 sectors, 2 heads, 9 spt). */
static void build_boot(void)
{
    char *b = gb_copybuf;
    buf_zero();
    b[0] = (char)0xEB; b[1] = (char)0xFE; b[2] = (char)0x90;        /* jump */
    b[3]='G'; b[4]='E'; b[5]='O'; b[6]='B'; b[7]='E'; b[8]='N'; b[9]='C'; b[10]='H';
    b[11] = 0x00; b[12] = 0x02;      /* bytes/sector = 512 */
    b[13] = 2;                       /* sectors/cluster */
    b[14] = 1; b[15] = 0;            /* reserved sectors = 1 */
    b[16] = 2;                       /* number of FATs */
    b[17] = 112; b[18] = 0;          /* root dir entries = 112 */
    b[19] = (char)0xA0; b[20] = 0x05;/* total sectors = 1440 */
    b[21] = (char)0xF9;              /* media descriptor (720K) */
    b[22] = 3; b[23] = 0;            /* sectors/FAT */
    b[24] = 9; b[25] = 0;            /* sectors/track */
    b[26] = 2; b[27] = 0;            /* heads */
    /* extended BPB (DOS 3.31) - what a native MSX format writes, keeps fsck happy */
    b[38] = 0x29;                    /* extended boot signature */
    b[39] = 0x01; b[40] = 0x4E; b[41] = 0x42; b[42] = 0x47;    /* volume serial */
    b[43]='G';b[44]='E';b[45]='O';b[46]='B';b[47]='E';b[48]='N';b[49]='C';b[50]='H';
    b[51]=' ';b[52]=' ';b[53]=' ';   /* 11-byte volume label "GEOBENCH   " */
    b[54]='F';b[55]='A';b[56]='T';b[57]='1';b[58]='2';b[59]=' ';b[60]=' ';b[61]=' ';
    b[510] = 0x55; b[511] = (char)0xAA;
}

/* result: 0=fail, 1=ok (MSX quick-format has no per-track progress; it is fast) */
static unsigned char run_format(void)
{
    unsigned char i;
    w_drive = drive;
    w_count = 1;

    build_boot();                    /* sector 0: boot sector + BPB */
    w_sec = 0; msx_wrabs(); if (w_err) return 0;

    for (i = 0; i < 2; i++) {        /* FAT1 (sectors 1..3), FAT2 (4..6) */
        unsigned int base = (unsigned int)(1 + i * 3);
        buf_zero();
        gb_copybuf[0] = (char)0xF9; gb_copybuf[1] = (char)0xFF; gb_copybuf[2] = (char)0xFF;
        w_sec = base;     msx_wrabs(); if (w_err) return 0;
        buf_zero();
        w_sec = base + 1; msx_wrabs(); if (w_err) return 0;
        w_sec = base + 2; msx_wrabs(); if (w_err) return 0;
    }
    buf_zero();                      /* root dir sector 7: a volume-label entry matching the BPB */
    gb_copybuf[0]='G'; gb_copybuf[1]='E'; gb_copybuf[2]='O'; gb_copybuf[3]='B';
    gb_copybuf[4]='E'; gb_copybuf[5]='N'; gb_copybuf[6]='C'; gb_copybuf[7]='H';
    gb_copybuf[8]=' '; gb_copybuf[9]=' '; gb_copybuf[10]=' ';
    gb_copybuf[11]=0x08;             /* ATTR_VOLUME_ID */
    w_sec = 7; msx_wrabs(); if (w_err) return 0;
    buf_zero();                      /* remaining root-dir sectors 8..13 (empty) */
    for (i = 8; i <= 13; i++) { w_sec = i; msx_wrabs(); if (w_err) return 0; }
    return 1;
}
#endif  /* MSX backend */

/* ---- window drawing --------------------------------------------------------- */
static void d_draw(void)
{
    unsigned char i;
    char t[10];
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = gb_wm_w(); win_h = gb_wm_h();
    gb_fill(win_x, (unsigned char)(win_y + TITLE_H), win_w,
            (unsigned char)(win_h - TITLE_H), 1);              /* white panel */

    t[0]='D';t[1]='r';t[2]='i';t[3]='v';t[4]='e';t[5]=':';t[6]=0;
    gb_textbw((unsigned char)(win_x + 1), DRV_Y, t);
#ifdef GB_MSX2
    gb_textbw((unsigned char)(win_x + 8), DRV_Y, "A");
#else
    if (drive == 0) gb_textrev((unsigned char)(win_x + 8),  DRV_Y, "A");
    else            gb_textbw ((unsigned char)(win_x + 8),  DRV_Y, "A");
    if (drive == 1) gb_textrev((unsigned char)(win_x + 11), DRV_Y, "B");
    else            gb_textbw ((unsigned char)(win_x + 11), DRV_Y, "B");
#endif

    for (i = 0; i < N_FMT; i++) {
        if (i == sel) gb_textrev((unsigned char)(win_x + 1), ROW_Y(i), formats[i].name);
        else          gb_textbw ((unsigned char)(win_x + 1), ROW_Y(i), formats[i].name);
    }
    gb_button((unsigned char)(win_x + 1), (unsigned char)(BTN_Y - 1),
              BTN_W, 10, "FORMAT", 0);
    gb_textbw((unsigned char)(win_x + 1), STAT_Y, statusmsg);
}

static const char *const confirm_lbl[2] = { "FORMAT - erase disk", "Cancel" };

static void do_format(void)
{
    unsigned char r, ok;

    r = gb_popup((unsigned char)(win_x + 2), BTN_Y, confirm_lbl, 2);
    gb_curhide(); d_draw(); gb_curshow();
    if (r != 0) { set_status("Cancelled."); return; }

    set_status("Formatting...");
    ok = run_format();
#ifdef GB_MSX2
    if (ok) set_status("Done - 720K FAT12 disk.");
    else    set_status("Write error - failed.");
#else
    if (ok == 1)      set_status("Done - disk formatted.");
    else if (ok == 2) set_status("Aborted.");
    else              set_status("FDC error - failed.");
#endif
}

static void d_click(void)
{
    unsigned char mx, my, i;
    win_x = gb_wm_x(); win_y = gb_wm_y(); win_w = gb_wm_w(); win_h = gb_wm_h();
    mx = gb_mx(); my = gb_my();

#ifndef GB_MSX2
    if (my >= (unsigned char)(DRV_Y - 1) && my < (unsigned char)(DRV_Y + 8)) {
        if (mx >= (unsigned char)(win_x + 8)  && mx < (unsigned char)(win_x + 10)) {
            drive = 0; gb_curhide(); d_draw(); gb_curshow(); return; }
        if (mx >= (unsigned char)(win_x + 11) && mx < (unsigned char)(win_x + 13)) {
            drive = 1; gb_curhide(); d_draw(); gb_curshow(); return; }
    }
#endif
    for (i = 0; i < N_FMT; i++) {
        unsigned char y = ROW_Y(i);
        if (my >= (unsigned char)(y - 1) && my < (unsigned char)(y + 9)) {
            sel = i; gb_curhide(); d_draw(); gb_curshow(); return;
        }
    }
    if (gb_button_hit((unsigned char)(win_x + 1), (unsigned char)(BTN_Y - 1),
                      BTN_W, 10, mx, my, 0)) {
        do_format();
    }
}

static void d_drag(void)
{
    win_x = gb_wm_x(); win_y = gb_wm_y();
    if (gb_drag_window(&win_x, &win_y, gb_wm_w(), gb_wm_h())) {
        gb_wm_setpos(win_x, win_y);
        gb_restore_parent();
    }
}

static void d_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  d_draw();      break;
        case GB_MSG_CLICK: d_click();     break;
        case GB_MSG_CLOSE: gb_wm_close(); break;
        case GB_MSG_DRAG:  d_drag();      break;
    }
}

static const gb_mwin_t dmw = {
    DEF_X, DEF_Y, WIN_W, WIN_H, 0, 0, d_proc, "Disk Utility"
};

void main(void)
{
    unsigned char n;
    gb_wm_managed(&dmw);                              /* register FIRST (no draw) */
    for (n = 64; n; n--) if (!gb_getkey()) break;     /* drain the launch keystrokes */
    gb_restore_parent();                              /* first paint: WM chrome + d_draw */
}
