#!/usr/bin/env python3
"""iconedit - Tk editor for GEOBENCH .IST icon sets and .SPR cursor sprites.

Edits Amstrad CPC Mode 1 bitmaps (4 colours, 4 pixels per byte) byte-for-byte
compatible with tools/packicons.py and tools/png2spr.py — see
tools/test_iconed_codec.py for the encoding rules.

  * .IST  v2 icon set: header(16) + dir(count*4: off u16le, w_bytes u8, h u8)
          + bitmaps. Each icon keeps its own size; mixed sizes are allowed.
  * .SPR  cursor sprite: 256 bytes = 4 phases of 4x16 bytes (d0, m0, d2, m2).
          We edit a single 16x16 logical grid (pen 0 = transparent) and
          regenerate d0/m0/d2/m2 on save (d2/m2 are the +2 px pre-shift).

Run:
    python3 tools/iconedit.py [file.IST | file.SPR]
"""
import os
import struct
import sys
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

# --- Mode 1 pixel packing (matches png2spr / png2cpc) -----------------------

def decode_pixel(b, i):
    return ((b >> (7 - i)) & 1) | (((b >> (3 - i)) & 1) << 1)

def set_pixel(b, i, pen):
    if pen & 1:
        b |= 1 << (7 - i)
    if pen & 2:
        b |= 1 << (3 - i)
    return b

def decode_icon(data, off, wbytes, h):
    grid = [[0] * (wbytes * 4) for _ in range(h)]
    for y in range(h):
        for bx in range(wbytes):
            b = data[off + y * wbytes + bx]
            for i in range(4):
                grid[y][bx * 4 + i] = decode_pixel(b, i)
    return grid

def encode_icon(grid, wbytes, h):
    out = bytearray(wbytes * h)
    for y in range(h):
        for bx in range(wbytes):
            b = 0
            for i in range(4):
                b = set_pixel(b, i, grid[y][bx * 4 + i])
            out[y * wbytes + bx] = b
    return bytes(out)

# --- .SPR cursor (16x16, file = d0 m0 d2 m2) --------------------------------

CUR_W = 4         # bytes
CUR_H = 16
PHASE = CUR_W * CUR_H   # 64

def decode_cursor_phase0(data):
    """Return a 16x16 grid where 0 = transparent, 1..3 = pen."""
    grid = [[0] * (CUR_W * 4) for _ in range(CUR_H)]
    for y in range(CUR_H):
        for bx in range(CUR_W):
            d = data[y * CUR_W + bx]
            m = data[PHASE + y * CUR_W + bx]
            for i in range(4):
                if (m >> (7 - i)) & 1:
                    grid[y][bx * 4 + i] = 0
                else:
                    grid[y][bx * 4 + i] = decode_pixel(d, i)
    return grid

def encode_cursor_phase(grid, shift):
    dout = bytearray(PHASE)
    mout = bytearray(PHASE)
    for y in range(CUR_H):
        for bx in range(CUR_W):
            d = m = 0
            for i in range(4):
                x = bx * 4 + i - shift
                pen = grid[y][x] if 0 <= x < CUR_W * 4 else 0
                if pen == 0:
                    m = set_pixel(m, i, 3)
                else:
                    d = set_pixel(d, i, pen)
            dout[y * CUR_W + bx] = d
            mout[y * CUR_W + bx] = m
    return bytes(dout), bytes(mout)

def encode_cursor_file(grid):
    d0, m0 = encode_cursor_phase(grid, 0)
    d2, m2 = encode_cursor_phase(grid, 2)
    return d0 + m0 + d2 + m2

# --- .IST set load/save -----------------------------------------------------

def load_ist(path):
    data = open(path, "rb").read()
    if data[:4] != b"GBIS":
        raise ValueError(f"{path}: not a GBIS icon set")
    if data[4] != 2:
        raise ValueError(f"{path}: unsupported version {data[4]} (expected 2)")
    count = data[5]
    icons = []
    for k in range(count):
        off, wbytes, h = struct.unpack_from("<HBB", data, 16 + k * 4)
        icons.append({
            "w": wbytes,
            "h": h,
            "grid": decode_icon(data, off, wbytes, h),
        })
    return icons

