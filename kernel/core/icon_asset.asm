; Shared icon selection/fallback. Providers own mapping, capacity and publication.
icon_init
                ICON_ENTER
                ld hl,KCFG_ICONNAME
                ld de,fs_req_name
                call copy11
                ld hl,ICON_LOAD_MAX
                ld (fs_load_max),hl
                ld hl,ICON_LOAD_DST
                ld (fs_load_dst),hl
                ld hl,def_ist
                call load_or_default
                ICON_APPLY
                ICON_LEAVE
                ret
