/* GBWEB.MOD - Browser source-cache and configuration helper.
 *
 * Browser fills the low-RAM staging block and calls the shared GB_UI entry with
 * op 6/7/9. The kernel dispatches those non-visual operations here, keeping the
 * already-full Browser application bank small. */
#include "gb.h"

#define UI_OP          (*(volatile unsigned char *)0x1700)
#define UI_N           (*(volatile unsigned char *)0x1703)
#define UI_RES         (*(volatile unsigned char *)0x1704)
#define UI_NAME        ((char *)0x1708)
#define BUI_STAGE      ((char *)0x2B00)
#define BUI_PAGES      ((volatile unsigned char *)0x3900)
#define BUI_NPAGES     (*(volatile unsigned char *)0x3904)
#define BUI_TAIL       (*(volatile unsigned int  *)0x3905)
#define BUI_STAGE_LEN  (*(volatile unsigned int  *)0x3907)
#define BUI_FLAGS      (*(volatile unsigned char *)0x3909)
#define BUI_LOCAL_LEN  (*(volatile unsigned int  *)0x390A)
#define BUI_LOCAL_POS  (*(volatile unsigned int  *)0x390C)
#define BUI_LOCAL_OFS  ((volatile unsigned char *)0x390E)
#define BUI_CTRL       (*(volatile unsigned char *)0x3911)
#define BUI_PROXY      ((char *)0x3920)
#define BUI_PROXY_HOST ((char *)0x3980)
#define BUI_PROXY_PORT (*(volatile unsigned int *)0x39C0)
#define BUI_FORM_ACTION ((char *)0x39D0)
#define BUI_FORM_NAME   ((char *)0x3A00)
#define BUI_FORM_VALUE  ((char *)0x3A18)
#define BUI_FORM_URL    ((char *)0x3A48)
#define BUI_FORM_ACTIVE (*(volatile unsigned char *)0x3AA8)
#define BUI_PROXY_MAX  95
#define BUI_SOURCE_FULL 0x01
#define BUI_PROXY_ON   0x08
#define BUI_LOCAL_EOF  0x20
#define BUI_LOCAL_BUF  ((char *)0x2900)
#define BUI_URL_BASE   ((char *)0x2900)
#define BUI_URL_LINK   ((char *)0x2960)
#define BUI_URL_RESULT ((char *)0x29C0)
#define FS_LOAD_OFS    ((volatile unsigned char *)0x144C)
#define FS_XFLAGS      (*(volatile unsigned char *)0x144F)

#define GB_FORM_EXTERNAL_STORAGE 1
#define GB_FORM_ACTION BUI_FORM_ACTION
#define GB_FORM_NAME   BUI_FORM_NAME
#define GB_FORM_VALUE  BUI_FORM_VALUE
#define GB_FORM_URL    BUI_FORM_URL
#define GB_FORM_ACTIVE BUI_FORM_ACTIVE
#include "gbform.h"

#define GB_URL_EXTERNAL_STORAGE 1
#define GB_URL_BASE   BUI_URL_BASE
#define GB_URL_LINK   BUI_URL_LINK
#define GB_URL_RESULT BUI_URL_RESULT
#include "gburl.h"

#define APP_NPAGES     (*(volatile unsigned char *)0x1437)
#define APP_PAGES      ((volatile unsigned char *)0x1438)
#define APP_BUSY       ((volatile unsigned char *)0x1440)
#define PIC_PAGE_K     (*(volatile unsigned char *)0x130B)
#define PIC_PAGE2_K    (*(volatile unsigned char *)0x1348)
#define FS_SAVE_LEN_K  (*(volatile unsigned int  *)0x14FD)

static unsigned char alloc_page(void)
{
    unsigned char i;
    for (i = 0; i < APP_NPAGES; i++) if (!APP_BUSY[i]) {
        APP_BUSY[i] = 1;
        return APP_PAGES[i];
    }
    return 0;
}

