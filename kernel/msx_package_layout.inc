; Private opt-in fixed-module layout. No public application boundary changes.
MSX_PACKAGE_ENTRY equ #0100
MSX_PACKAGE_CODE_SIZE equ 747
MSX_PACKAGE_IO_BASE equ #CFDB       ; after the existing 123-byte button IRQ leaf
MSX_PACKAGE_IO_OPEN equ MSX_PACKAGE_IO_BASE
MSX_PACKAGE_IO_READ equ MSX_PACKAGE_IO_BASE+8
MSX_PACKAGE_IO_CLOSE equ MSX_PACKAGE_IO_BASE+11
MSX_PACKAGE_OWNER_CHECK equ MSX_PACKAGE_IO_BASE+14
MSX_PACKAGE_MAP equ MSX_PACKAGE_IO_BASE+17
MSX_PACKAGE_ALLOC equ MSX_PACKAGE_IO_BASE+20
MSX_PACKAGE_FREE equ MSX_PACKAGE_IO_BASE+23
MSX_PACKAGE_PREFIX equ #D0E3       ; one prefetched 256-byte prefix, under launch lock
MSX_PACKAGE_LAUNCH equ #D0E4       ; 0=off, 1=ordinary path, 2=stream handled
MSX_PACKAGE_RESULT equ #D0E5       ; stream outcome, never an executable seal
MSX_PACKAGE_STATE equ #D0E7         ; 22 bytes, before the fixed data-page module
MSX_PACKAGE_IO_STATE equ #D0FD      ; three bytes
MSX_PACKAGE_CRC_BASE equ #D2EC      ; after the existing 492-byte data-page module
MSX_PACKAGE_EXTRA_BASE equ #D3A6   ; after the 186-byte shared CRC helpers
MSX_PACKAGE_ADMISSION_STATE equ #D3F0 ; 15 bytes + one private admission mode
MSX_PACKAGE_IMAGE_SIZE equ #D400-MSX_PACKAGE_IO_BASE
MSX_PACKAGE_BUFFER equ #1800       ; exclusively borrowed during serialized launch
MSX_PACKAGE_ROUTE_BASE equ #1C00   ; MSX has no 2-KiB FDC directory provider
MSX_PACKAGE_ROUTE_LIMIT equ #2200  ; backdrop scratch ends at 1C00; bulk scratch starts here
MSX_PACKAGE_PROGRESS equ MSX_PACKAGE_ROUTE_BASE+8
MSX_PACKAGE_CLEAR equ MSX_PACKAGE_ROUTE_BASE+11
MSX_PACKAGE_VALIDATE equ MSX_GBAP4_GATE+23
MSX_PACKAGE_CRC_SEED equ MSX_GBAP4_GATE+26
MSX_PACKAGE_CRC_UPDATE equ MSX_GBAP4_GATE+29
MSX_PACKAGE_CRC_FINISH equ MSX_GBAP4_GATE+32
                assert MSX_PACKAGE_ENTRY+MSX_PACKAGE_CODE_SIZE<=MSX_GBAP4_GATE,"package code overlaps admission module"
                assert MSX_PACKAGE_IO_STATE+3==MSX_DATA_PAGE_ENTRY,"package state overlaps data-page code"
                assert MSX_DATA_PAGE_ENTRY+MSX_DATA_PAGE_SIZE==MSX_PACKAGE_CRC_BASE,"data-page image overlaps CRC code"
