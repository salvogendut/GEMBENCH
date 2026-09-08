; MSX2 fixed bindings for storage-free owner cleanup (#74).
CORE_FSCTX_TABLE equ MSX_FSCTX_TABLE
CORE_FSCTX_MAX equ MSX_FSCTX_MAX
CORE_FSCTX_RECORD_SIZE equ MSX_FSCTX_RECORD_SIZE
CORE_FSCTX_ACTIVE equ 0
CORE_FSCTX_OWNER equ 2
                include "core/fsctx_cleanup_contract.inc"
