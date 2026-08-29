#include <stdio.h>
#include <string.h>

#include "gbr_menu.h"
#include "view_menu_gbr.h"

static unsigned char registered[10];
static unsigned char register_count;
static unsigned char popup_result;
static unsigned char popup_state[GBR_MENU_MAX_ITEMS];
static int failures;

void gbr_menu_host_register(const void *definition)
{
    memcpy(registered, definition, sizeof(registered));
    register_count++;
}

unsigned char gbr_menu_host_popup(unsigned char col,
                                  const unsigned char *descriptor,
                                  unsigned int size,
                                  const unsigned char *state)
{
    (void)descriptor;
    (void)size;
    if (col != 10) return 0xFF;
    memcpy(popup_state, state, GBR_MENU_MAX_ITEMS);
    return popup_result;
}

static void check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", message);
        failures++;
        return;
    }
    printf("ok   %s\n", message);
}

int main(void)
{
    gbr_menu_t menu;
    unsigned char object = 0xFF;
    unsigned char corrupt[FILEMGR_VIEW_MENU_SIZE + 1];

    memset(&menu, 0, sizeof(menu));
    check(gbr_menu_init(&menu, filemgr_view_menu_gbrm,
                        FILEMGR_VIEW_MENU_SIZE, 10),
          "valid generated menu initializes");
    check(register_count == 1 && registered[0] == 1 && registered[1] == 10 &&
              !memcmp(registered + 2, "View", 4),
          "title is registered only after validation");
    check(gbr_menu_checked(&menu, FILEMGR_VIEW_ICONS) &&
              !gbr_menu_checked(&menu, FILEMGR_VIEW_LIST),
          "initial radio state comes from resource metadata");
    check(!gbr_menu_arm(&menu, 9) && gbr_menu_arm(&menu, 10),
          "only the resource title range arms the popup");
    popup_result = 2;
    check(gbr_menu_run(&menu, &object) && object == FILEMGR_VIEW_LIST,
          "popup result dispatches generated object identity");
    check(!gbr_menu_checked(&menu, FILEMGR_VIEW_ICONS) &&
              gbr_menu_checked(&menu, FILEMGR_VIEW_LIST),
          "radio activation is exclusive");
    check(gbr_menu_shortcut(&menu, 'i', &object) &&
              object == FILEMGR_VIEW_ICONS &&
              gbr_menu_checked(&menu, FILEMGR_VIEW_ICONS),
          "shortcuts are case-insensitive and activate radio items");
    check(gbr_menu_shortcut(&menu, 'F', &object) &&
              object == FILEMGR_VIEW_FULLSCREEN &&
              gbr_menu_checked(&menu, FILEMGR_VIEW_FULLSCREEN),
          "checkbox shortcut toggles checked state");
    check(gbr_menu_shortcut(&menu, 'f', &object) &&
              !gbr_menu_checked(&menu, FILEMGR_VIEW_FULLSCREEN),
          "checkbox shortcut toggles back off");
    check(gbr_menu_set_disabled(&menu, FILEMGR_VIEW_LIST, 1) &&
              !gbr_menu_shortcut(&menu, 'L', &object),
          "disabled items suppress shortcut activation");
    popup_result = 2;
    check(gbr_menu_arm(&menu, 10) && !gbr_menu_run(&menu, &object) &&
              (popup_state[2] & GBR_MENU_DISABLED),
          "disabled popup rows cannot dispatch and reach the renderer as disabled");
    check(gbr_menu_set_disabled(&menu, FILEMGR_VIEW_LIST, 0) &&
              gbr_menu_set_checked(&menu, FILEMGR_VIEW_LIST, 1) &&
              !gbr_menu_checked(&menu, FILEMGR_VIEW_ICONS),
          "callers can synchronize live radio state");

    memcpy(corrupt, filemgr_view_menu_gbrm, FILEMGR_VIEW_MENU_SIZE);
    corrupt[0] = 'X';
    check(!gbr_menu_init(&menu, corrupt, FILEMGR_VIEW_MENU_SIZE, 10) &&
              register_count == 1,
          "bad magic fails without partial menu registration");
    memcpy(corrupt, filemgr_view_menu_gbrm, FILEMGR_VIEW_MENU_SIZE);
    corrupt[12] = 0x80;
    check(!gbr_menu_init(&menu, corrupt, FILEMGR_VIEW_MENU_SIZE, 10) &&
              register_count == 1,
          "unknown state bits fail without registration");
    memcpy(corrupt, filemgr_view_menu_gbrm, FILEMGR_VIEW_MENU_SIZE);
    corrupt[34] = corrupt[11];
    check(!gbr_menu_init(&menu, corrupt, FILEMGR_VIEW_MENU_SIZE, 10) &&
              register_count == 1,
          "duplicate action identities fail without registration");
    check(!gbr_menu_init(&menu, filemgr_view_menu_gbrm,
                         FILEMGR_VIEW_MENU_SIZE - 1, 10) &&
              register_count == 1,
          "truncated descriptors fail without registration");
    memcpy(corrupt, filemgr_view_menu_gbrm, FILEMGR_VIEW_MENU_SIZE);
    corrupt[FILEMGR_VIEW_MENU_SIZE] = 0;
    check(!gbr_menu_init(&menu, corrupt, FILEMGR_VIEW_MENU_SIZE + 1, 10) &&
              register_count == 1,
          "trailing descriptor bytes fail canonical validation");
    return failures ? 1 : 0;
}
