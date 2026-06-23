#!/usr/bin/env python3
"""patternedit - a tkinter editor for GEOBENCH desktop backdrop tiles (.BDP).

A backdrop is a 16x16 Mode-1 tile the desktop repeats behind the icons + windows
(the GEOS/Workbench dither look), selected via GEOBENCH.CFG's BACKDROP= key. This
edits one tile in the 4 desktop pens and - crucially - shows a LIVE TILED PREVIEW
(the tile repeated, with a wrap seam marker) so you can see at a glance whether the
pattern repeats seamlessly, which a single-cell view can't.

  * left-click / drag : paint with the selected pen
  * right-click / drag : paint pen 0 (paper / erase)
  * File: New, Open .BDP, Import .png (any size -> nearest-pen 16x16), Save .BDP,
          Export .png

.BDP format (matches tools/png2backdrop.py and the kernel loader): raw 64 bytes,
16 rows x 4 Mode-1 bytes (4 px/byte), no header.

    python3 tools/patternedit.py [file.BDP]
"""
import sys
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

TILE = 16
WB = TILE // 4                       # 4 Mode-1 bytes per row
PEN_RGB = ["#0000aa", "#ffffff", "#000000", "#ff0000"]   # blue paper / white / black / red
PEN_NAME = ["Paper (blue)", "White", "Black", "Red"]
BIT0 = (7, 6, 5, 4)                  # Mode-1: pen bit0 of pixel i
BIT1 = (3, 2, 1, 0)                  # Mode-1: pen bit1 of pixel i

CELL = 26                            # editor zoom (px per tile pixel)
PV_CELL = 7                          # tiled-preview zoom
PV_TILES = 4                         # tiled-preview repeats each way


# --- .BDP encode / decode ---------------------------------------------------
def decode_bdp(data):
    grid = [[0] * TILE for _ in range(TILE)]
    for y in range(TILE):
        for bx in range(WB):
            byte = data[y * WB + bx]
            for i in range(4):
                grid[y][bx * 4 + i] = ((byte >> BIT0[i]) & 1) | (((byte >> BIT1[i]) & 1) << 1)
    return grid


def encode_bdp(grid):
    out = bytearray()
    for y in range(TILE):
        for bx in range(WB):
            b = 0
            for i in range(4):
                pen = grid[y][bx * 4 + i]
                if pen & 1:
                    b |= 1 << BIT0[i]
                if pen & 2:
                    b |= 1 << BIT1[i]
            out.append(b)
    return bytes(out)


