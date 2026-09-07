#define UI_OP request[0]
#define UI_RES request[4]
#define UI_NAME ((char *)request+8)
#define UI_TEXT ((char *)request+24)
#define GB_UI_STATUS ui_status
#define CPC_EDIT_OP 26
#define CPC_EDIT_STATUS edit_status
#define CPC_EDIT_CHANGED edit_changed
#define CPC_EDIT_ERROR edit_error
#define CPC_EDIT_IO_STATUS transport_status
