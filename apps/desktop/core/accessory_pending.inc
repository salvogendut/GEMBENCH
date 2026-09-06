/* Run only after gb_doc_frame restored the popup and released its input. */
        if (want_accessory) {
            unsigned char index = (unsigned char)(want_accessory - 1);
            want_accessory = 0;
            open_accessory(index);
        }
