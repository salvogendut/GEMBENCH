; Fixed provider bindings, private until qualified by a receiving profile.
SEC_BUSY equ SEC_STATE
SEC_POINTER equ SEC_STATE+1
SEC_LENGTH equ SEC_STATE+3
SEC_ENTRY equ SEC_STATE+5
SEC_NATIVE equ SEC_STATE+7
SEC_BACK equ SEC_STATE+8
                ifndef SEC_ALLOW_IRQ
SEC_ALLOW_IRQ equ 0
                endif
                assert (SEC_ALLOW_IRQ==0)|(SEC_ALLOW_IRQ==1),"secondary IRQ profile must be boolean"
                assert (SEC_OWNER_MAX>=1)&(SEC_OWNER_MAX<=8),"invalid secondary owner capacity"
                assert ((SEC_TABLE>=#100)&(SEC_TABLE+SEC_OWNER_MAX*8<=#4000))|((SEC_TABLE>=#8000)&(SEC_TABLE+SEC_OWNER_MAX*8<=#10000)),"seals must remain fixed"
                assert ((SEC_STATE>=#100)&(SEC_STATE+12<=#4000))|((SEC_STATE>=#8000)&(SEC_STATE+12<=#10000)),"secondary state must remain fixed"
                assert ((SEC_TRANSFER>=#100)&(SEC_TRANSFER+512<=#4000))|((SEC_TRANSFER>=#8000)&(SEC_TRANSFER+512<=#10000)),"secondary transfer must remain fixed"
