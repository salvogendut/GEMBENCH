/* Compact application-side runtime for generated GBRM menu metadata. */
#include "gbr_menu.h"

#ifdef GBR_MENU_HOST_TEST
extern void gbr_menu_host_register(const void *definition);
extern unsigned char gbr_menu_host_popup(
    unsigned char col, const unsigned char *descriptor, unsigned int size,
    const unsigned char *state);
#define menu_register gbr_menu_host_register
#define menu_popup gbr_menu_host_popup
#else
#include "gb.h"
#define menu_register gb_menu
#define menu_popup gb_resource_menu_popup
#endif

#define GBRM_HEADER 7u

static unsigned char fold(unsigned char value)
{
    if (value >= 'A' && value <= 'Z') value = (unsigned char)(value | 0x20);
    return value;
}

static const unsigned char *item_at(const gbr_menu_t *menu, unsigned char wanted)
{
    const unsigned char *p = menu->descriptor + GBRM_HEADER + menu->descriptor[6];
    unsigned char index;
    for (index = 0; index < wanted; index++) p += (unsigned char)(4u + p[3]);
    return p;
}

static unsigned char find_object(const gbr_menu_t *menu, unsigned char object_id)
{
    unsigned char index;
    if (!menu || !menu->valid) return 0xFF;
    for (index = 0; index < menu->count; index++)
        if (item_at(menu, index)[0] == object_id) return index;
    return 0xFF;
}

static unsigned char activate(gbr_menu_t *menu, unsigned char index,
                              unsigned char *object_id)
{
    const unsigned char *item;
    unsigned char i;
    if (index >= menu->count || (menu->state[index] & GBR_MENU_DISABLED)) return 0;
    item = item_at(menu, index);
    if (menu->state[index] & GBR_MENU_RADIO) {
        for (i = 0; i < menu->count; i++)
            if (menu->state[i] & GBR_MENU_RADIO)
                menu->state[i] &= (unsigned char)~GBR_MENU_CHECKED;
        menu->state[index] |= GBR_MENU_CHECKED;
    } else if (menu->state[index] & GBR_MENU_CHECKBOX) {
        menu->state[index] ^= GBR_MENU_CHECKED;
    }
    *object_id = item[0];
    return 1;
}

static unsigned char validate(const unsigned char *data, unsigned int size)
{
    unsigned int offset;
    unsigned char count, title_len, index, other, checked_radio = 0;
    unsigned char objects[GBR_MENU_MAX_ITEMS];
    unsigned char shortcuts[GBR_MENU_MAX_ITEMS];
    if (!data || size < GBRM_HEADER) return 0;
    if (data[0] != 'G' || data[1] != 'B' || data[2] != 'R' || data[3] != 'M' ||
        data[4] != GBR_MENU_VERSION) return 0;
    count = data[5];
    title_len = data[6];
    if (!count || count > GBR_MENU_MAX_ITEMS || !title_len ||
        title_len > GBR_MENU_TITLE_MAX) return 0;
    offset = (unsigned int)(GBRM_HEADER + title_len);
    if (offset > size) return 0;
    for (index = 0; index < title_len; index++)
        if (data[GBRM_HEADER + index] < 0x20 || data[GBRM_HEADER + index] > 0x7E)
            return 0;
    for (index = 0; index < count; index++) {
        unsigned char state, shortcut, length;
        if (offset + 4u > size) return 0;
        objects[index] = data[offset];
        state = data[offset + 1];
        shortcut = data[offset + 2];
        length = data[offset + 3];
        if (objects[index] == 0xFF || state & (unsigned char)~GBR_MENU_STATE_MASK ||
            ((state & GBR_MENU_RADIO) && (state & GBR_MENU_CHECKBOX)) ||
            ((state & GBR_MENU_CHECKED) && !(state & (GBR_MENU_RADIO | GBR_MENU_CHECKBOX))) ||
            !length || length > GBR_MENU_LABEL_MAX) return 0;
        if ((state & (GBR_MENU_RADIO | GBR_MENU_CHECKED)) ==
            (GBR_MENU_RADIO | GBR_MENU_CHECKED) && checked_radio++) return 0;
        if (shortcut && (shortcut < 0x20 || shortcut > 0x7E)) return 0;
        shortcuts[index] = fold(shortcut);
        for (other = 0; other < index; other++)
            if (objects[other] == objects[index] ||
                (shortcuts[index] && shortcuts[other] == shortcuts[index])) return 0;
        offset += 4u;
        if (offset + length > size) return 0;
        for (other = 0; other < length; other++)
            if (data[offset + other] < 0x20 || data[offset + other] > 0x7E) return 0;
        offset += length;
    }
    return (unsigned char)(offset == size);
}