def save_ist(path, icons):
    n = len(icons)
    header = bytearray(16)
    header[0:4] = b"GBIS"
    header[4] = 2
    header[5] = n
    directory = bytearray()
    blob = bytearray()
    off = 16 + n * 4
    for ic in icons:
        directory += struct.pack("<HBB", off, ic["w"], ic["h"])
        bm = encode_icon(ic["grid"], ic["w"], ic["h"])
        blob += bm
        off += len(bm)
    with open(path, "wb") as f:
        f.write(header)
        f.write(directory)
        f.write(blob)

# --- palette ----------------------------------------------------------------

PEN_RGB = ["#000080", "#ffffff", "#000000", "#ff0000"]
PEN_NAME = ["blue", "white", "black", "red"]
GRID_LINE = "#404060"
CHECKER_A = "#bdbdbd"
CHECKER_B = "#8a8a8a"

# Real-size preview inset (lower-right): one icon pixel -> PREVIEW_SCALE screen px,
# so you see the final effect while editing the zoomed grid.
PREVIEW_SCALE = 2
PREVIEW_MARGIN = 12

# ----------------------------------------------------------------------------

class IconEditor(tk.Tk):
    def __init__(self, path=None):
        super().__init__()
        self.title("GEOBENCH Icon Editor")
        self.geometry("900x640")

        self.icons = []         # list of {"w","h","grid"}
        self.path = None
        self.mode = None        # "IST" or "SPR"
        self.index = 0
        self.scale = 24
        self.preview_scale = PREVIEW_SCALE
        self.tool = tk.StringVar(value="pen")
        self.pen = tk.IntVar(value=2)
        self.fill = tk.BooleanVar(value=False)
        self.dirty = False
        self.undo_stack = []
        self.preview = None     # (tool, x0, y0, x1, y1) during a drag
        self.clipboard_icon = None   # {"w","h","grid"} copied by Edit > Copy Icon

        self._build_ui()
        self._bind_keys()

        if path:
            self.open_file(path)
        else:
            self._new_ist()

    # -- UI ------------------------------------------------------------------

    def _build_ui(self):
        menubar = tk.Menu(self)
        m_file = tk.Menu(menubar, tearoff=0)
        m_file.add_command(label="New IST...", command=self._new_ist)
        m_file.add_command(label="New SPR", command=self._new_spr)
        m_file.add_command(label="Open...", accelerator="Ctrl+O", command=self.open_dialog)
        m_file.add_command(label="Save", accelerator="Ctrl+S", command=self.save)
        m_file.add_command(label="Save As...", command=self.save_as)
        m_file.add_separator()
        m_file.add_command(label="Quit", command=self.destroy)
        menubar.add_cascade(label="File", menu=m_file)

        m_icon = tk.Menu(menubar, tearoff=0)
        m_icon.add_command(label="Clear current", command=self.clear_current)
        m_icon.add_command(label="Add icon (IST)...", command=self.add_icon)
        m_icon.add_command(label="Delete icon (IST)", command=self.delete_icon)
        menubar.add_cascade(label="Icon", menu=m_icon)

        m_edit = tk.Menu(menubar, tearoff=0)
        m_edit.add_command(label="Undo", accelerator="Ctrl+Z", command=self.undo)
        m_edit.add_separator()
        m_edit.add_command(label="Copy Icon", accelerator="Ctrl+C", command=self.copy_icon)
        m_edit.add_command(label="Paste Icon", accelerator="Ctrl+V", command=self.paste_icon)
        menubar.add_cascade(label="Edit", menu=m_edit)
        self.config(menu=menubar)

        root = ttk.Frame(self, padding=6)
        root.pack(fill="both", expand=True)

        # left: canvas + nav
        left = ttk.Frame(root)
        left.pack(side="left", fill="both", expand=True)

        self.canvas = tk.Canvas(left, bg="#222", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True, padx=4, pady=4)
        self.canvas.bind("<ButtonPress-1>", self._on_press)
        self.canvas.bind("<B1-Motion>", self._on_drag)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)
        self.canvas.bind("<Configure>", lambda e: self._redraw())

        nav = ttk.Frame(left)
        nav.pack(fill="x", padx=4, pady=(0, 4))
        ttk.Button(nav, text="<", width=3, command=self.prev_icon).pack(side="left")
        self.info_var = tk.StringVar(value="—")
        ttk.Label(nav, textvariable=self.info_var, anchor="center")\
            .pack(side="left", fill="x", expand=True)
        ttk.Button(nav, text=">", width=3, command=self.next_icon).pack(side="left")

        # right: toolbox
        right = ttk.Frame(root, padding=(8, 4))
        right.pack(side="right", fill="y")

        ttk.Label(right, text="Tools", font=("TkDefaultFont", 10, "bold"))\
            .pack(anchor="w")
        for label, val in [("Pen", "pen"), ("Square", "rect"),
                           ("Circle", "circle"), ("Delete", "erase")]:
            ttk.Radiobutton(right, text=label, value=val,
                            variable=self.tool).pack(anchor="w")
        ttk.Checkbutton(right, text="Filled", variable=self.fill)\
            .pack(anchor="w", pady=(2, 8))

        ttk.Label(right, text="Color", font=("TkDefaultFont", 10, "bold"))\
            .pack(anchor="w")
        self.swatches = []
        sw_frame = ttk.Frame(right)
        sw_frame.pack(anchor="w", pady=2)
        for p in range(4):
            sw = tk.Label(sw_frame, width=3, height=1, relief="raised",
                          bg=PEN_RGB[p], borderwidth=2)
            sw.grid(row=p // 2, column=p % 2, padx=2, pady=2)
            sw.bind("<Button-1>", lambda e, pen=p: self._select_pen(pen))
            self.swatches.append(sw)
        self.pen_label = ttk.Label(right, text="")
        self.pen_label.pack(anchor="w", pady=(4, 8))
        self._select_pen(self.pen.get())

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=4)
        ttk.Label(right, text="Zoom").pack(anchor="w")
        zoom = ttk.Frame(right)
        zoom.pack(anchor="w")
        ttk.Button(zoom, text="-", width=2,
                   command=lambda: self._set_scale(self.scale - 4)).pack(side="left")
        ttk.Button(zoom, text="+", width=2,
                   command=lambda: self._set_scale(self.scale + 4)).pack(side="left")

        ttk.Label(right, text="Preview size").pack(anchor="w", pady=(6, 0))
        pvz = ttk.Frame(right)
        pvz.pack(anchor="w")
        ttk.Button(pvz, text="-", width=2,
                   command=lambda: self._set_preview_scale(self.preview_scale - 1)).pack(side="left")
        ttk.Button(pvz, text="+", width=2,
                   command=lambda: self._set_preview_scale(self.preview_scale + 1)).pack(side="left")

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=4)
        self.status = ttk.Label(right, text="", foreground="#666", wraplength=120)
        self.status.pack(anchor="w")

    def _bind_keys(self):
        self.bind("<Control-s>", lambda e: self.save())
        self.bind("<Control-o>", lambda e: self.open_dialog())
        self.bind("<Control-z>", lambda e: self.undo())
        self.bind("<Control-c>", lambda e: self.copy_icon())
        self.bind("<Control-v>", lambda e: self.paste_icon())
        self.bind("<Left>",  lambda e: self.prev_icon())
        self.bind("<Right>", lambda e: self.next_icon())
        for k in "1234":
            self.bind(k, lambda e, p=int(k) - 1: self._select_pen(p))

    def _select_pen(self, p):
        self.pen.set(p)
        for i, sw in enumerate(self.swatches):
            sw.config(relief=("sunken" if i == p else "raised"))
        self.pen_label.config(text=f"Pen {p} ({PEN_NAME[p]})")

    def _set_scale(self, s):
        self.scale = max(4, min(48, s))
        self._redraw()

    def _set_preview_scale(self, s):
        self.preview_scale = max(1, min(10, s))
        self._redraw()

    # -- file ops ------------------------------------------------------------

    def _new_ist(self):
        self.icons = [{"w": 4, "h": 16, "grid": [[0] * 16 for _ in range(16)]}]
        self.path = None
        self.mode = "IST"
        self.index = 0
        self.dirty = False
        self.undo_stack.clear()
        self._refresh_title()
        self._redraw()

    def _new_spr(self):
        self.icons = [{"w": CUR_W, "h": CUR_H,
                       "grid": [[0] * (CUR_W * 4) for _ in range(CUR_H)]}]
        self.path = None
        self.mode = "SPR"
        self.index = 0
        self.dirty = False
        self.undo_stack.clear()
        self._refresh_title()
        self._redraw()

    def open_dialog(self):
        p = filedialog.askopenfilename(
            title="Open icon set or cursor",
            filetypes=[("Icon set / cursor", "*.IST *.ist *.SPR *.spr"),
                       ("All files", "*.*")])
        if p:
            self.open_file(p)

    def open_file(self, path):
        try:
            ext = os.path.splitext(path)[1].lower()
            if ext == ".ist":
                self.icons = load_ist(path)
                self.mode = "IST"
            elif ext == ".spr":
                data = open(path, "rb").read()
                if len(data) != 4 * PHASE:
                    raise ValueError(f"{path}: expected {4*PHASE} bytes, got {len(data)}")
                self.icons = [{"w": CUR_W, "h": CUR_H,
                               "grid": decode_cursor_phase0(data)}]
                self.mode = "SPR"
            else:
                raise ValueError(f"unknown extension: {ext}")
        except Exception as e:
            messagebox.showerror("Open failed", str(e))
            return
        self.path = path
        self.index = 0
        self.dirty = False
        self.undo_stack.clear()
        self._refresh_title()
        self._redraw()

    def save(self):
        if self.path is None:
            return self.save_as()
        try:
            if self.mode == "IST":
                save_ist(self.path, self.icons)
            else:
                with open(self.path, "wb") as f:
                    f.write(encode_cursor_file(self.icons[0]["grid"]))
        except Exception as e:
            messagebox.showerror("Save failed", str(e))
            return
        self.dirty = False
        self._refresh_title()
        self.status.config(text=f"Saved {os.path.basename(self.path)}")

    def save_as(self):
        default_ext = ".IST" if self.mode == "IST" else ".SPR"
        p = filedialog.asksaveasfilename(
            defaultextension=default_ext,
            filetypes=[("Icon set", "*.IST"), ("Cursor", "*.SPR")])
        if p:
            self.path = p
            self.save()

    # -- icon ops ------------------------------------------------------------

    def clear_current(self):
        ic = self._cur()
        if ic is None:
            return
        self._push_undo()
        for y in range(ic["h"]):
            for x in range(ic["w"] * 4):
                ic["grid"][y][x] = 0
        self._touched()

    def add_icon(self):
        if self.mode != "IST":
            messagebox.showinfo("Add icon", "Only IST files can hold multiple icons.")
            return
        dlg = tk.Toplevel(self)
        dlg.title("New icon size")
        ttk.Label(dlg, text="Width (px, multiple of 4):").grid(row=0, column=0, sticky="w")
        ttk.Label(dlg, text="Height (px):").grid(row=1, column=0, sticky="w")
        w_var = tk.StringVar(value="32")
        h_var = tk.StringVar(value="32")
        ttk.Entry(dlg, textvariable=w_var, width=6).grid(row=0, column=1)
        ttk.Entry(dlg, textvariable=h_var, width=6).grid(row=1, column=1)
        def ok():
            try:
                w = int(w_var.get()); h = int(h_var.get())
                if w <= 0 or h <= 0 or w % 4:
                    raise ValueError
            except ValueError:
                messagebox.showerror("Bad size", "Width must be a positive multiple of 4.")
                return
            self._push_undo()
            self.icons.append({"w": w // 4, "h": h,
                               "grid": [[0] * w for _ in range(h)]})
            self.index = len(self.icons) - 1
            dlg.destroy()
            self._touched()
        ttk.Button(dlg, text="OK", command=ok).grid(row=2, column=0, columnspan=2, pady=4)

    def delete_icon(self):
        if self.mode != "IST" or len(self.icons) <= 1:
            messagebox.showinfo("Delete icon", "Need at least one icon in the set.")
            return
        self._push_undo()
        del self.icons[self.index]
        self.index = min(self.index, len(self.icons) - 1)
        self._touched()

    def copy_icon(self):
        ic = self._cur()
        if ic is None:
            return
        self.clipboard_icon = {"w": ic["w"], "h": ic["h"],
                               "grid": [row[:] for row in ic["grid"]]}
        self.status.config(text=f"Copied {ic['w']*4}x{ic['h']} icon")

    def paste_icon(self):
        if self.clipboard_icon is None:
            messagebox.showinfo("Paste Icon", "Nothing copied yet.")
            return
        ic = self._cur()
        if ic is None:
            return
        cb = self.clipboard_icon
        self._push_undo()
        if self.mode == "SPR":
            # cursor is a fixed 16x16 grid: drop the copy in top-left, clipped
            for y in range(ic["h"]):
                for x in range(ic["w"] * 4):
                    inside = y < cb["h"] and x < cb["w"] * 4
                    ic["grid"][y][x] = cb["grid"][y][x] if inside else 0
        else:
            # IST icons keep their own size: replace this one wholesale
            ic["w"] = cb["w"]
            ic["h"] = cb["h"]
            ic["grid"] = [row[:] for row in cb["grid"]]
        self._touched()
        self.status.config(text=f"Pasted {cb['w']*4}x{cb['h']} icon")

    def prev_icon(self):
        if not self.icons:
            return
        self.index = (self.index - 1) % len(self.icons)
        self._redraw()

    def next_icon(self):
        if not self.icons:
            return
        self.index = (self.index + 1) % len(self.icons)
        self._redraw()

    # -- drawing -------------------------------------------------------------

    def _cur(self):
        return self.icons[self.index] if self.icons else None

    def _cell_at(self, sx, sy):
        ic = self._cur()
        if ic is None:
            return None
        ox, oy = self._origin(ic)
        x = (sx - ox) // self.scale
        y = (sy - oy) // self.scale
        if 0 <= x < ic["w"] * 4 and 0 <= y < ic["h"]:
            return int(x), int(y)
        return None

    def _origin(self, ic):
        cw = self.canvas.winfo_width()
        ch = self.canvas.winfo_height()
        gw = ic["w"] * 4 * self.scale
        gh = ic["h"] * self.scale
        return (cw - gw) // 2, (ch - gh) // 2

    def _on_press(self, ev):
        cell = self._cell_at(ev.x, ev.y)
        if cell is None:
            return
        self._push_undo()
        tool = self.tool.get()
        if tool in ("pen", "erase"):
            self._paint(cell[0], cell[1], 0 if tool == "erase" else self.pen.get())
            self.preview = (tool, cell[0], cell[1], cell[0], cell[1])
        else:
            self.preview = (tool, cell[0], cell[1], cell[0], cell[1])
            self._redraw()

    def _on_drag(self, ev):
        if self.preview is None:
            return
        cell = self._cell_at(ev.x, ev.y)
        if cell is None:
            ic = self._cur()
            x = max(0, min(ic["w"] * 4 - 1,
                           (ev.x - self._origin(ic)[0]) // self.scale))
            y = max(0, min(ic["h"] - 1,
                           (ev.y - self._origin(ic)[1]) // self.scale))
            cell = (int(x), int(y))
        tool, x0, y0, _, _ = self.preview
        if tool in ("pen", "erase"):
            pen = 0 if tool == "erase" else self.pen.get()
            self._line(x0, y0, cell[0], cell[1], pen)
            self.preview = (tool, cell[0], cell[1], cell[0], cell[1])
        else:
            self.preview = (tool, x0, y0, cell[0], cell[1])
            self._redraw()

    def _on_release(self, ev):
        if self.preview is None:
            return
        tool, x0, y0, x1, y1 = self.preview
        if tool == "rect":
            self._draw_rect(x0, y0, x1, y1, self.pen.get(), self.fill.get())
        elif tool == "circle":
            self._draw_ellipse(x0, y0, x1, y1, self.pen.get(), self.fill.get())
        self.preview = None
        self._touched()

    def _paint(self, x, y, pen):
        ic = self._cur()
        if 0 <= x < ic["w"] * 4 and 0 <= y < ic["h"]:
            if ic["grid"][y][x] != pen:
                ic["grid"][y][x] = pen
                self.dirty = True
                self._draw_cell(ic, x, y)
                self._draw_preview_cell(ic, x, y, self._preview_geom(ic))
                self._refresh_title()

    def _line(self, x0, y0, x1, y1, pen):
        # Bresenham
        dx = abs(x1 - x0); sx = 1 if x0 < x1 else -1
        dy = -abs(y1 - y0); sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self._paint(x0, y0, pen)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy; x0 += sx
            if e2 <= dx:
                err += dx; y0 += sy

    def _draw_rect(self, x0, y0, x1, y1, pen, fill):
        lo_x, hi_x = sorted((x0, x1))
        lo_y, hi_y = sorted((y0, y1))
        for y in range(lo_y, hi_y + 1):
            for x in range(lo_x, hi_x + 1):
                if fill or y in (lo_y, hi_y) or x in (lo_x, hi_x):
                    self._paint(x, y, pen)

    def _draw_ellipse(self, x0, y0, x1, y1, pen, fill):
        lo_x, hi_x = sorted((x0, x1))
        lo_y, hi_y = sorted((y0, y1))
        cx = (lo_x + hi_x) / 2.0
        cy = (lo_y + hi_y) / 2.0
        rx = max(0.5, (hi_x - lo_x) / 2.0)
        ry = max(0.5, (hi_y - lo_y) / 2.0)
        ic = self._cur()
        if fill:
            for y in range(lo_y, hi_y + 1):
                for x in range(lo_x, hi_x + 1):
                    if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                        self._paint(x, y, pen)
        else:
            painted = set()
            steps = int(2 * 3.14159 * max(rx, ry) * 4) + 8
            import math
            for i in range(steps):
                t = 2 * math.pi * i / steps
                px = int(round(cx + rx * math.cos(t)))
                py = int(round(cy + ry * math.sin(t)))
                if (px, py) not in painted:
                    painted.add((px, py))
                    self._paint(px, py, pen)

    def _push_undo(self):
        ic = self._cur()
        if ic is None:
            return
        snap = {"index": self.index,
                "icons": [{"w": i["w"], "h": i["h"],
                           "grid": [row[:] for row in i["grid"]]}
                          for i in self.icons]}
        self.undo_stack.append(snap)
        if len(self.undo_stack) > 40:
            self.undo_stack.pop(0)

    def undo(self):
        if not self.undo_stack:
            return
        snap = self.undo_stack.pop()
        self.icons = snap["icons"]
        self.index = min(snap["index"], len(self.icons) - 1)
        self.dirty = True
        self._refresh_title()
        self._redraw()

    def _touched(self):
        self.dirty = True
        self._refresh_title()
        self._redraw()

    # -- render --------------------------------------------------------------

    def _redraw(self):
        self.canvas.delete("all")
        ic = self._cur()
        if ic is None:
            self.info_var.set("—")
            return
        ox, oy = self._origin(ic)
        s = self.scale
        pw = ic["w"] * 4
        ph = ic["h"]
        # backdrop for transparent (SPR) or pen 0 cells
        for y in range(ph):
            for x in range(pw):
                self._draw_cell(ic, x, y)
        # grid lines
        for x in range(pw + 1):
            self.canvas.create_line(ox + x * s, oy, ox + x * s, oy + ph * s,
                                    fill=GRID_LINE)
        for y in range(ph + 1):
            self.canvas.create_line(ox, oy + y * s, ox + pw * s, oy + y * s,
                                    fill=GRID_LINE)
        # preview overlay for shape tools
        if self.preview is not None:
            tool, x0, y0, x1, y1 = self.preview
            if tool in ("rect", "circle"):
                lo_x, hi_x = sorted((x0, x1))
                lo_y, hi_y = sorted((y0, y1))
                rx = ox + lo_x * s
                ry = oy + lo_y * s
                rxe = ox + (hi_x + 1) * s
                rye = oy + (hi_y + 1) * s
                col = PEN_RGB[self.pen.get()]
                if tool == "rect":
                    self.canvas.create_rectangle(rx, ry, rxe, rye,
                                                 outline=col, width=2)
                else:
                    self.canvas.create_oval(rx, ry, rxe, rye,
                                            outline=col, width=2)
        self.info_var.set(self._info_text())
        self._draw_preview()

    def _draw_cell(self, ic, x, y):
        ox, oy = self._origin(ic)
        s = self.scale
        x0 = ox + x * s; y0 = oy + y * s
        x1 = x0 + s;     y1 = y0 + s
        pen = ic["grid"][y][x]
        if self.mode == "SPR" and pen == 0:
            # checkered background for transparency
            half = s // 2
            self.canvas.create_rectangle(x0, y0, x1, y1,
                                         fill=CHECKER_A, outline="")
            self.canvas.create_rectangle(x0 + half, y0, x1, y0 + half,
                                         fill=CHECKER_B, outline="")
            self.canvas.create_rectangle(x0, y0 + half, x0 + half, y1,
                                         fill=CHECKER_B, outline="")
        else:
            self.canvas.create_rectangle(x0, y0, x1, y1,
                                         fill=PEN_RGB[pen], outline="")

    # -- real-size preview inset (lower-right) --------------------------------

    def _preview_geom(self, ic):
        """(px0, py0, ps): top-left of the preview box + per-pixel scale."""
        cw = self.canvas.winfo_width()
        ch = self.canvas.winfo_height()
        ps = self.preview_scale
        bw = ic["w"] * 4 * ps
        bh = ic["h"] * ps
        px0 = max(PREVIEW_MARGIN, cw - PREVIEW_MARGIN - bw)
        py0 = max(PREVIEW_MARGIN + 8, ch - PREVIEW_MARGIN - bh)
        return px0, py0, ps

    def _draw_preview_cell(self, ic, x, y, geom):
        """Repaint a single preview pixel (lets pen strokes update live)."""
        px0, py0, ps = geom
        x0 = px0 + x * ps
        y0 = py0 + y * ps
        self.canvas.delete(f"pv_{x}_{y}")
        self.canvas.create_rectangle(x0, y0, x0 + ps, y0 + ps,
                                     fill=PEN_RGB[ic["grid"][y][x]], outline="",
                                     tags=("preview", f"pv_{x}_{y}"))

    def _draw_preview(self):
        """The whole preview box: a 1:N inset of the icon, so the final effect is
        visible while editing the zoomed grid. Pen 0 shows as the desktop blue."""
        self.canvas.delete("preview")
        ic = self._cur()
        if ic is None:
            return
        geom = self._preview_geom(ic)
        px0, py0, ps = geom
        pw, ph = ic["w"] * 4, ic["h"]
        bw, bh = pw * ps, ph * ps
        pad = 3
        self.canvas.create_rectangle(px0 - pad, py0 - pad,
                                     px0 + bw + pad, py0 + bh + pad,
                                     fill="#161616", outline="#888", width=1,
                                     tags="preview")
        self.canvas.create_text(px0 - pad, py0 - pad - 1,
                                text=f"preview {self.preview_scale}x",
                                anchor="sw", fill="#aaa",
                                font=("TkDefaultFont", 7), tags="preview")
        for y in range(ph):
            for x in range(pw):
                self._draw_preview_cell(ic, x, y, geom)

    def _info_text(self):
        ic = self._cur()
        if ic is None:
            return "—"
        kind = "cursor" if self.mode == "SPR" else "icon"
        return f"{kind} {self.index + 1}/{len(self.icons)}   {ic['w']*4}x{ic['h']} px"

    def _refresh_title(self):
        name = os.path.basename(self.path) if self.path else f"(untitled {self.mode or 'IST'})"
        mark = "*" if self.dirty else ""
        self.title(f"GEOBENCH Icon Editor — {mark}{name}")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else None
    app = IconEditor(path)
    app.mainloop()


if __name__ == "__main__":
    main()
