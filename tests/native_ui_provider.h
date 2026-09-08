/* Host storage for the actual module; never mapped into an emulator. */
#define UI_OP request[0]
#define UI_COL request[1]
#define UI_LINE request[2]
#define UI_N request[3]
#define UI_RES request[4]
#define UI_NAME ((char *)request+8)
#define UI_TEXT ((char *)request+24)
#define UI_WIDTH width
#define UI_HEIGHT height
#define KCFG_MEMSTR "512K"
#define GB_UI_TEXT_END ((const char *)request+sizeof(request))
#define GB_UI_STATUS status
#define GB_UI_SAVEUNDER saved
#define GB_POPUP_CAPACITY 4864