def nearest_pen(rgb):
    pal = [(0, 0, 170), (255, 255, 255), (0, 0, 0), (255, 0, 0)]
    best, bd = 0, None
    for pen, (r, g, b) in enumerate(pal):
        d = (r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2
        if bd is None or d < bd:
            best, bd = pen, d
    return best


class PatternEditor(tk.Tk):
    def __init__(self, path=None):
        super().__init__()
        self.title("GEOBENCH pattern editor")
        self.grid_data = [[0] * TILE for _ in range(TILE)]
        self.path = None
        self.pen = tk.IntVar(value=2)
        self.cell_ids = None
        self.pv_ids = None
        self._build()
        self._init_items()
        if path:
            self.load_bdp(path)
        self._redraw()

    def _build(self):
        bar = ttk.Frame(self, padding=6)
        bar.pack(side="top", fill="x")
        ttk.Button(bar, text="New", command=self.new).pack(side="left")
        ttk.Button(bar, text="Open .BDP", command=self.open_bdp).pack(side="left", padx=2)
        ttk.Button(bar, text="Import .png", command=self.import_png).pack(side="left", padx=2)
        ttk.Button(bar, text="Save .BDP", command=self.save_bdp).pack(side="left", padx=2)
        ttk.Button(bar, text="Export .png", command=self.export_png).pack(side="left", padx=2)

        pens = ttk.Frame(bar)
        pens.pack(side="right")
        ttk.Label(pens, text="Pen:").pack(side="left")
        for p in range(4):
            tk.Radiobutton(pens, text=PEN_NAME[p], variable=self.pen, value=p,
                           indicatoron=False, width=11, bg=PEN_RGB[p],
                           fg=("#000" if p in (1,) else "#fff"),
                           selectcolor=PEN_RGB[p]).pack(side="left", padx=1)

        main = ttk.Frame(self, padding=6)
        main.pack(side="top", fill="both", expand=True)

        left = ttk.Frame(main)
        left.pack(side="left")
        ttk.Label(left, text="Tile (16x16)").pack()
        self.canvas = tk.Canvas(left, width=TILE * CELL, height=TILE * CELL,
                                highlightthickness=1, highlightbackground="#888")
        self.canvas.pack()
        self.canvas.bind("<Button-1>", lambda e: self._paint(e, self.pen.get()))
        self.canvas.bind("<B1-Motion>", lambda e: self._paint(e, self.pen.get()))
        self.canvas.bind("<Button-3>", lambda e: self._paint(e, 0))
        self.canvas.bind("<B3-Motion>", lambda e: self._paint(e, 0))

        right = ttk.Frame(main)
        right.pack(side="left", padx=12)
        ttk.Label(right, text="Tiled preview (seams marked)").pack()
        self.preview = tk.Canvas(right, width=TILE * PV_TILES * PV_CELL,
                                 height=TILE * PV_TILES * PV_CELL,
                                 highlightthickness=1, highlightbackground="#888")
        self.preview.pack()
        self.status = ttk.Label(right, text="")
        self.status.pack(anchor="w", pady=4)

    # --- canvas items (created ONCE; painting only itemconfig's the changed cell) ----
    def _init_items(self):
        self.cell_ids = [[self.canvas.create_rectangle(
            x * CELL, y * CELL, (x + 1) * CELL, (y + 1) * CELL,
            fill=PEN_RGB[0], outline="#444") for x in range(TILE)] for y in range(TILE)]
        n = TILE * PV_TILES
        self.pv_ids = [[self.preview.create_rectangle(
            X * PV_CELL, Y * PV_CELL, (X + 1) * PV_CELL, (Y + 1) * PV_CELL,
            fill=PEN_RGB[0], outline="") for X in range(n)] for Y in range(n)]
        for t in range(1, PV_TILES):                     # tile-boundary seam guides (drawn last = on top)
            self.preview.create_line(t * TILE * PV_CELL, 0, t * TILE * PV_CELL, n * PV_CELL, fill="#0f0")
            self.preview.create_line(0, t * TILE * PV_CELL, n * PV_CELL, t * TILE * PV_CELL, fill="#0f0")

    def _set_cell(self, x, y, pen):
        col = PEN_RGB[pen]
        self.canvas.itemconfig(self.cell_ids[y][x], fill=col)
        for ty in range(PV_TILES):                       # update this cell's copies in every tiled repeat
            for tx in range(PV_TILES):
                self.preview.itemconfig(self.pv_ids[ty * TILE + y][tx * TILE + x], fill=col)

    # --- painting -----------------------------------------------------------
    def _paint(self, e, pen):
        x, y = int(e.x) // CELL, int(e.y) // CELL
        if 0 <= x < TILE and 0 <= y < TILE and self.grid_data[y][x] != pen:
            self.grid_data[y][x] = pen
            self._set_cell(x, y, pen)

    def _redraw(self):                                   # full refresh after New / Open / Import
        for y in range(TILE):
            for x in range(TILE):
                self._set_cell(x, y, self.grid_data[y][x])
        self.status.config(text=(self.path or "(unsaved)"))

    # --- file ---------------------------------------------------------------
    def new(self):
        self.grid_data = [[0] * TILE for _ in range(TILE)]
        self.path = None
        self._redraw()

    def load_bdp(self, path):
        data = open(path, "rb").read()
        if len(data) != WB * TILE:
            messagebox.showerror("Open .BDP", f"{path}: expected {WB*TILE} bytes, got {len(data)}")
            return
        self.grid_data = decode_bdp(data)
        self.path = path

    def open_bdp(self):
        f = filedialog.askopenfilename(filetypes=[("Backdrop tile", "*.BDP *.bdp")])
        if f:
            self.load_bdp(f)
            self._redraw()

    def import_png(self):
        f = filedialog.askopenfilename(filetypes=[("PNG", "*.png")])
        if not f:
            return
        try:
            from PIL import Image
        except ImportError:
            messagebox.showerror("Import", "Pillow (PIL) is required to import PNGs.")
            return
        img = Image.open(f).convert("RGB").resize((TILE, TILE), Image.NEAREST)
        px = img.load()
        self.grid_data = [[nearest_pen(px[x, y]) for x in range(TILE)] for y in range(TILE)]
        self.path = None
        self._redraw()

    def save_bdp(self):
        f = self.path if (self.path and self.path.lower().endswith(".bdp")) else \
            filedialog.asksaveasfilename(defaultextension=".BDP",
                                         filetypes=[("Backdrop tile", "*.BDP")])
        if not f:
            return
        open(f, "wb").write(encode_bdp(self.grid_data))
        self.path = f
        self._redraw()

    def export_png(self):
        try:
            from PIL import Image
        except ImportError:
            messagebox.showerror("Export", "Pillow (PIL) is required to export PNGs.")
            return
        f = filedialog.asksaveasfilename(defaultextension=".png", filetypes=[("PNG", "*.png")])
        if not f:
            return
        pal = [(0, 0, 170), (255, 255, 255), (0, 0, 0), (255, 0, 0)]
        img = Image.new("RGB", (TILE, TILE))
        for y in range(TILE):
            for x in range(TILE):
                img.putpixel((x, y), pal[self.grid_data[y][x]])
        img.save(f)


if __name__ == "__main__":
    PatternEditor(sys.argv[1] if len(sys.argv) > 1 else None).mainloop()
