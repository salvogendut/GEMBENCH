#!/usr/bin/env python3
"""png2spr - convert a PNG into a CPC Mode 1 masked, pre-shifted cursor sprite.

A cursor is an irregular shape on a transparent field, drawn over arbitrary
screen content, that can sit at any pixel x (4 pixels per byte). So we emit:

  * a MASK  (1-bits where the sprite is transparent -> keep the background)
  * DATA    (the sprite pens, 0 where transparent)
  * four PRE-SHIFTED copies (shifted 0..3 px) so the sprite can land on any
    pixel column; each copy is one byte wider to hold the shifted overflow.

Compositing is then  screen = (background AND mask) OR data.

Transparency: a pixel is transparent if alpha < 128 or it is background-blue
(b > 120 and r < 120). Opaque pixels map to the nearest of pen1 white, pen2
black, pen3 red (pen0 is reserved as 'transparent' in the data).

Output (RASM-includable):
  <label>_w   width in bytes (incl. shift overflow)
  <label>_h   height in rows
  <label>_hx  hotspot x (px, from sprite left)
  <label>_hy  hotspot y (px, from sprite top)
  <label>_data  dw d0,d1,d2,d3     ; per-shift data pointers
  <label>_mask  dw m0,m1,m2,m3     ; per-shift mask pointers
  d0..d3 / m0..m3  the byte arrays

Usage:
    tools/png2spr.py <in.png> <out.asm> <label> [WxH]   (default 12x16)
"""
import sys
from PIL import Image

OPAQUE = [((255, 255, 255), 1), ((0, 0, 0), 2), ((255, 0, 0), 3)]
BIT0_FOR_PIXEL = (7, 6, 5, 4)   # pen bit0 of pixel i
BIT1_FOR_PIXEL = (3, 2, 1, 0)   # pen bit1 of pixel i


def transparent(p):
    r, g, b, a = p
    return a < 128 or (b > 120 and r < 120)


