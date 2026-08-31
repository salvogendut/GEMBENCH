#!/usr/bin/env python3
"""picconv - convert an image into a GEOBENCH 4- or 16-colour .PIC.

A tkinter GUI (like tools/iconedit.py) AND a CLI. Four-colour output remains the
portable canonical Mode-1 format used by every target. Sixteen-colour output uses
the MSX Screen-7 palette and linear 4bpp packing (two pixels per byte). Both modes
optionally dither photos and snap width to a multiple of four. Width and height
can be supplied independently; leaving either one unspecified preserves the
source aspect ratio:

    "GBPC" | ver=2 | mode=1/7 | width_px(2 LE) | height_px(2 LE) | inks[4] | bitmap

    pen 0  blue   #000080   CPC ink 1
    pen 1  white  #FFFFFF   CPC ink 26
    pen 2  black  #000000   CPC ink 0
    pen 3  red    #FF0000   CPC ink 6

Usage:
    tools/picconv.py                         # launch the GUI
    tools/picconv.py photo.jpg out.PIC       # convert (CLI), Floyd-Steinberg
    tools/picconv.py in.png out.PIC -d none -w 160
    tools/picconv.py in.png out.PIC -c 16 -w 200 --height 255
"""
import sys
import os
import struct
import tempfile
from PIL import Image

# pen -> display RGB and the CPC hardware ink stored in the .PIC palette.
PAL_RGB = [(0x00, 0x00, 0x80), (0xFF, 0xFF, 0xFF), (0x00, 0x00, 0x00), (0xFF, 0x00, 0x00)]
INKS = [1, 26, 0, 6]

# Screen-7 entries 4..15 are fixed by lib/msx/screen7.asm. The first four remain
# the configurable GEOBENCH UI pens; this default palette matches a stock setup.
MID = 146  # V9938 channel level 4/7, rounded to RGB8
CPC_RGB = [
    (0, 0, 0),       (0, 0, MID),     (0, 0, 255),
    (MID, 0, 0),     (MID, 0, MID),   (MID, 0, 255),
    (255, 0, 0),     (255, 0, MID),   (255, 0, 255),
    (0, MID, 0),     (0, MID, MID),   (0, MID, 255),
    (MID, MID, 0),   (MID, MID, MID), (MID, MID, 255),
    (255, MID, 0),   (255, MID, MID), (255, MID, 255),
    (0, 255, 0),     (0, 255, MID),   (0, 255, 255),
    (MID, 255, 0),   (MID, 255, MID), (MID, 255, 255),
    (255, 255, 0),   (255, 255, MID), (255, 255, 255),
]
PAL16_INKS = INKS + [18, 2, 24, 8, 20, 15, 16, 11, 21, 5, 13, 22]
PAL16_RGB = [CPC_RGB[ink] for ink in PAL16_INKS]
BIT0_FOR_PIXEL = (7, 6, 5, 4)        # Mode-1: pen bit0 of the 4 pixels in a byte
BIT1_FOR_PIXEL = (3, 2, 1, 0)        # ... pen bit1
DITHERS = ("floyd", "atkinson", "ordered", "none")
MODE_4COLOUR = 1
MODE_SCREEN7 = 7
SCREEN7_MAX_W = 512
SCREEN7_MAX_H = 255

_BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def nearest(r, g, b, palette=PAL_RGB):
    best, best_d = 0, None
    for pen, (pr, pg, pb) in enumerate(palette):
        d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2
        if best_d is None or d < best_d:
            best, best_d = pen, d
    return best


def _clamp(v):
    return 0 if v < 0 else 255 if v > 255 else v


