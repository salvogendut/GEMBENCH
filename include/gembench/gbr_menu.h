#ifndef GEMBENCH_GBR_MENU_H
#define GEMBENCH_GBR_MENU_H

/* GBRM is generated, code-only metadata derived from a frozen GBR1 source.
 * It is deliberately not an on-disk resource version. */
#define GBR_MENU_VERSION       1u
#define GBR_MENU_MAX_ITEMS     8u
#define GBR_MENU_TITLE_MAX     8u
#define GBR_MENU_LABEL_MAX    20u

/* State bytes are shared with the paged menu renderer. */
#define GBR_MENU_DISABLED   0x01u
#define GBR_MENU_CHECKED    0x02u
#define GBR_MENU_RADIO      0x04u
#define GBR_MENU_CHECKBOX   0x08u
#define GBR_MENU_STATE_MASK 0x0Fu

typedef struct {
    const unsigned char *descriptor;
    unsigned int size;
    unsigned char col;
    unsigned char count;
    unsigned char armed;
    unsigned char valid;
    unsigned char state[GBR_MENU_MAX_ITEMS];
    unsigned char menu_def[10];
} gbr_menu_t;

/* Validation is all-or-nothing: a malformed descriptor is never registered. */
unsigned char gbr_menu_init(gbr_menu_t *menu, const unsigned char *descriptor,
                            unsigned int size, unsigned char col);
unsigned char gbr_menu_arm(gbr_menu_t *menu, unsigned char clicked_col);
unsigned char gbr_menu_shortcut(gbr_menu_t *menu, unsigned char key,
                                unsigned char *object_id);
unsigned char gbr_menu_run(gbr_menu_t *menu, unsigned char *object_id);
unsigned char gbr_menu_set_checked(gbr_menu_t *menu, unsigned char object_id,
                                   unsigned char checked);
unsigned char gbr_menu_set_disabled(gbr_menu_t *menu, unsigned char object_id,
                                    unsigned char disabled);
unsigned char gbr_menu_checked(const gbr_menu_t *menu, unsigned char object_id);

#endif
