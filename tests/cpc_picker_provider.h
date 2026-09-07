#define UI_OP request[0]
#define UI_RES request[4]
#define UI_NAME ((char *)request+8)
#define UI_TEXT ((char *)request+24)
#define GB_UI_TEXT_END ((const char *)request+sizeof(request))
#define GB_UI_STATUS ui_status
#define CPC_PICK_PATH last_path
#define CPC_PICK_OWNER last_owner
#define CPC_UI_OWNER caller_owner
#define CPC_PICK_STATUS pick_status