def quantize(img, dither, palette=PAL_RGB):
    """RGB PIL image -> 2D list of pen indices (height x width)."""
    w, h = img.size
    px = img.load()
    if dither == "none":
        return [[nearest(*px[x, y], palette) for x in range(w)] for y in range(h)]
    if dither == "ordered":
        out = [[0] * w for _ in range(h)]
        for y in range(h):
            for x in range(w):
                o = (_BAYER4[y & 3][x & 3] / 15.0 - 0.5) * 64
                r, g, b = px[x, y]
                out[y][x] = nearest(_clamp(r + o), _clamp(g + o), _clamp(b + o), palette)
        return out
    # error-diffusion (Floyd-Steinberg or Atkinson)
    r = [[float(px[x, y][0]) for x in range(w)] for y in range(h)]
    g = [[float(px[x, y][1]) for x in range(w)] for y in range(h)]
    b = [[float(px[x, y][2]) for x in range(w)] for y in range(h)]
    out = [[0] * w for _ in range(h)]
    if dither == "atkinson":
        taps, denom = [(1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)], 8
    else:
        taps, denom = [(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)], 16
    for y in range(h):
        for x in range(w):
            rv, gv, bv = _clamp(r[y][x]), _clamp(g[y][x]), _clamp(b[y][x])
            pen = nearest(rv, gv, bv, palette)
            out[y][x] = pen
            er, eg, eb = rv - palette[pen][0], gv - palette[pen][1], bv - palette[pen][2]
            for tap in taps:
                dx, dy = tap[0], tap[1]
                wgt = (tap[2] if len(tap) == 3 else 1) / denom
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    r[ny][nx] += er * wgt
                    g[ny][nx] += eg * wgt
                    b[ny][nx] += eb * wgt
    return out


def pack(pens):
    """2D pens -> Mode-1 bytes (row-major, 4 px per byte)."""
    h = len(pens)
    w = len(pens[0]) if h else 0
    wb = w // 4
    data = bytearray()
    for y in range(h):
        for bx in range(wb):
            byte = 0
            for i in range(4):
                p = pens[y][bx * 4 + i]
                if p & 1:
                    byte |= 1 << BIT0_FOR_PIXEL[i]
                if p & 2:
                    byte |= 1 << BIT1_FOR_PIXEL[i]
            data.append(byte)
    return bytes(data)


def pack16(pens):
    """2D palette indices -> linear 4bpp bytes (high nibble first)."""
    h = len(pens)
    w = len(pens[0]) if h else 0
    data = bytearray()
    for y in range(h):
        for x in range(0, w, 2):
            data.append((pens[y][x] << 4) | pens[y][x + 1])
    return bytes(data)


