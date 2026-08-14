/* SHELL.APP - a small command shell for GEOBENCH (#365).
 *
 * Familiar commands are mapped onto the portable GEOBENCH filesystem API. Paths
 * use A:/, B:/ and C:/ drive prefixes and 8.3 components. File reads and copies
 * use the same 24-bit chunk protocol as File Manager, so file size is not limited
 * by the app bank. */
#include "gb.h"

#define WIN_X       0
#define WIN_Y       8
#define WIN_W       GB_COLS
#define WIN_H       (GB_LINES - WIN_Y)
#define OUT_Y       (WIN_Y + 16)
#define INPUT_Y     (GB_LINES - 10)
#define TEXT_X      5
#define SCROLL_X    1
#define SCROLL_W    3
#define VIEW_ROWS   ((INPUT_Y - OUT_Y - 2) / 8)

#ifdef GB_MSX2
#define TERM_COLS   80
#define HIST_LINES  34
#elif defined(GB_PCW)
#define TERM_COLS   56
#define HIST_LINES  44
#else
#define TERM_COLS   49
#define HIST_LINES  44
#endif

#define LINE_SIZE   (TERM_COLS + 1)
#define INPUT_MAX   79
#define CMD_HISTORY 4
#define PATH_MAX    40
#define IO_CHUNK    1024

#define FS_LOAD_OFS ((volatile unsigned char *)0x144C)
#define FS_XFLAGS   (*(volatile unsigned char *)0x144F)

static char history[HIST_LINES * LINE_SIZE];
static char pending[LINE_SIZE];
static char input[INPUT_MAX + 1];
static char input_draw[LINE_SIZE];
static char prompt[28];
static char arg_one[PATH_MAX], arg_two[PATH_MAX];
static char cmd_history[CMD_HISTORY * (INPUT_MAX + 1)];
static char cwd[3 * PATH_MAX];
static char path_a[PATH_MAX], path_b[PATH_MAX], path_c[PATH_MAX];
static char component[14];
static char name_a[11], name_b[11];
static char dir_name[11];
static char io_buffer[IO_CHUNK];
static const char *parse_ptr;
static const char *path_ptr;
static unsigned char path_drive;

static unsigned char hist_start, hist_count, view_top;
static unsigned char pending_len, input_len;
static unsigned char active_drive, close_requested;
static unsigned char cmd_hist_start, cmd_hist_count, cmd_hist_pos;
static unsigned char caret_tick, caret_on, key_cool;

#define HIST_AT(n) (&history[(unsigned int)(n) * LINE_SIZE])
#define CMD_AT(n)  (&cmd_history[(unsigned int)(n) * (INPUT_MAX + 1)])
#define CWD_AT(n)  (&cwd[(unsigned int)(n) * PATH_MAX])

static unsigned char upper(unsigned char c)
{
    if (c >= 'a' && c <= 'z') c = (unsigned char)(c - ('a' - 'A'));
    return c;
}

static unsigned char same_word(const char *a, const char *b)
{
    unsigned char ca, cb;
    while (*a && *b) {
        ca = upper((unsigned char)*a);
        cb = upper((unsigned char)*b);
        if (ca != cb) return 0;
        a++; b++;
    }
    return (unsigned char)(*a == 0 && *b == 0);
}

static void copy_text(char *dst, const char *src, unsigned char max)
{
    unsigned char i = 0;
    while (src[i] && i < max) { dst[i] = src[i]; i++; }
    dst[i] = 0;
}

static unsigned char text_len(const char *s)
{
    unsigned char n = 0;
    while (s[n]) n++;
    return n;
}

static unsigned char ring_index(unsigned char start, unsigned char rel,
                                unsigned char size)
{
    unsigned char n = (unsigned char)(start + rel);
    while (n >= size) n = (unsigned char)(n - size);
    return n;
}

static char *history_line(unsigned char rel)
{
    return HIST_AT(ring_index(hist_start, rel, HIST_LINES));
}

