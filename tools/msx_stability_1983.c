/* Read-only observation/input bridge for the unmodified 1983 core.
 * Compile in GEMBENCH, never alter the sibling emulator or accepted media.
 * SPDX-License-Identifier: BSD-3-Clause
 */
#include "msx.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    MsxMachine *m = calloc(1, sizeof(*m));
    char line[4096], command[32];
    unsigned a, b, i;
    if (!m || (argc != 4 && argc != 6)) {
        fprintf(stderr, "usage: bridge OMEGA_ROM SUNRISE_ROM PRIVATE_IMAGE [PHILIPS_BIOS SUBROM]\n");
        return 2;
    }
    msx_init(m, argc == 6 ? MSX_MODEL_PHILIPS_NMS8250 : MSX_MODEL_GENERIC_MSX2,
             MSX_REGION_PAL, 512);
    const MsxFloppyConfig floppy = {
        MSX_FLOPPY_CONTROLLER_PHILIPS_WD2793, 3, 3
    };
    int firmware_error = argc == 6 ?
        (msx_load_bios(m, argv[4]) || msx_load_subrom(m, argv[5])) :
        msx_load_omega_unified_rom(m, argv[1], 0);
    if (firmware_error || msx_configure_floppy(m, &floppy) ||
        msx_load_sunrise_ide(m, 0, argv[2]) ||
        msx_mount_sunrise_disk_mode(m, argv[3], ATA_IMAGE_READ_ONLY)) {
        fprintf(stderr, "cannot initialize 1983 reference machine\n");
        return 2;
    }
    msx_reset(m);
    puts("{\"ready\":true}");
    fflush(stdout);
    while (fgets(line, sizeof(line), stdin)) {
        a = b = 0;
        int fields = sscanf(line, "%31s %u %u", command, &a, &b);
        if (fields == 1 && !strcmp(command, "quit")) break;
        if (!strncmp(line, "ppm ", 4)) {
            line[strcspn(line, "\r\n")] = 0;
            FILE *out = fopen(line + 4, "wb");
            if (!out) { puts("{\"error\":\"cannot write screenshot\"}"); }
            else {
                fprintf(out, "P6\n%u %u\n255\n", m->vdp.render_width, m->vdp.render_height);
                for (i = 0; i < m->vdp.render_width*m->vdp.render_height; ++i) {
                    unsigned pixel = m->vdp.pixels[i];
                    fputc(pixel >> 16, out); fputc(pixel >> 8, out); fputc(pixel, out);
                }
                int error = ferror(out);
                if (fclose(out)) error = 1;
                puts(error ? "{\"error\":\"screenshot write failed\"}" : "{}");
            }
        } else if (fields == 2 && !strcmp(command, "frames") && a <= 6000) {
            for (i = 0; i < a; ++i) msx_run_frame(m);
            printf("{\"frame\":%llu,\"pc\":%u,\"sp\":%u,\"p0\":%u,\"p3\":%u,\"vdp_regs\":[%u,%u,%u,%u,%u]}\n",
                   (unsigned long long)m->frame, m->cpu.pc, m->cpu.sp,
                   m->mapper_segment[0] & 31u, m->mapper_segment[3] & 31u,
                   m->vdp.registers[0], m->vdp.registers[1], m->vdp.registers[2],
                   m->vdp.registers[7], m->vdp.registers[9]);
        } else if (fields == 3 && !strcmp(command, "key") && a < 11 && b <= 255) {
            msx_keyboard_clear(m);
            for (i = 0; i < 8; ++i)
                if (b & (1u << i)) msx_keyboard_press(m, a, i);
            puts("{}");
        } else if (fields == 3 && b <= 4096 &&
                   ((!strcmp(command, "read") && a <= 65536 && b <= 65536-a) ||
                    (!strcmp(command, "ram") && a <= m->ram_capacity && b <= m->ram_capacity-a) ||
                    (!strcmp(command, "vram") && a <= sizeof(m->vdp.vram) && b <= sizeof(m->vdp.vram)-a))) {
            putchar('[');
            for (i = 0; i < b; ++i) {
                unsigned value = !strcmp(command, "read") ? msx_memory_read(m, a+i) :
                    !strcmp(command, "ram") ? m->ram[a+i] : m->vdp.vram[a+i];
                printf("%s%u", i ? "," : "", value);
            }
            puts("]");
        } else {
            puts("{\"error\":\"invalid command\"}");
        }
        fflush(stdout);
    }
    msx_destroy(m);
    free(m);
    return 0;
}