static void source_put(void)
{
    unsigned char page;
    char *src = BUI_STAGE;
    unsigned int left = BUI_STAGE_LEN, take;
    if (!BUI_STAGE_LEN || (BUI_FLAGS & BUI_SOURCE_FULL)) return;
    while (left) {
        if (!BUI_NPAGES || BUI_TAIL == 0x4000) {
            /* Leave one app page for BRSAVE.APP, which writes these borrowed
             * pages without paging this helper out underneath itself. */
            if (BUI_NPAGES >= 3 || !(page = alloc_page())) {
                BUI_FLAGS |= BUI_SOURCE_FULL;
                break;
            }
            BUI_PAGES[BUI_NPAGES++] = page;
            BUI_TAIL = 0;
        }
        take = (unsigned int)(0x4000 - BUI_TAIL);
        if (take > left) take = left;
        PIC_PAGE_K = BUI_PAGES[BUI_NPAGES - 1];
        PIC_PAGE2_K = 0;
        gb_pic_edit_buf = (unsigned int)src;
        gb_pic_edit_off = BUI_TAIL;
        FS_SAVE_LEN_K = take;
        if (!gb_pic_edit(GB_PICEDIT_WRITE)) { BUI_FLAGS |= BUI_SOURCE_FULL; break; }
        BUI_TAIL += take;
        src += take;
        left -= take;
    }
    BUI_STAGE_LEN = 0;
}

static void source_free(void)
{
    while (BUI_NPAGES) {
        PIC_PAGE_K = BUI_PAGES[--BUI_NPAGES];
        PIC_PAGE2_K = 0;
        gb_pic_close();
    }
    BUI_TAIL = BUI_STAGE_LEN = 0;
    BUI_FLAGS = 0;
    BUI_FORM_ACTIVE = 0;
}

static unsigned char key_at(const char *p)
{
    return (unsigned char)(p[0] == 'P' && p[1] == 'R' && p[2] == 'O' &&
                           p[3] == 'X' && p[4] == 'Y' && p[5] == '=');
}

static void cfg_proxy(void)
{
    char *cfg = (char *)0x1000, *p = cfg, *value = BUI_PROXY;
    unsigned int len = *(volatile unsigned int *)0x1200, pos, end, old, add, i;
    unsigned char vl = 0;
    while (value[vl] && vl < BUI_PROXY_MAX) vl++;
    pos = 0xFFFF;
    while ((unsigned int)(p - cfg) + 6 <= len) {
        if ((p == cfg || p[-1] == '\r' || p[-1] == '\n') && key_at(p)) {
            pos = (unsigned int)(p - cfg + 6); break;
        }
        p++;
    }
    if (pos == 0xFFFF) {
        if (len + 8 + vl > 512) return;
        cfg[len++] = 'P'; cfg[len++] = 'R'; cfg[len++] = 'O';
        cfg[len++] = 'X'; cfg[len++] = 'Y'; cfg[len++] = '=';
        for (i = 0; i < vl; i++) cfg[len++] = value[i];
        cfg[len++] = '\r'; cfg[len++] = '\n';
    } else {
        end = pos;
        while (end < len && cfg[end] != '\r' && cfg[end] != '\n') end++;
        old = end - pos;
        if (vl > old) {
            add = vl - old;
            if (len + add > 512) return;
            for (i = len; i > end; i--) cfg[i - 1 + add] = cfg[i - 1];
            len += add;
        } else if (vl < old) {
            add = old - vl;
            for (i = end; i < len; i++) cfg[i - add] = cfg[i];
            len -= add;
        }
        for (i = 0; i < vl; i++) cfg[pos + i] = value[i];
    }
    *(volatile unsigned int *)0x1200 = len;
}

static void save_cfg(void)
{
    unsigned char i, d = gb_drives();
    gb_set_drive((d & GB_DRV_C) ? GB_DRIVE_C : GB_DRIVE_A);
    for (i = 0; i < 4; i++) gb_back();
    gb_set_name("GEOBENCHCFG");
    gb_fs_save((char *)0x1000, *(volatile unsigned int *)0x1200);
}