unsigned char gbr_menu_init(gbr_menu_t *menu, const unsigned char *descriptor,
                            unsigned int size, unsigned char col)
{
    unsigned char index, title_len;
    if (!menu) return 0;
    menu->valid = 0;
    menu->armed = 0;
    if (!validate(descriptor, size)) return 0;
    menu->descriptor = descriptor;
    menu->size = size;
    menu->col = col;
    menu->count = descriptor[5];
    for (index = 0; index < menu->count; index++)
        menu->state[index] = item_at(menu, index)[1];
    menu->menu_def[0] = 1;
    menu->menu_def[1] = col;
    title_len = descriptor[6];
    for (index = 0; index < GBR_MENU_TITLE_MAX; index++)
        menu->menu_def[2 + index] = index < title_len ? descriptor[GBRM_HEADER + index] : 0;
    menu->valid = 1;
    menu_register(menu->menu_def);
    return 1;
}

unsigned char gbr_menu_arm(gbr_menu_t *menu, unsigned char clicked_col)
{
    unsigned char width;
    if (!menu || !menu->valid) return 0;
    width = (unsigned char)((menu->descriptor[6] * 6u + 3u) / 4u);
    if (clicked_col < menu->col || clicked_col >= (unsigned char)(menu->col + width))
        return 0;
    menu->armed = 1;
    return 1;
}

unsigned char gbr_menu_shortcut(gbr_menu_t *menu, unsigned char key,
                                unsigned char *object_id)
{
    unsigned char index;
    if (!menu || !menu->valid || !object_id || !key) return 0;
    key = fold(key);
    for (index = 0; index < menu->count; index++)
        if (fold(item_at(menu, index)[2]) == key)
            return activate(menu, index, object_id);
    return 0;
}

unsigned char gbr_menu_run(gbr_menu_t *menu, unsigned char *object_id)
{
    unsigned char selected;
    if (!menu || !menu->valid || !menu->armed || !object_id) return 0;
    menu->armed = 0;
    selected = menu_popup(menu->col, menu->descriptor, menu->size, menu->state);
    if (selected == 0xFF) return 0;
    return activate(menu, selected, object_id);
}

unsigned char gbr_menu_set_checked(gbr_menu_t *menu, unsigned char object_id,
                                   unsigned char checked)
{
    unsigned char index = find_object(menu, object_id), i;
    if (index == 0xFF || !(menu->state[index] & (GBR_MENU_RADIO | GBR_MENU_CHECKBOX)))
        return 0;
    if (checked && (menu->state[index] & GBR_MENU_RADIO))
        for (i = 0; i < menu->count; i++)
            if (menu->state[i] & GBR_MENU_RADIO)
                menu->state[i] &= (unsigned char)~GBR_MENU_CHECKED;
    if (checked) menu->state[index] |= GBR_MENU_CHECKED;
    else menu->state[index] &= (unsigned char)~GBR_MENU_CHECKED;
    return 1;
}

unsigned char gbr_menu_set_disabled(gbr_menu_t *menu, unsigned char object_id,
                                    unsigned char disabled)
{
    unsigned char index = find_object(menu, object_id);
    if (index == 0xFF) return 0;
    if (disabled) menu->state[index] |= GBR_MENU_DISABLED;
    else menu->state[index] &= (unsigned char)~GBR_MENU_DISABLED;
    return 1;
}

unsigned char gbr_menu_checked(const gbr_menu_t *menu, unsigned char object_id)
{
    unsigned char index = find_object(menu, object_id);
    return (unsigned char)(index != 0xFF && (menu->state[index] & GBR_MENU_CHECKED));
}
