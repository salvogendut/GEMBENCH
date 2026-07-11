#ifndef GBURL_H
#define GBURL_H

/* Resolve a bounded HTTP link against a bounded absolute base URL. Browser
 * keeps these buffers in low RAM so GBWEB.MOD can do this outside the app bank. */
#ifndef GB_URL_MAX
#define GB_URL_MAX 95
#endif

#ifndef GB_URL_EXTERNAL_STORAGE
static char gb_url_base_storage[GB_URL_MAX + 1];
static char gb_url_link_storage[GB_URL_MAX + 1];
static char gb_url_result_storage[GB_URL_MAX + 1];
#define GB_URL_BASE   gb_url_base_storage
#define GB_URL_LINK   gb_url_link_storage
#define GB_URL_RESULT gb_url_result_storage
#endif

static unsigned char gb_url_lower(unsigned char c)
{
    if (c >= 'A' && c <= 'Z') c = (unsigned char)(c + ('a' - 'A'));
    return c;
}

static unsigned char gb_url_prefix(const char *s, const char *prefix)
{
    while (*prefix) {
        if (!*s || gb_url_lower((unsigned char)*s++) !=
                   (unsigned char)*prefix++) return 0;
    }
    return 1;
}

static unsigned char gb_url_resolve(void)
{
    const char *base = GB_URL_BASE, *link = GB_URL_LINK;
    const char *p, *origin_end, *path_end, *cut, *slash = 0;
    unsigned char n = 0;
#define GB_URL_PUT(c) do { \
    if (n >= GB_URL_MAX) { GB_URL_RESULT[0] = 0; return 0; } \
    GB_URL_RESULT[n++] = (char)(c); \
} while (0)
#define GB_URL_COPY(s) do { \
    p = (s); \
    while (*p && *p != '#') GB_URL_PUT(*p++); \
} while (0)
    if (!*link || *link == '#') return 0;
    if (gb_url_prefix(link, "http://") || gb_url_prefix(link, "https://")) {
        GB_URL_COPY(link);
        GB_URL_RESULT[n] = 0;
        return 1;
    }
    if (link[0] == '/' && link[1] == '/') {
        GB_URL_COPY("http:");
        GB_URL_COPY(link);
        GB_URL_RESULT[n] = 0;
        return 1;
    }
    p = base;
    while (*p && !(p[0] == ':' && p[1] == '/' && p[2] == '/')) p++;
    if (!*p) return 0;
    p += 3;
    while (*p && *p != '/' && *p != '?' && *p != '#') p++;
    origin_end = p;
    path_end = origin_end;
    while (*path_end && *path_end != '?' && *path_end != '#') path_end++;
    if (*link == '/') cut = origin_end;
    else if (*link == '?') cut = path_end;
    else {
        for (p = origin_end; p < path_end; p++) if (*p == '/') slash = p + 1;
        cut = slash ? slash : origin_end;
    }
    for (p = base; p < cut; p++) GB_URL_PUT(*p);
    if (cut == origin_end && *link != '/') GB_URL_PUT('/');
    GB_URL_COPY(link);
    GB_URL_RESULT[n] = 0;
    return 1;
#undef GB_URL_COPY
#undef GB_URL_PUT
}

#endif
