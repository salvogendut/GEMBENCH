        const char *exts[8];                     /* rebuild the ext list from UI_TEXT */
        unsigned char ne = 0;
        while (*p && ne < 7) { exts[ne++] = p; while (*p) p++; p++; }
        exts[ne] = 0;
        if (UI_OP == UI_OP_PICKFILE) UI_RES = gb_pickfile(UI_NAME, exts);   /* name -> UI_NAME */
        else                         UI_RES = gb_pickdir(exts);
