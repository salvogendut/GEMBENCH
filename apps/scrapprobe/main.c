/* Disposable service diagnostic, not a migrated editor. Uses only public ABI.
 * A second launch verifies the clipboard survived the first owner's teardown. */
#include "gbuniversal.h"
#include "gbscrap.h"

volatile unsigned char scrapprobe_state[8];
static char input[512], output[512];
static unsigned char arena[32];
static gb_params_t request;
#define HEADER (arena + 8)
#define CHECK(x) do { ++scrapprobe_state[1]; if (!(x)) { scrapprobe_state[0]=255; return; } } while (0)

static unsigned char boundary(unsigned int pointer, unsigned int size)
{
    request.operation = GB_PARAMS_CLIPBOARD;
    request.version = GB_PARAMS_VERSION;
    request.data[0] = (unsigned char)pointer;
    request.data[1] = (unsigned char)(pointer >> 8);
    request.data[2] = (unsigned char)size;
    request.data[3] = (unsigned char)(size >> 8);
    return (unsigned char)(gb_parameters(&request) >> 8);
}
static unsigned char wire(unsigned char action, unsigned int pointer, unsigned int size)
{
    HEADER[0] = action; HEADER[2] = GB_SCRAP_TEXT;
    HEADER[4] = (unsigned char)pointer; HEADER[5] = (unsigned char)(pointer >> 8);
    HEADER[6] = (unsigned char)size; HEADER[7] = (unsigned char)(size >> 8);
    if (boundary((unsigned int)HEADER, 8)) return 255;
    return HEADER[1];
}
static unsigned char equal(const char *a, const char *b, unsigned int size)
{
    while (size--) if (*a++ != *b++) return 0;
    return 1;
}
static void exercise(void)
{
    gb_scrap_info_t info;
    unsigned int got, i;
    CHECK(gb_scrap_query(&info) == GB_SCRAP_OK);
    if (info.length) {
        CHECK(info.type == GB_SCRAP_TEXT && info.length == 6);
        CHECK(gb_scrap_get(GB_SCRAP_TEXT, output, 6, &got) == GB_SCRAP_OK &&
              got == 6 && equal(output, "SHARED", 6));
        scrapprobe_state[2] = 1;
    } else {
        CHECK(info.type == GB_SCRAP_UNTYPED);
    }
    gb_scrap_clear();
    CHECK(gb_scrap_query(&info) == GB_SCRAP_OK && !info.length && !info.type);
    CHECK(gb_scrap_get(GB_SCRAP_ANY, 0, 0, &got) == GB_SCRAP_OK && !got);
    for (i=0; i<512; ++i) { input[i]=(char)(i*13u+7u); output[i]=0x69; }
    CHECK(gb_scrap_set(GB_SCRAP_TEXT, input, 512) == GB_SCRAP_TRUNCATED);
    CHECK(gb_scrap_query(&info) == GB_SCRAP_OK && info.length == 510 &&
          info.type == GB_SCRAP_TEXT && gb_scrap_type() == GB_SCRAP_TEXT);
    CHECK(gb_scrap_get(GB_SCRAP_BITMAP, output, 510, &got) == GB_SCRAP_ERR_MISMATCH &&
          !got && output[0] == 0x69);
    CHECK(gb_scrap_get(GB_SCRAP_TEXT, output, 3, &got) == GB_SCRAP_TRUNCATED &&
          got == 3 && equal(input, output, 3) && output[3] == 0x69);
    CHECK(gb_scrap_get(GB_SCRAP_ANY, output, 512, &got) == GB_SCRAP_OK &&
          got == 510 && equal(input, output, 510) && output[510] == 0x69);
    CHECK(gb_scrap_get(GB_SCRAP_TEXT, 0, 0, &got) == GB_SCRAP_TRUNCATED && !got);
    CHECK(gb_scrap_get(GB_SCRAP_TEXT, 0, 1, &got) == GB_SCRAP_ERR_ARGUMENT && !got);
    CHECK(gb_scrap_get(5, output, 510, &got) == GB_SCRAP_ERR_TYPE && !got);
    CHECK(gb_scrap_get(GB_SCRAP_ANY, output, 510, 0) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(gb_scrap_query(0) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(gb_scrap_set(GB_SCRAP_TEXT, 0, 1) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(gb_scrap_set(0, input, 0) == GB_SCRAP_ERR_TYPE);
    CHECK(gb_scrap_set(5, input, 1) == GB_SCRAP_ERR_TYPE);
    CHECK(gb_scrap_set(255, input, 1) == GB_SCRAP_ERR_TYPE);
    CHECK(gb_scrap_get(GB_SCRAP_TEXT, output, 510, &got) == GB_SCRAP_OK &&
          got == 510 && equal(input, output, 510)); /* invalid calls preserve scrap */
    CHECK(boundary(0x3FFF,8) == GB_PARAMS_BADARG);
    CHECK(boundary(0x7EF9,8) == GB_PARAMS_BADARG);
    CHECK(boundary(0xFFF8,8) == GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)HEADER,7) == GB_PARAMS_BADARG);
    CHECK(boundary((unsigned int)HEADER,9) == GB_PARAMS_BADARG);
    HEADER[0]=4;
    CHECK(boundary((unsigned int)HEADER,8) == GB_PARAMS_BADARG);
    CHECK(wire(1,0x3FFF,1) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(wire(1,0x7EFF,2) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(wire(1,0xFFFF,2) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(wire(1,(unsigned int)HEADER,1) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(wire(1,(unsigned int)HEADER-1,2) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(wire(1,(unsigned int)HEADER+7,1) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(gb_scrap_get(GB_SCRAP_TEXT, output, 510, &got) == GB_SCRAP_OK &&
          got == 510 && equal(input, output, 510));
    CHECK(wire(2,(unsigned int)HEADER,1) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(wire(2,(unsigned int)HEADER-1,2) == GB_SCRAP_ERR_ARGUMENT);
    CHECK(wire(2,(unsigned int)HEADER+7,1) == GB_SCRAP_ERR_ARGUMENT);
    arena[7]='L'; arena[16]='R';
    CHECK(wire(1,(unsigned int)HEADER-1,1) == GB_SCRAP_OK);
    CHECK(gb_scrap_get(GB_SCRAP_TEXT, output, 1, &got) == GB_SCRAP_OK && output[0]=='L');
    CHECK(wire(1,(unsigned int)HEADER+8,1) == GB_SCRAP_OK);
    CHECK(gb_scrap_get(GB_SCRAP_TEXT, output, 1, &got) == GB_SCRAP_OK && output[0]=='R');
    CHECK(wire(2,(unsigned int)HEADER-1,1) == GB_SCRAP_OK && arena[7]=='R');
    CHECK(wire(2,(unsigned int)HEADER+8,1) == GB_SCRAP_OK && arena[16]=='R');
    CHECK(gb_scrap_set(GB_SCRAP_ICON, input, 510) == GB_SCRAP_OK);
    CHECK(gb_scrap_type() == GB_SCRAP_ICON);
    CHECK(gb_scrap_get(GB_SCRAP_UNTYPED, output, 1, &got) == GB_SCRAP_ERR_MISMATCH && !got);
    CHECK(gb_scrap_set(GB_SCRAP_FILELIST, input, 1) == GB_SCRAP_OK);
    CHECK(gb_scrap_type() == GB_SCRAP_FILELIST);
    CHECK(gb_scrap_set(GB_SCRAP_BITMAP, 0, 0) == GB_SCRAP_OK);
    CHECK(gb_scrap_query(&info) == GB_SCRAP_OK && !info.length && !info.type);
    CHECK(gb_scrap_set(GB_SCRAP_TEXT, "SHARED", 6) == GB_SCRAP_OK);
    scrapprobe_state[0] = 85;
}
static void proc(void)
{
    gb_msg_t m;
    gb_message_read(&m);
    if (m.type == GB_MSG_DRAW) {
        gb_rect_t r; gb_window_rect(&r);
        gb_fill(r.x+1,r.y+14,r.w-2,r.h-15,GB_UI_SURFACE);
        gb_textbw(r.x+4,r.y+22,scrapprobe_state[0]==85 ? "CLIPBOARD PASS" : "CLIPBOARD FAIL");
    }
    if (m.type == GB_MSG_CLOSE) gb_wm_close();
}
static gb_mwin_t window={11,66,58,50,0,0,proc,"Portable clipboard"};
void main(void)
{
    if (!gb_universal_ready()) return;
    scrapprobe_state[0]=1;
    exercise();
    gb_wm_managed(&window);
    gb_restore_parent();
}