def nearest_opaque_pen(rgb):
    best, bd = 1, None
    for (r, g, b), pen in OPAQUE:
        d = (r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2
        if bd is None or d < bd:
            best, bd = pen, d
    return best


def main():
    args = sys.argv[1:]
    platform = 'cpc'
    if len(args) > 1 and args[0] == '--platform':
        platform = args[1]
        args = args[2:]
    if len(args) not in (3, 4):
        print(__doc__)
        sys.exit(2)
    in_png, out_asm, label = args[0], args[1], args[2]
    tw, th = (int(v) for v in (args[3].lower().split("x") if len(args) == 4
                               else (("14", "16") if platform == 'msx2' else ("12", "16"))))

    img = Image.open(in_png).convert("RGBA")
    w, h = img.size
    px = img.load()

    # crop to the opaque (arrow) bounding box
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if not transparent(px[x, y]):
                xs.append(x)
                ys.append(y)
    img = img.crop((min(xs), min(ys), max(xs) + 1, max(ys) + 1))

    # scale to fit tw x th preserving aspect, pad transparent (blue-with-alpha0)
    img.thumbnail((tw, th), Image.LANCZOS)
    sw, sh = img.size
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    canvas.paste(img, ((tw - sw) // 2, 0))
    px = canvas.load()

    # pixel grid -> (transparent?, pen)
    grid = [[None] * tw for _ in range(th)]
    hot = None
    for y in range(th):
        for x in range(tw):
            if transparent(px[x, y]):
                grid[y][x] = None
            else:
                grid[y][x] = nearest_opaque_pen(px[x, y][:3])
                if hot is None:
                    hot = (x, y)          # topmost-leftmost opaque pixel = tip
    if hot is None:
        hot = (0, 0)

    base_bytes = (tw + 3) // 4
    out_bytes = base_bytes + 1            # room for the shift overflow
    span = out_bytes * 4

    def encode_row(pixels):
        data, mask = [], []
        for b in range(out_bytes):
            db = mb = 0
            for i in range(4):
                x = b * 4 + i
                pen = pixels[x] if x < span else None
                if pen is None:
                    mb |= (1 << BIT0_FOR_PIXEL[i]) | (1 << BIT1_FOR_PIXEL[i])
                else:
                    if pen & 1:
                        db |= 1 << BIT0_FOR_PIXEL[i]
                    if pen & 2:
                        db |= 1 << BIT1_FOR_PIXEL[i]
            data.append(db)
            mask.append(mb)
        return data, mask

    shifts_data, shifts_mask = [], []
    for s in range(4):
        d_rows, m_rows = [], []
        for y in range(th):
            line = [None] * span
            for x in range(tw):
                line[x + s] = grid[y][x]
            d, m = encode_row(line)
            d_rows.append(d)
            m_rows.append(m)
        shifts_data.append(d_rows)
        shifts_mask.append(m_rows)

    def emit(f, name, rows):
        f.write(f"{name}\n")
        for r in rows:
            f.write("                db    " + ",".join(f"#{b:02X}" for b in r) + "\n")

    # --platform msx2 (#287): a V9938 hardware-sprite cursor. Binary .SPR:
    #   +0 hotspot_x, +1 hotspot_y,
    #   +2..33  outline plane (pen-2/black pixels), 16x16 pattern layout
    #   +34..65 fill plane (pen-1/3 white/red pixels)
    # 16x16 pattern layout = 16 bytes left 8-px column (rows 0..15), then 16
    # bytes right column; bit7 = leftmost pixel of the column.
    if platform == 'msx2':
        def rows_of(pens):
            rows = [[0] * 16 for _ in range(16)]
            for y in range(min(th, 16)):
                for x in range(min(tw, 16)):
                    if grid[y][x] in pens:
                        rows[y][x] = 1
            return rows
        def pack(rows):
            blob = bytearray()
            for col in (0, 8):
                for y in range(16):
                    b = 0
                    for i in range(8):
                        if rows[y][col + i]:
                            b |= 0x80 >> i
                    blob.append(b)
            return blob
        fill = rows_of({1, 3})
        outline = rows_of({2})
        # If the art has no explicit outline pixels, synthesise one: the
        # 1-pixel dilated border of the fill, so the pointer stays visible
        # over light surfaces (a white arrow on the white top bar vanishes).
        if not any(any(r) for r in outline):
            for y in range(16):
                for x in range(16):
                    if fill[y][x]:
                        continue
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = y + dy, x + dx
                            if 0 <= ny < 16 and 0 <= nx < 16 and fill[ny][nx]:
                                outline[y][x] = 1
        blob = bytearray((hot[0], hot[1]))
        blob += pack(outline)       # outline plane (black, sprite 0)
        blob += pack(fill)          # fill plane (white, sprite 1)
        with open(out_asm, "wb") as f:
            f.write(blob)
        print(f"{in_png}: MSX2 sprite cursor -> {len(blob)} bytes "
              f"(2 planes), hotspot {hot}")
        return

    # --platform pcw (#331): the CPC's interleaved software-cursor .SPR, but in
    # Screen-6 packing (pixel i = 2-bit field at bits 7-2i..6-2i) with the data
    # already permuted to CGA2 hardware pens (the composite writes raw bytes):
    # GB pen 1 white -> 3, pen 2 black -> 0, pen 3 red -> 2. Masks are 11-per-
    # transparent-field. Same 2-phase (shift 0/2) interleaved layout and size.
    if platform == 'pcw':
        HW = {1: 3, 2: 0, 3: 2}
        def encode_row_pcw(pixels):
            data, mask = [], []
            for b in range(out_bytes):
                db = mb = 0
                for i in range(4):
                    x = b * 4 + i
                    pen = pixels[x] if x < span else None
                    sh = 6 - 2 * i
                    if pen is None:
                        mb |= 3 << sh
                    else:
                        db |= HW[pen] << sh
                data.append(db)
                mask.append(mb)
            return data, mask
        shifts_data, shifts_mask = [], []
        for s in range(4):
            d_rows, m_rows = [], []
            for y in range(th):
                line = [None] * span
                for x in range(tw):
                    line[x + s] = grid[y][x]
                d, m = encode_row_pcw(line)
                d_rows.append(d)
                m_rows.append(m)
            shifts_data.append(d_rows)
            shifts_mask.append(m_rows)
        blob = bytearray()
        for s in (0, 2):
            for y in range(th):
                for b in range(out_bytes):
                    blob += bytes((shifts_mask[s][y][b], shifts_data[s][y][b]))
        with open(out_asm, "wb") as f:
            f.write(blob)
        print(f"{in_png}: PCW cursor .SPR {tw}x{th} -> {len(blob)} bytes "
              f"(2 interleaved phases, CGA2), hotspot {hot}")
        return

    # .SPR binary mode (#65): the kernel loads a cursor as a disk file into low RAM and
    # composites it with  screen = (bg AND mask) OR data, reading one advancing pointer
    # (lib/cursor.asm cc_col: `and (hl)` / `inc hl` / `or (hl)`). So mask and data must
    # be INTERLEAVED per byte (mask,data,mask,data...), with the 2 pre-shifted phases
    # (shift 0 then shift 2) laid out back to back - exactly like lib/cursor_data.asm
    # (-> DEFAULT.SPR). The old d0,m0,d2,m2 BLOCK order garbled every png2spr cursor.
    if out_asm.lower().endswith(".spr"):
        blob = bytearray()
        for s in (0, 2):                         # phase0 (shift 0) then phase2 (shift 2)
            for y in range(th):
                for b in range(out_bytes):       # interleave mask,data per byte column
                    blob += bytes((shifts_mask[s][y][b], shifts_data[s][y][b]))
        with open(out_asm, "wb") as f:
            f.write(blob)
        print(f"{in_png}: cursor .SPR {tw}x{th} -> {len(blob)} bytes "
              f"(2 interleaved phases), hotspot {hot}, label {label}")
        return

    with open(out_asm, "w") as f:
        f.write(f"; generated by png2spr from {in_png} ({tw}x{th}, hotspot {hot})\n")
        f.write(f"{label}_w        equ   {out_bytes}\n")
        f.write(f"{label}_h        equ   {th}\n")
        f.write(f"{label}_hx       equ   {hot[0]}\n")
        f.write(f"{label}_hy       equ   {hot[1]}\n")
        f.write(f"{label}_data     dw    {label}_d0,{label}_d1,{label}_d2,{label}_d3\n")
        f.write(f"{label}_mask     dw    {label}_m0,{label}_m1,{label}_m2,{label}_m3\n")
        for s in range(4):
            emit(f, f"{label}_d{s}", shifts_data[s])
            emit(f, f"{label}_m{s}", shifts_mask[s])

    print(f"{in_png}: sprite {tw}x{th} -> {out_bytes}x{th} bytes/shift, "
          f"hotspot {hot}, label {label}")


if __name__ == "__main__":
    main()
