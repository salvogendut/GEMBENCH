; 3D-S: keep the font allocation before the F7 filesystem module. All disk
; candidates are staged/validated in the excluded F6 module bank first.
CPC_FONT_BASE equ #4000
                ifndef CPC_FONT_LIMIT
CPC_FONT_LIMIT equ #4400
                endif
CPC_FONT_STATUS equ #1850       ; 0 selected, 1 DEFAULT.FNT, 2 embedded recovery
CPC_FONT_ATTEMPT equ #1851
CPC_FONT_BYTES equ #1852
CPC_FONT_SOURCE equ #1854
CPC_FONT_DEST equ #1856
CPC_FONT_LEFT equ #1858
CPC_VISUAL_CALLS equ #185A
CPC_VISUAL_DIRTY equ #185C       ; font pixels or frame pen changed, not just RGB
CPC_ASSET_KIND equ #185D         ; 0 font, 1 icons, 2 cursor, 3 backdrop, 4..6 chrome
CPC_ICON_STATUS equ #185E
CPC_ICON_COUNT equ #185F
CPC_ICON_BYTES equ #1860
CPC_CURSOR_STATUS equ #1862
CPC_BACKDROP_STATUS equ #1863     ; 0 tile, 1 solid/missing/invalid
CPC_ASSET_EXPECT equ #1864
CPC_ASSET_ENTRIES equ #1866
CPC_ASSET_DIR equ #1867
CPC_ASSET_REMAIN equ #1869
gi_slot equ #186B
gi_x equ #186C
gi_y equ #186D
be_x equ gi_x
be_y equ gi_y
ig_w equ #186E
ig_h equ #186F
bm_src equ #1870
bm_w equ #1872
bm_h equ #1873
bm_x equ #1874
bm_y equ #1875
bm_keep equ #1876
CPC_ICON_HALF equ #1877
CPC_ASSET_BANK equ #1878
CPC_ASSET_PREVIOUS equ #1879
CPC_ICON_DEMO equ #187A          ; private root test toggle, not Desktop policy
CPC_BD_TILE equ #1880
CPC_TITLE_XFER equ #1900        ; complete candidate, published only after all reads
CPC_TITLE_MODULE_STATUS equ #196A ; 0 installed, 1 absent/invalid: plain recovery
CPC_TITLE_STATUS equ #196B      ; 0 selected TBR, 1 fallback
CPC_GADGET_STATUS equ #196C     ; 0 selected GDT, 1 TBR/module fallback
TITLE_READY equ #196D
CPC_TITLE_OFF equ #196E         ; serialized paged renderer scratch, not self-modified code
CPC_TITLE_PREVIOUS equ #196F
CPC_TITLE_NAME equ #1980
CPC_GADGET_NAME equ CPC_TITLE_NAME+11
CPC_VISUAL_STATE_END equ CPC_GADGET_NAME+11
DATA_TITLE equ #5E00
DATA_TITLE_SIZE equ 106
DATA_TITLE_CLOSE equ DATA_TITLE+56
DATA_TITLE_MAX equ DATA_TITLE_CLOSE+20
DATA_TITLE_RUN equ DATA_TITLE+DATA_TITLE_SIZE
                ifndef CPC_TITLE_LIMIT
CPC_TITLE_LIMIT equ #6000
                endif
CPC_TITLE_MODULE_SIZE equ 384
                assert pointer_background+64<=CPC_TITLE_XFER,"pointer/title staging overlap"
                assert CPC_TITLE_XFER+106<=CPC_TITLE_MODULE_STATUS,"title staging/state overlap"
                assert CPC_TITLE_PREVIOUS+1<=CPC_TITLE_NAME,"title state/config names overlap"
                assert CPC_FS_MODULE_LIMIT<=DATA_TITLE,"filesystem/title module overlap"
                assert DATA_TITLE+CPC_TITLE_MODULE_SIZE<=CPC_TITLE_LIMIT,"title module overflow"
                assert CPC_TITLE_LIMIT<=CPC_APP_IO_BUFFER,"title/filesystem I/O overlap"
                assert CPC_BD_TILE+64<=pointer_background,"backdrop/pointer save-under overlap"
DATA_ICONS equ #6100
                ifndef CPC_ICON_LIMIT
CPC_ICON_LIMIT equ CPC_APP_LIMIT
                endif
                assert CPC_APP_IO_END<=DATA_ICONS,"icon/filesystem I/O overlap"
                assert DATA_ICONS<CPC_ICON_LIMIT,"empty icon allocation"
                assert CPC_ICON_LIMIT<=CPC_APP_LIMIT,"icon/snapshot overlap"
                assert CPC_ICON_LIMIT-DATA_ICONS>=5284,"default icon set exceeds allocation"
                assert CPC_NATIVE_MODULE_STATE_END<=CPC_FONT_STATUS,"visual/native state overlap"
                assert CPC_VISUAL_STATE_END<=CPC_NATIVE_STATE_END,"visual/hardware state overlap"
                assert CPC_FONT_BASE==CPC_APP_BASE,"font staging reader base mismatch"
                assert CPC_FONT_LIMIT<=#4400,"font/filesystem module overlap"
                assert CPC_FONT_LIMIT-CPC_FONT_BASE>=816,"embedded font exceeds allocation"
