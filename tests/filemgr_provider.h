/* Reuse the actual CPC provider contract; relocate only its device state. */
#include "../apps/filemgr/platform/cpc.h"
extern volatile gb_msg_t fm_test_message;
extern gb_fsctx_entry_t fm_test_batch[4];
#undef gb_msg
#define gb_msg fm_test_message
#undef gb_fsctx_batch_entries
#define gb_fsctx_batch_entries() fm_test_batch
