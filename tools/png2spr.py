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
    if len(sys.argv) not in (4, 5):
        print(__doc__)
        sys.exit(2)
    in_png, out_asm, label = sys.argv[1], sys.argv[2], sys.argv[3]
    tw, th = (int(v) for v in (sys.argv[4].lower().split("x") if len(sys.argv) == 5
                               else ("12", "16")))

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