static void scroll_bottom(void)
{
    view_top = hist_count > VIEW_ROWS ? (unsigned char)(hist_count - VIEW_ROWS) : 0;
}

static void add_history_line(const char *s)
{
    unsigned char slot, i = 0;
    if (hist_count < HIST_LINES) {
        slot = ring_index(hist_start, hist_count, HIST_LINES);
        hist_count++;
    } else {
        slot = hist_start;
        hist_start = ring_index(hist_start, 1, HIST_LINES);
    }
    while (s[i] && i < TERM_COLS) { HIST_AT(slot)[i] = s[i]; i++; }
    HIST_AT(slot)[i] = 0;
    scroll_bottom();
}

static void output_flush(unsigned char force)
{
    if (!pending_len && !force) return;
    pending[pending_len] = 0;
    add_history_line(pending);
    pending_len = 0;
}

static void output_char(unsigned char c)
{
    unsigned char i;
    if (c == '\r') return;
    if (c == '\n') { output_flush(1); return; }
    if (c == '\t') {
        for (i = 0; i < 4; i++) output_char(' ');
        return;
    }
    if (c < 32 || c >= 127) c = '.';
    pending[pending_len++] = (char)c;
    if (pending_len >= TERM_COLS) output_flush(0);
}

static void output_text(const char *s)
{
    while (*s) output_char((unsigned char)*s++);
}

static void output_line(const char *s)
{
    output_text(s);
    output_flush(1);
}

static void output_error(const char *what, const char *path)
{
    output_text(what);
    if (path && *path) { output_text(": "); output_text(path); }
    output_flush(1);
}

static unsigned char drive_letter(unsigned char drive)
{
#ifdef GB_MSX2
    return gb_msx_drive_letter(drive);
#else
    if (drive == GB_DRIVE_A) return 'A';
    if (drive == GB_DRIVE_B) return 'B';
    return 'C';
#endif
}

static unsigned char drive_from_letter(unsigned char c, unsigned char *drive)
{
    c = upper(c);
#ifdef GB_MSX2
    {
        unsigned char i;
        for (i = 0; i < GB_MSX_DRIVE_COUNT; i++)
            if (gb_msx_drive_letter(i) == c) { *drive = i; return 1; }
    }
    return 0;
#else
    if (c == 'A') *drive = GB_DRIVE_A;
    else if (c == 'B') *drive = GB_DRIVE_B;
    else if (c == 'C') *drive = GB_DRIVE_C;
    else return 0;
    return 1;
#endif
}

static unsigned char valid_name_char(unsigned char c)
{
    c = upper(c);
    if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return 1;
    if (c == '_' || c == '-' || c == '$' || c == '!' || c == '#' ||
        c == '%' || c == '&' || c == '@' || c == '^' || c == '~') return 1;
    return 0;
}

/* Convert one display component to a raw, space-padded 8.3 name. */
static unsigned char make83(const char *s, char *out)
{
    unsigned char i, base = 0, ext = 0, in_ext = 0, c, pos;
    for (i = 0; i < 11; i++) out[i] = ' ';
    if (!*s) return 0;
    while (*s) {
        c = upper((unsigned char)*s++);
        if (c == '.') {
            if (in_ext || !base) return 0;
            in_ext = 1;
            continue;
        }
        if (!valid_name_char(c)) return 0;
        if (!in_ext) {
            if (base >= 8) return 0;
            pos = base; out[pos] = (char)c; base++;
        } else {
            if (ext >= 3) return 0;
            pos = (unsigned char)(8 + ext); out[pos] = (char)c; ext++;
        }
    }
    return (unsigned char)(base != 0 && (!in_ext || ext != 0));
}