static void load_proxy(void)
{
    const char *cfg = (const char *)0x1000;
    unsigned int len = *(volatile unsigned int *)0x1200, i = 0;
    unsigned char n = 0;
    BUI_PROXY[0] = 0;
    while (i + 6 <= len) {
        if ((!i || cfg[i - 1] == '\r' || cfg[i - 1] == '\n') && key_at(cfg + i)) {
            i += 6;
            while (i < len && cfg[i] != '\r' && cfg[i] != '\n' && n < BUI_PROXY_MAX)
                BUI_PROXY[n++] = cfg[i++];
            break;
        }
        i++;
    }
    BUI_PROXY[n] = 0;
}

static unsigned char lower(unsigned char c)
{
    return (unsigned char)(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
}

static unsigned char prefix(const char *s, const char *want)
{
    while (*want) if (lower((unsigned char)*s++) != (unsigned char)*want++) return 0;
    return 1;
}

static unsigned char parse_proxy(void)
{
    const char *p = BUI_PROXY;
    char *dst = BUI_PROXY_HOST;
    unsigned char n = 0, digit;
    unsigned int port = 80;
    BUI_CTRL &= (unsigned char)~BUI_PROXY_ON;
    if (!*p) return 1;
    if (prefix(p, "https://")) return 0;
    if (prefix(p, "http://")) p += 7;
    while (*p && *p != ':' && *p != '/' && n < 63) { *dst++ = *p++; n++; }
    *dst = 0;
    if (!n || (n == 63 && *p && *p != ':' && *p != '/')) return 0;
    if (*p == ':') {
        p++; port = 0;
        if (*p < '0' || *p > '9') return 0;
        while (*p >= '0' && *p <= '9') {
            digit = (unsigned char)(*p++ - '0');
            if (port > 6553 || (port == 6553 && digit > 5)) return 0;
            port = (unsigned int)(port * 10 + digit);
        }
        if (!port) return 0;
    }
    if (*p == '/') p++;
    if (*p) return 0;
    BUI_PROXY_PORT = port;
    BUI_CTRL |= BUI_PROXY_ON;
    return 1;
}

static void local_read(void)
{
    unsigned int n, off, i;
    if (BUI_CTRL & BUI_LOCAL_EOF) {
        BUI_LOCAL_LEN = BUI_LOCAL_POS = 0;
        UI_RES = 0;
        return;
    }
    FS_LOAD_OFS[0] = BUI_LOCAL_OFS[0];
    FS_LOAD_OFS[1] = BUI_LOCAL_OFS[1];
    FS_LOAD_OFS[2] = BUI_LOCAL_OFS[2];
    FS_XFLAGS = 0x01;
    n = gb_fs_load(BUI_LOCAL_BUF, 512);
    FS_XFLAGS = 0;
    for (i = 0; i < n; i++) if ((unsigned char)BUI_LOCAL_BUF[i] == 0x1A) {
        n = i;
        BUI_CTRL |= BUI_LOCAL_EOF;
        break;
    }
    BUI_LOCAL_LEN = n; BUI_LOCAL_POS = 0;
    if (!n) { UI_RES = 0; return; }
    off = (unsigned int)BUI_LOCAL_OFS[0] | ((unsigned int)BUI_LOCAL_OFS[1] << 8);
    off += n;
    if (off < n) BUI_LOCAL_OFS[2]++;
    BUI_LOCAL_OFS[0] = (unsigned char)off;
    BUI_LOCAL_OFS[1] = (unsigned char)(off >> 8);
}

static unsigned char launch_file(void)
{
    gb_get_name(UI_NAME);
    return (unsigned char)(UI_NAME[8] == 'H' && UI_NAME[9] == 'T' &&
                           UI_NAME[10] == 'M');
}

void main(void)
{
    UI_RES = 1;
    if (UI_OP == 6) source_put();
    else if (UI_OP == 7) source_free();
    else if (UI_OP == 9) { cfg_proxy(); save_cfg(); }
    else if (UI_OP == 10) local_read();
    else if (UI_OP == 11) UI_RES = parse_proxy();
    else if (UI_OP == 12) load_proxy();
    else if (UI_OP == 13) UI_RES = launch_file();
    else if (UI_OP == 14)
        UI_RES = gb_form_process(UI_N, *(const char **)UI_NAME);
    else if (UI_OP == 15) UI_RES = gb_form_build_url();
    else if (UI_OP == 18) UI_RES = gb_url_resolve();
    else UI_RES = 0;
}