def prepare(img, width=0, height=0):
    """Resize an RGB image.

    A zero dimension is inferred from the other one while preserving aspect
    ratio. If both are zero, the source width is retained. Supplying both uses
    the requested dimensions. Width is always snapped down to a multiple of
    four for the common GBPC row layout.
    """
    if width < 0 or height < 0:
        raise ValueError("picture dimensions cannot be negative")
    sw, sh = img.size
    if width:
        out_w = max(4, (width // 4) * 4)
        out_h = height if height else max(1, round(out_w * sh / sw))
    elif height:
        out_h = height
        inferred_w = max(4, round(out_h * sw / sh))
        out_w = max(4, (inferred_w // 4) * 4)
    else:
        out_w = max(4, (sw // 4) * 4)
        out_h = max(1, round(out_w * sh / sw))
    if out_h < 1:
        raise ValueError("picture height must be positive")
    return img.resize((out_w, out_h), Image.LANCZOS)


def save_pic(path, pens, w, h, colors=4, inks=INKS):
    if colors not in (4, 16):
        raise ValueError("colors must be 4 or 16")
    if w < 4 or w % 4:
        raise ValueError("picture width must be a positive multiple of four")
    if h < 1:
        raise ValueError("picture height must be positive")
    if colors == 16 and (w > SCREEN7_MAX_W or h > SCREEN7_MAX_H):
        raise ValueError(
            f"16-color pictures are limited to {SCREEN7_MAX_W}x{SCREEN7_MAX_H}")
    mode = MODE_SCREEN7 if colors == 16 else MODE_4COLOUR
    hdr = b"GBPC" + bytes([2, mode]) + struct.pack("<HH", w, h) + bytes(inks)
    with open(path, "wb") as f:
        f.write(hdr)
        f.write(pack16(pens) if colors == 16 else pack(pens))


def convert_file(in_png, out_pic, dither, width=0, height=0, colors=4):
    img = Image.open(in_png).convert("RGB")
    img = prepare(img, width, height)
    palette = PAL16_RGB if colors == 16 else PAL_RGB
    pens = quantize(img, dither, palette)
    w, h = img.size
    save_pic(out_pic, pens, w, h, colors, INKS)
    return w, h


# --------------------------------------------------------------------------- GUI
def run_gui(initial=None):
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    class PicConv(tk.Tk):
        def __init__(self):
            super().__init__()
            self.title("picconv - PNG to .PIC")
            self.src = None             # source RGB image
            self.pens = None            # last conversion
            self.preview_img = None     # keep a ref so Tk doesn't GC it
            self._tmp = None

            bar = ttk.Frame(self, padding=6)
            bar.pack(fill="x")
            ttk.Button(bar, text="Open PNG…", command=self.open_png).pack(side="left")
            ttk.Button(bar, text="Save .PIC…", command=self.save_pic).pack(side="left", padx=(4, 12))
            ttk.Label(bar, text="Dither:").pack(side="left")
            self.dither = tk.StringVar(value="floyd")
            cb = ttk.Combobox(bar, textvariable=self.dither, values=DITHERS, width=9, state="readonly")
            cb.pack(side="left", padx=(2, 12))
            cb.bind("<<ComboboxSelected>>", lambda e: self.reconvert())
            ttk.Label(bar, text="Colors:").pack(side="left")
            self.colors = tk.StringVar(value="4")
            cc = ttk.Combobox(bar, textvariable=self.colors, values=("4", "16"),
                              width=3, state="readonly")
            cc.pack(side="left", padx=(2, 12))
            cc.bind("<<ComboboxSelected>>", lambda e: self.reconvert())
            ttk.Label(bar, text="Width:").pack(side="left")
            self.width = tk.StringVar(value="160")
            we = ttk.Entry(bar, textvariable=self.width, width=5)
            we.pack(side="left", padx=2)
            we.bind("<Return>", lambda e: self.reconvert())
            ttk.Label(bar, text="Height:").pack(side="left", padx=(6, 0))
            self.height = tk.StringVar(value="")
            he = ttk.Entry(bar, textvariable=self.height, width=5)
            he.pack(side="left", padx=2)
            he.bind("<Return>", lambda e: self.reconvert())
            ttk.Button(bar, text="Convert", command=self.reconvert).pack(side="left", padx=(4, 0))

            self.canvas = tk.Canvas(self, width=480, height=360, bg="#202028", highlightthickness=0)
            self.canvas.pack(padx=6, pady=(0, 6))
            self.status = ttk.Label(self, text="Open a PNG to begin.", anchor="w", padding=(6, 2))
            self.status.pack(fill="x")
            if initial:
                self.load(initial)

        def open_png(self):
            p = filedialog.askopenfilename(filetypes=[
                ("Images", "*.png *.jpg *.jpeg *.gif *.bmp"), ("All", "*")])
            if p:
                self.load(p)

        def load(self, path):
            try:
                self.src = Image.open(path).convert("RGB")
            except Exception as e:
                messagebox.showerror("picconv", f"Could not open:\n{e}")
                return
            self.title(f"picconv - {os.path.basename(path)}")
            if self.width.get().strip() in ("", "160"):
                self.width.set(str(min(320, self.src.size[0])))
            self.reconvert()

        def reconvert(self):
            if self.src is None:
                return
            try:
                width_text = self.width.get().strip()
                height_text = self.height.get().strip()
                w = int(width_text) if width_text else 0
                h = int(height_text) if height_text else 0
                if w < 0 or h < 0:
                    raise ValueError
            except ValueError:
                self.status.config(text="Width and height must be positive numbers or blank.")
                return
            img = prepare(self.src, w, h)
            colors = int(self.colors.get())
            palette = PAL16_RGB if colors == 16 else PAL_RGB
            self.pens = quantize(img, self.dither.get(), palette)
            self.pw, self.ph = img.size
            self.show()
            stride = self.pw // (2 if colors == 16 else 4)
            limit = "   (Screen 7 max 512x255)" if colors == 16 else ""
            self.status.config(text=f"{self.pw}x{self.ph} px  ->  "
                                     f"{stride * self.ph + 14} byte .PIC   "
                                     f"({colors} colors, {self.dither.get()}){limit}")

        def show(self):
            palette = PAL16_RGB if int(self.colors.get()) == 16 else PAL_RGB
            prev = Image.new("RGB", (self.pw, self.ph))
            prev.putdata([palette[self.pens[y][x]]
                          for y in range(self.ph) for x in range(self.pw)])
            scale = max(1, min(480 // self.pw, 360 // self.ph)) if self.pw and self.ph else 1
            prev = prev.resize((self.pw * scale, self.ph * scale), Image.NEAREST)
            if self._tmp is None:
                self._tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False).name
            prev.save(self._tmp)
            self.preview_img = tk.PhotoImage(file=self._tmp)        # Tk 8.6+ reads PNG
            self.canvas.delete("all")
            self.canvas.create_image(240, 180, image=self.preview_img)

        def save_pic(self):
            if self.pens is None:
                return
            p = filedialog.asksaveasfilename(defaultextension=".PIC",
                                             filetypes=[("GEOBENCH picture", "*.PIC"), ("All", "*")])
            if not p:
                return
            try:
                save_pic(p, self.pens, self.pw, self.ph, int(self.colors.get()))
            except ValueError as e:
                messagebox.showerror("picconv", str(e))
                return
            self.status.config(text=f"Saved {os.path.basename(p)}  ({self.pw}x{self.ph})")

        def destroy(self):
            if self._tmp and os.path.exists(self._tmp):
                try:
                    os.unlink(self._tmp)
                except OSError:
                    pass
            super().destroy()

    PicConv().mainloop()


def main():
    args = sys.argv[1:]
    if not args:
        run_gui()
        return
    # CLI
    import argparse
    p = argparse.ArgumentParser(description="Convert an image (PNG/JPG/...) to a GEOBENCH .PIC.")
    p.add_argument("in_img", help="source image (any format Pillow reads: PNG, JPG, GIF, BMP...)")
    p.add_argument("out_pic", nargs="?", help="defaults to in.<ext> -> in.PIC")
    p.add_argument("-d", "--dither", choices=DITHERS, default="floyd")
    p.add_argument("-w", "--width", type=int, default=0, help="target width (snapped x4); 0 = source width")
    p.add_argument("--height", type=int, default=0,
                   help="target height; 0 = preserve aspect ratio")
    p.add_argument("-c", "--colors", type=int, choices=(4, 16), default=4,
                   help="output palette size; 16 targets the MSX Screen-7 Viewer")
    p.add_argument("--gui", action="store_true", help="open the GUI on this file")
    a = p.parse_args(args)
    if a.gui:
        run_gui(a.in_img)
        return
    out = a.out_pic or os.path.splitext(a.in_img)[0] + ".PIC"
    try:
        w, h = convert_file(a.in_img, out, a.dither, a.width, a.height, a.colors)
    except ValueError as e:
        p.error(str(e))
    stride = w // (2 if a.colors == 16 else 4)
    print(f"{a.in_img}: {w}x{h} -> {out}  "
          f"({a.colors} colors, {a.dither}, {stride * h + 14} bytes)")


if __name__ == "__main__":
    main()