static void format83(char *dst, const char *raw)
{
    unsigned char i, n = 0;
    for (i = 0; i < 8 && raw[i] != ' '; i++) { dst[n] = raw[i]; n++; }
    if (raw[8] != ' ') {
        dst[n] = '.'; n++;
        for (i = 8; i < 11 && raw[i] != ' '; i++) { dst[n] = raw[i]; n++; }
    }
    dst[n] = 0;
}

static unsigned char same83(const char *a, const char *b)
{
    unsigned char i;
    for (i = 0; i < 11; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static void path_pop(char *path)
{
    char *scan = path, *last = path;
    while (*scan) { if (*scan == '/') last = scan; scan++; }
    if (last == path) { path[0] = '/'; path[1] = 0; }
    else *last = 0;
}

static unsigned char path_append(char *path, const char *part)
{
    char *dst = path;
    unsigned char used = 0, needed = text_len(part);
    while (*dst) { dst++; used++; }
    if ((unsigned char)(used + needed + 2) >= PATH_MAX) return 0;
    if (!(used == 1 && path[0] == '/')) { *dst = '/'; dst++; }
    while (*part) { *dst = *part; dst++; part++; }
    *dst = 0;
    return 1;
}

static unsigned char read_path_component(void)
{
    char *dst = component;
    unsigned char n = 0;
    while (*path_ptr && *path_ptr != '/' && *path_ptr != '\\') {
        if (n >= 12) return 0;
        *dst = *path_ptr;
        dst++; path_ptr++; n++;
    }
    *dst = 0;
    while (*path_ptr == '/' || *path_ptr == '\\') path_ptr++;
    return 1;
}

/* Produce an uppercase, absolute path. Relative paths start at that drive's cwd. */
static unsigned char normalize_path(const char *src, unsigned char *out_drive,
                                    char *out)
{
    path_ptr = src;
    path_drive = active_drive;
    if (path_ptr[0] && path_ptr[1] == ':') {
        if (!drive_from_letter((unsigned char)path_ptr[0], &path_drive)) return 0;
        path_ptr += 2;
    }
    if (*path_ptr == '/' || *path_ptr == '\\') {
        out[0] = '/'; out[1] = 0;
        while (*path_ptr == '/' || *path_ptr == '\\') path_ptr++;
    } else copy_text(out, CWD_AT(path_drive), PATH_MAX - 1);

    while (*path_ptr) {
        if (!read_path_component()) return 0;
        if (component[0] == '.' && component[1] == 0) continue;
        if (component[0] == '.' && component[1] == '.' && component[2] == 0) {
            path_pop(out); continue;
        }
        if (!make83(component, dir_name)) return 0;
        format83(component, dir_name);
        if (!path_append(out, component)) return 0;
    }
    *out_drive = path_drive;
    return 1;
}

static unsigned char find_entry(const char *raw)
{
    char *p = gb_dir1();
    while (p) {
        if (same83(gb_entname(), raw)) return 1;
        p = gb_dirn();
    }
    return 0;
}

static void drive_root(unsigned char drive)
{
    unsigned char i;
    gb_set_drive(drive);
    for (i = 0; i < 8; i++) gb_back();
}

/* Select drive/path and leave its directory active. */
static unsigned char select_directory(unsigned char drive, const char *path)
{
    drive_root(drive);
    path_ptr = path;
    while (*path_ptr == '/' || *path_ptr == '\\') path_ptr++;
    while (*path_ptr) {
        if (!read_path_component()) return 0;
        if (!make83(component, dir_name)) return 0;
        if (!find_entry(dir_name)) return 0;
        if (!gb_isdir()) return 0;
        gb_chdir();
    }
    return 1;
}

static void restore_cwd(void)
{
    if (!select_directory(active_drive, CWD_AT(active_drive))) {
        CWD_AT(active_drive)[0] = '/'; CWD_AT(active_drive)[1] = 0;
        drive_root(active_drive);
    }
}

static unsigned char split_parent(const char *path, char *parent, char *leaf)
{
    const char *scan = path, *last = path;
    char *dst = parent;
    while (*scan) { if (*scan == '/') last = scan; scan++; }
    if (!last[1]) return 0;
    if (last == path) { parent[0] = '/'; parent[1] = 0; }
    else {
        while (path != last) { *dst = *path; dst++; path++; }
        *dst = 0;
    }
    last++;
    return make83(last, leaf);
}

static void format_location(char *dst, unsigned char drive, const char *path)
{
    unsigned char used = 2;
    *dst = (char)drive_letter(drive); dst++;
    *dst = ':'; dst++;
    while (*path && used < PATH_MAX - 1) { *dst = *path; dst++; path++; used++; }
    *dst = 0;
}

static void command_pwd(void)
{
    format_location(path_a, active_drive, CWD_AT(active_drive));
    output_line(path_a);
}

static void command_ls(const char *arg)
{
    unsigned char drive, any = 0;
    char *p;
    if (!normalize_path(arg && *arg ? arg : ".", &drive, path_a)) {
        output_error("ls: invalid path", arg); return;
    }
    if (select_directory(drive, path_a)) {
        p = gb_dir1();
        while (p) {
            format83(component, gb_entname());
            output_text(component);
            if (gb_isdir()) output_char('/');
            output_flush(1);
            any = 1; p = gb_dirn();
        }
        if (!any) output_line("(empty)");
        restore_cwd(); return;
    }
    if (!split_parent(path_a, path_b, name_a)) {
        output_error("ls: not found", arg); restore_cwd(); return;
    }
    if (!select_directory(drive, path_b)) {
        output_error("ls: not found", arg); restore_cwd(); return;
    }
    if (!find_entry(name_a)) {
        output_error("ls: not found", arg); restore_cwd(); return;
    }
    format83(component, name_a); output_text(component);
    if (gb_isdir()) output_char('/');
    output_flush(1);
    restore_cwd();
}

static void command_cd(const char *arg)
{
    unsigned char drive;
    const char *target = (arg && *arg) ? arg : "/";
    if (!normalize_path(target, &drive, path_a)) {
        output_error("cd: invalid path", target); return;
    }
    if (!select_directory(drive, path_a)) {
        output_error("cd: directory not found", target); restore_cwd(); return;
    }
    active_drive = drive;
    copy_text(CWD_AT(drive), path_a, PATH_MAX - 1);
}

static void command_rm(const char *arg)
{
    unsigned char drive;
    if (!arg || !*arg) { output_line("usage: rm FILE"); return; }
    if (!normalize_path(arg, &drive, path_a)) {
        output_error("rm: invalid path", arg); return;
    }
    if (!split_parent(path_a, path_b, name_a)) {
        output_error("rm: invalid path", arg); return;
    }
    if (!select_directory(drive, path_b)) {
        output_error("rm: not found", arg); restore_cwd(); return;
    }
    if (!find_entry(name_a)) {
        output_error("rm: not found", arg); restore_cwd(); return;
    }
    if (gb_isdir()) output_error("rm: is a directory", arg);
    else if (!gb_file_delete(name_a)) output_error("rm: delete failed", arg);
    else { output_text("removed "); output_line(arg); }
    restore_cwd();
}

static void set_offset(unsigned int lo, unsigned char hi)
{
    FS_LOAD_OFS[0] = (unsigned char)lo;
    FS_LOAD_OFS[1] = (unsigned char)(lo >> 8);
    FS_LOAD_OFS[2] = hi;
}

static void advance_offset(unsigned int *lo, unsigned char *hi, unsigned int amount)
{
    unsigned int next = (unsigned int)(*lo + amount);
    if (next < *lo) (*hi)++;
    *lo = next;
}

static void command_cat(const char *arg)
{
    unsigned char drive, hi = 0, first = 1;
    unsigned int lo = 0, got, i;
    if (!arg || !*arg) { output_line("usage: cat FILE"); return; }
    if (!normalize_path(arg, &drive, path_a)) {
        output_error("cat: invalid path", arg); return;
    }
    if (!split_parent(path_a, path_b, name_a)) {
        output_error("cat: invalid path", arg); return;
    }
    if (!select_directory(drive, path_b)) {
        output_error("cat: file not found", arg); restore_cwd(); return;
    }
    if (!find_entry(name_a)) {
        output_error("cat: file not found", arg); restore_cwd(); return;
    }
    if (gb_isdir()) {
        output_error("cat: file not found", arg); restore_cwd(); return;
    }
    gb_set_name(name_a);
    for (;;) {
        set_offset(lo, hi); FS_XFLAGS = 0x01;
        got = gb_fs_load(io_buffer, IO_CHUNK);
        if (!got) break;
        if (got > IO_CHUNK) got = IO_CHUNK;
        for (i = 0; i < got; i++) output_char((unsigned char)io_buffer[i]);
        advance_offset(&lo, &hi, got); first = 0;
        if (got < IO_CHUNK) break;
    }
    FS_XFLAGS = 0;
    if (pending_len) output_flush(0);
    if (first) output_line("");
    restore_cwd();
}

static unsigned char locate_file(const char *arg, unsigned char *drive,
                                 char *parent, char *raw)
{
    if (!normalize_path(arg, drive, path_a)) return 0;
    if (!split_parent(path_a, parent, raw)) return 0;
    if (!select_directory(*drive, parent)) return 0;
    if (!find_entry(raw)) return 0;
    if (gb_isdir()) return 0;
    return 1;
}

static unsigned char same_path(unsigned char da, const char *pa, const char *na,
                               unsigned char db, const char *pb, const char *nb)
{
    if (da != db || !same83(na, nb)) return 0;
    while (*pa && *pb && *pa == *pb) { pa++; pb++; }
    return (unsigned char)(*pa == 0 && *pb == 0);
}

static void remove_copy_target(unsigned char drive, const char *dir, const char *raw)
{
    if (select_directory(drive, dir)) gb_file_delete(raw);
}

static void command_cp(const char *src, const char *dst)
{
    unsigned char src_drive, dst_drive, hi = 0, first = 1, wrote = 0, ok = 1;
    unsigned int lo = 0, got;
    if (!src || !dst) { output_line("usage: cp SOURCE DEST"); return; }
    if (!locate_file(src, &src_drive, path_b, name_a)) {
        output_error("cp: source not found", src); restore_cwd(); return;
    }

    if (!normalize_path(dst, &dst_drive, path_a)) {
        output_error("cp: invalid destination", dst); restore_cwd(); return;
    }
    if (select_directory(dst_drive, path_a)) {
        copy_text(path_c, path_a, PATH_MAX - 1);
        { unsigned char i; for (i = 0; i < 11; i++) name_b[i] = name_a[i]; }
    } else if (!split_parent(path_a, path_c, name_b)) {
        output_error("cp: destination not found", dst); restore_cwd(); return;
    } else if (!select_directory(dst_drive, path_c)) {
        output_error("cp: destination not found", dst); restore_cwd(); return;
    }
    if (same_path(src_drive, path_b, name_a, dst_drive, path_c, name_b)) {
        output_line("cp: source and destination are the same"); restore_cwd(); return;
    }

    for (;;) {
        if (!select_directory(src_drive, path_b)) { ok = 0; break; }
        gb_set_name(name_a); set_offset(lo, hi); FS_XFLAGS = 0x01;
        got = gb_fs_load(io_buffer, IO_CHUNK);
        if (!got) {
            if (first) {
                if (!select_directory(dst_drive, path_c)) { ok = 0; break; }
                gb_set_name(name_b); FS_XFLAGS = 0x04;
                if (!gb_fs_save(io_buffer, 0)) ok = 0;
                else wrote = 1;
            }
            break;
        }
        if (got > IO_CHUNK) got = IO_CHUNK;
        if (!select_directory(dst_drive, path_c)) { ok = 0; break; }
        gb_set_name(name_b); FS_XFLAGS = first ? 0x04 : 0x06;
        if (!gb_fs_save(io_buffer, got)) { ok = 0; break; }
        wrote = 1; first = 0; advance_offset(&lo, &hi, got);
        if (got < IO_CHUNK) break;
    }
    FS_XFLAGS = 0;
    if (!ok) {
        if (wrote) remove_copy_target(dst_drive, path_c, name_b);
        output_error("cp: copy failed", dst);
    } else {
        output_text("copied "); output_text(src); output_text(" to "); output_line(dst);
    }
    restore_cwd();
}

static void command_help(void)
{
    output_line("Commands:");
    output_line("  ls [PATH]       list files");
    output_line("  cd [PATH]       change directory");
    output_line("  pwd             show current directory");
    output_line("  cat FILE        display a text file");
    output_line("  cp SOURCE DEST  copy a file");
    output_line("  rm FILE         remove a file");
    output_line("  clear           clear the window");
    output_line("  help            show this help");
    output_line("  exit            close the shell");
    output_line("Paths use A:/, B:/ or C:/ and 8.3 names.");
}

static void clear_output(void)
{
    hist_start = hist_count = view_top = pending_len = 0;
}

static void remember_command(const char *s)
{
    unsigned char slot;
    if (!*s) return;
    if (cmd_hist_count) {
        slot = ring_index(cmd_hist_start, (unsigned char)(cmd_hist_count - 1), CMD_HISTORY);
        if (same_word(CMD_AT(slot), s)) { cmd_hist_pos = 0xFF; return; }
    }
    if (cmd_hist_count < CMD_HISTORY) {
        slot = ring_index(cmd_hist_start, cmd_hist_count, CMD_HISTORY); cmd_hist_count++;
    } else {
        slot = cmd_hist_start; cmd_hist_start = ring_index(cmd_hist_start, 1, CMD_HISTORY);
    }
    copy_text(CMD_AT(slot), s, INPUT_MAX);
    cmd_hist_pos = 0xFF;
}

static unsigned char parse_token(char *dst, unsigned char max)
{
    unsigned char n = 0, c;
    while (*parse_ptr == ' ' || *parse_ptr == '\t') parse_ptr++;
    if (!*parse_ptr) { dst[0] = 0; return 0; }
    while (*parse_ptr && *parse_ptr != ' ' && *parse_ptr != '\t') {
        c = (unsigned char)*parse_ptr;
        parse_ptr++;
        if (n < max) { *dst = (char)c; dst++; n++; }
    }
    *dst = 0;
    return 1;
}

static void execute_command(void)
{
    unsigned char has_arg1, has_arg2;
    output_text(prompt); output_line(input);
    remember_command(input);
    parse_ptr = input;
    if (!parse_token(component, sizeof(component) - 1)) return;
    has_arg1 = parse_token(arg_one, PATH_MAX - 1);
    has_arg2 = parse_token(arg_two, PATH_MAX - 1);
    if (same_word(component, "ls")) {
        if (has_arg1) command_ls(arg_one); else command_ls(0);
    } else if (same_word(component, "cd")) {
        if (has_arg1) command_cd(arg_one); else command_cd(0);
    }
    else if (same_word(component, "pwd")) command_pwd();
    else if (same_word(component, "cat")) {
        if (has_arg1) command_cat(arg_one); else command_cat(0);
    } else if (same_word(component, "rm")) {
        if (has_arg1) command_rm(arg_one); else command_rm(0);
    } else if (same_word(component, "cp")) {
        if (has_arg1 && has_arg2) command_cp(arg_one, arg_two);
        else command_cp(0, 0);
    }
    else if (same_word(component, "clear")) clear_output();
    else if (same_word(component, "help")) command_help();
    else if (same_word(component, "exit") || same_word(component, "quit")) close_requested = 1;
    else output_error("command not found", component);
}

static void build_prompt(void)
{
    const char *path = CWD_AT(active_drive);
    const char *tail = path;
    unsigned char plen = text_len(path), i = 0, keep = 17;
    prompt[i++] = (char)drive_letter(active_drive); prompt[i++] = ':';
    if (plen <= keep) {
        while (*path && i < sizeof(prompt) - 3) prompt[i++] = *path++;
    } else {
        prompt[i++] = '.'; prompt[i++] = '.'; prompt[i++] = '.';
        tail = path + plen - keep;
        while (*tail && i < sizeof(prompt) - 3) prompt[i++] = *tail++;
    }
    prompt[i++] = '>'; prompt[i++] = ' '; prompt[i] = 0;
}

static void draw_scrollbar(void)
{
    gb_vscroll(SCROLL_X, OUT_Y, SCROLL_W, (unsigned char)(VIEW_ROWS * 8),
               view_top, hist_count, VIEW_ROWS, GB_WIDGET_ARROWS);
}

static void draw_output(void)
{
    unsigned char row, rel;
    gb_fill((unsigned char)(TEXT_X - 1), OUT_Y, (unsigned char)(GB_COLS - TEXT_X),
            (unsigned char)(VIEW_ROWS * 8), 0);
    draw_scrollbar();
    for (row = 0; row < VIEW_ROWS; row++) {
        rel = (unsigned char)(view_top + row);
        if (rel >= hist_count) break;
        gb_text(TEXT_X, (unsigned char)(OUT_Y + row * 8), history_line(rel));
    }
}

static void draw_input(void)
{
    unsigned char i = 0, j = 0, avail, start;
    build_prompt();
    while (prompt[i] && i < TERM_COLS) { input_draw[i] = prompt[i]; i++; }
    avail = (unsigned char)(TERM_COLS - i);
    start = input_len > avail ? (unsigned char)(input_len - avail) : 0;
    while (input[start] && i < TERM_COLS) input_draw[i++] = input[start++];
    input_draw[i] = 0;
    gb_fill((unsigned char)(TEXT_X - 1), (unsigned char)INPUT_Y,
            (unsigned char)(GB_COLS - TEXT_X), 10, 0);
    gb_text(TEXT_X, (unsigned char)INPUT_Y, input_draw);
    j = text_len(input_draw);
    if (caret_on) gb_fill((unsigned char)(TEXT_X + ((unsigned int)j * 3) / 2),
                          (unsigned char)(INPUT_Y + 8), 2, 1, 3);
}

static void draw_content(void)
{
    gb_curhide();
    gb_fill(1, OUT_Y, (unsigned char)(GB_COLS - 2), (unsigned char)(GB_LINES - OUT_Y - 1), 0);
    draw_output();
    gb_fill(1, (unsigned char)(INPUT_Y - 2), (unsigned char)(GB_COLS - 2), 1, 1);
    draw_input();
    gb_curshow();
}

static void redraw_input(void)
{
    gb_curhide(); draw_input(); gb_curshow();
}

static void redraw_output(void)
{
    gb_curhide(); draw_output(); draw_input(); gb_curshow();
}

static void recall_command(unsigned char older)
{
    unsigned char slot;
    if (!cmd_hist_count) return;
    if (cmd_hist_pos == 0xFF) cmd_hist_pos = cmd_hist_count;
    if (older) { if (cmd_hist_pos) cmd_hist_pos--; }
    else if (cmd_hist_pos < cmd_hist_count) cmd_hist_pos++;
    if (cmd_hist_pos == cmd_hist_count) { input[0] = 0; input_len = 0; }
    else {
        slot = ring_index(cmd_hist_start, cmd_hist_pos, CMD_HISTORY);
        copy_text(input, CMD_AT(slot), INPUT_MAX); input_len = text_len(input);
    }
    caret_on = 1; caret_tick = 0; redraw_input();
}

static void handle_keys(void)
{
    unsigned char c, count = 8, changed = 0;
    if (key_cool) { key_cool--; while (gb_getkey()) ; return; }
    while (count-- && (c = gb_getkey()) != 0) {
        if (c == 0x0D) {
            input[input_len] = 0; execute_command();
            input[0] = 0; input_len = 0; cmd_hist_pos = 0xFF;
            caret_on = 1; caret_tick = 0;
            if (close_requested) { gb_wm_close(); return; }
            redraw_output(); return;
        }
        if (c == 0x10) { recall_command(1); return; } /* Ctrl-P / Ctrl-N history */
        if (c == 0x0E) { recall_command(0); return; }
        if (c == 0x0C) { clear_output(); redraw_output(); return; } /* Ctrl-L */
        if (c == 0x15) { input_len = 0; input[0] = 0; changed = 1; } /* Ctrl-U */
        else if ((c == 8 || c == 0x7F) && input_len) {
            input[--input_len] = 0; changed = 1;
        } else if (c >= 32 && c < 127 && input_len < INPUT_MAX) {
            input[input_len++] = (char)c; input[input_len] = 0; changed = 1;
        }
    }
    if (changed) {
        cmd_hist_pos = 0xFF; caret_on = 1; caret_tick = 0; redraw_input();
    } else if (++caret_tick >= 18) {
        caret_tick = 0; caret_on ^= 1; redraw_input();
    }
}

static void handle_click(void)
{
    unsigned char part = gb_vscroll_hit(
        SCROLL_X, OUT_Y, SCROLL_W, (unsigned char)(VIEW_ROWS * 8),
        view_top, hist_count, VIEW_ROWS, gb_mx(), gb_my(), GB_WIDGET_ARROWS);
    if (part == GB_SCROLL_NONE || part == GB_SCROLL_THUMB) return;
    if (part == GB_SCROLL_UP) {
        if (view_top) view_top--;
    } else if (part == GB_SCROLL_DOWN) {
        if (view_top + VIEW_ROWS < hist_count) view_top++;
    } else if (part == GB_SCROLL_PAGE_UP) {
        view_top = view_top > VIEW_ROWS ? (unsigned char)(view_top - VIEW_ROWS) : 0;
    } else if (part == GB_SCROLL_PAGE_DOWN && hist_count > VIEW_ROWS) {
        unsigned char bottom = (unsigned char)(hist_count - VIEW_ROWS);
        view_top = (unsigned char)(view_top + VIEW_ROWS);
        if (view_top > bottom) view_top = bottom;
    }
    caret_on = 1; caret_tick = 0; redraw_output();
}

static void shell_proc(void)
{
    switch (gb_msg.type) {
        case GB_MSG_DRAW:  draw_content(); break;
        case GB_MSG_FRAME: handle_keys(); break;
        case GB_MSG_CLICK: handle_click(); break;
        case GB_MSG_CLOSE: FS_XFLAGS = 0; gb_wm_close(); break;
        case GB_MSG_DRAG:  break;
    }
}

static const gb_mwin_t shell_window = {
    WIN_X, WIN_Y, WIN_W, WIN_H, 0, 0, shell_proc, "Shell"
};

void main(void)
{
    unsigned char i;
    for (i = 0; i < 3; i++) { CWD_AT(i)[0] = '/'; CWD_AT(i)[1] = 0; }
    gb_wm_managed(&shell_window);
    active_drive = gb_get_drive();
#ifdef GB_MSX2
    if (active_drive >= GB_MSX_DRIVE_COUNT) active_drive = gb_boot_drive;
#else
    if (active_drive > GB_DRIVE_B) active_drive = GB_DRIVE_C;
#endif
    restore_cwd();
    cmd_hist_pos = 0xFF; caret_on = 1; key_cool = 3;
    output_line("GEOBENCH Shell");
    output_line("Type 'help' for commands.");
    gb_restore_parent();
}
