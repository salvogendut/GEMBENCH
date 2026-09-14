; Private #84 receiver bindings; no application-side CPC variant.
                ifdef PORTABLE_DATA_PAGES
                fail "CPC secondary/data-page combined receiver is not qualified"
                endif
CPC_STREAM_STATE equ #1F00
CPC_STREAM_BUFFER equ #1500
CPC_STREAM_PATH equ #2840
CPC_STREAM_PATH_BYTES equ #2888
CPC_STREAM_SPLIT equ 1
SEC_STATE equ #1F0C
PKG_STATE equ #1F18
CPC_SECONDARY_BIND equ #1F30
CPC_PACKAGE_PREFIX equ #1F38
CPC_PACKAGE_READY equ #1F39
SEC_TABLE equ #1F40
SEC_TRANSFER equ CPC_STREAM_BUFFER
SEC_CURRENT equ SCHED_CURRENT
SEC_MAPPED equ BANK_CUR
SEC_LOCK equ SCHED_LOCK
SEC_OWNER_MAX equ CPC_OWNER_MAX
SEC_OWNER_CURRENT equ owner_current
SEC_MAP equ foundation_bank_set
SEC_ALLOW_IRQ equ 1
PAGE_SEAL_RELEASE equ secondary_seal_page_release
OWNER_SEAL_RELEASE equ secondary_seal_clear
PKG_BUFFER equ CPC_STREAM_BUFFER
PKG_CURRENT equ SCHED_CURRENT
PKG_LOCK equ SCHED_LOCK
PKG_MAPPED equ BANK_CUR
PKG_CAPS_LOW equ CPC_SYSINFO_BASE+16
PKG_CAPS_HIGH equ CPC_SYSINFO_BASE+32
PKG_MAP equ foundation_bank_set
PKG_READ equ cpc_package_read
PKG_CLOSE equ cpc_stream_close
PKG_ALLOW_IRQ equ 1
ADMISSION_DUAL equ 1
APP_LOAD_AND_ADMIT equ cpc_package_launch
APP_LAUNCH_GUARD equ cpc_package_guard
                ifdef PORTABLE_FS_HANDOFF
                ifndef CPC_NATIVE_SETTINGS
                fail "CPC document receiver requires the full Desktop/Settings profile"
                endif
CPC_FS_HANDOFF equ 1
PARAM_FS_IDENTITY equ 1
APP_LAUNCH_TRANSACTION equ document_launch
APP_LAUNCH_BIND equ document_bind
CORE_FSCTX_CLEANUP_TAIL equ document_owner_cleanup
DOC_PENDING equ #2460
DOC_CURRENT_OWNER equ owner_current
DOC_LAUNCH_BODY equ wm_open_transaction
DOC_LAUNCH_ARG equ launch_arg
DOC_COPY_NAME equ copy11
DOC_RELEASING_OWNER equ CORE_ALLOC_OWNER
DOC_WORKER equ SCHED_CURRENT
                endif
CPC_PACKAGE_MODULE_BASE equ CPC_LOADER_BASE
CPC_PACKAGE_MODULE_SIZE equ CPC_LOADER_END-CPC_LOADER_BASE
                include "core/secondary_contract.inc"
                include "core/package_stream_contract.inc"
                assert SEC_TABLE+8*CPC_OWNER_MAX<=CPC_ADAPTER_STATE_END,"package state overflow"
                assert CPC_STREAM_STATE+11<=SEC_STATE,"stream/secondary state overlap"
                assert SEC_STATE+12<=PKG_STATE,"secondary/package state overlap"
                assert PKG_STATE+22<=CPC_SECONDARY_BIND,"package/bind state overlap"
                assert CPC_SECONDARY_BIND+8<=CPC_PACKAGE_PREFIX,"bind/prefix overlap"
                assert CPC_PACKAGE_READY+1<=SEC_TABLE,"ready/seal table overlap"
