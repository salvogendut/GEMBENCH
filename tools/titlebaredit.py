#!/usr/bin/env python3
"""Edit and preview GEOBENCH tileable window title bars (.TBR).

A current .TBR is a headerless canonical Mode-1 theme: a 16x14 background tile
followed by reusable 8x10 close and 12x10 maximize gadget tiles. Four pixels
are packed per byte, for a total of 106 bytes. Legacy 56-byte background-only
files still open and receive the traditional gadgets when saved.

    python3 tools/titlebaredit.py [tile.TBR]
    python3 tools/titlebaredit.py --write-sample assets/titlebars/WEAVE.TBR
"""

import argparse
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk


TILE_W = 16
TILE_H = 14
ROW_BYTES = TILE_W // 4
TILE_BYTES = ROW_BYTES * TILE_H
CLOSE_W = 8
CLOSE_H = 10
CLOSE_BYTES = (CLOSE_W // 4) * CLOSE_H
MAX_W = 12
MAX_H = 10
MAX_BYTES = (MAX_W // 4) * MAX_H
THEME_BYTES = TILE_BYTES + CLOSE_BYTES + MAX_BYTES

PEN_RGB = ("#0000aa", "#ffffff", "#000000", "#ff0000")
PEN_NAME = ("Paper", "White", "Black", "Red")
BIT0 = (7, 6, 5, 4)
BIT1 = (3, 2, 1, 0)

CELL = 24
GADGET_CELL = 18
PREVIEW_W = 620
PREVIEW_H = 360


def decode_grid(data: bytes, width: int, height: int) -> list[list[int]]:
    """Decode one canonical Mode-1 grid with a four-pixel-aligned width."""
    row_bytes = width // 4
    expected = row_bytes * height
    if width % 4 or len(data) != expected:
        raise ValueError(f"expected {expected} bytes for {width}x{height}, got {len(data)}")
    grid = [[0] * width for _ in range(height)]
    for y in range(height):
        for bx in range(row_bytes):
            value = data[y * row_bytes + bx]
            for pixel in range(4):
                grid[y][bx * 4 + pixel] = (
                    ((value >> BIT0[pixel]) & 1)
                    | (((value >> BIT1[pixel]) & 1) << 1)
                )
    return grid


def encode_grid(grid: list[list[int]], width: int, height: int) -> bytes:
    """Encode a pen grid as canonical Mode-1 bytes."""
    if width % 4 or len(grid) != height or any(len(row) != width for row in grid):
        raise ValueError(f"tile must be {width}x{height} pixels")
    out = bytearray()
    for y in range(height):
        for bx in range(width // 4):
            value = 0
            for pixel in range(4):
                pen = grid[y][bx * 4 + pixel]
                if not 0 <= pen < 4:
                    raise ValueError(f"invalid pen {pen} at {bx * 4 + pixel},{y}")
                if pen & 1:
                    value |= 1 << BIT0[pixel]
                if pen & 2:
                    value |= 1 << BIT1[pixel]
            out.append(value)
    return bytes(out)


def decode_tbr(data: bytes) -> list[list[int]]:
    """Decode the repeated 16x14 portion of a legacy or current theme."""
    if len(data) not in (TILE_BYTES, THEME_BYTES):
        raise ValueError(f"expected {TILE_BYTES} or {THEME_BYTES} bytes, got {len(data)}")
    return decode_grid(data[:TILE_BYTES], TILE_W, TILE_H)


def encode_tbr(grid: list[list[int]]) -> bytes:
    """Encode a legacy 56-byte background tile (kept for codec compatibility)."""
    return encode_grid(grid, TILE_W, TILE_H)


def default_close_grid() -> list[list[int]]:
    """Traditional white close tile with the 5x7 DEFAULT-font X."""
    grid = [[1] * CLOSE_W for _ in range(CLOSE_H)]
    glyph = ("#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #")
    for y, row in enumerate(glyph, start=1):
        for x, pixel in enumerate(row):
            if pixel == "#":
                grid[y][x] = 2
    return grid


def default_max_grid() -> list[list[int]]:
    """Traditional white maximize tile with a centered 4x4 dark square."""
    grid = [[1] * MAX_W for _ in range(MAX_H)]
    for y in range(3, 7):
        for x in range(4, 8):
            grid[y][x] = 2
    return grid


def decode_theme(data: bytes) -> tuple[list[list[int]], list[list[int]], list[list[int]]]:
    """Decode a full theme, supplying traditional gadgets for a legacy tile."""
    title = decode_tbr(data)
    if len(data) == TILE_BYTES:
        return title, default_close_grid(), default_max_grid()
    close_start = TILE_BYTES
    max_start = close_start + CLOSE_BYTES
    return (
        title,
        decode_grid(data[close_start:max_start], CLOSE_W, CLOSE_H),
        decode_grid(data[max_start:], MAX_W, MAX_H),
    )


def encode_theme(title: list[list[int]], close: list[list[int]], maximize: list[list[int]]) -> bytes:
    """Encode the repeated background and both reusable gadget tiles."""
    return b"".join((
        encode_grid(title, TILE_W, TILE_H),
        encode_grid(close, CLOSE_W, CLOSE_H),
        encode_grid(maximize, MAX_W, MAX_H),
    ))


def stripe_grid() -> list[list[int]]:
    """Return the current GEOBENCH alternating-line motif as a tile."""
    return [[2 if y % 2 == 0 else 1 for _x in range(TILE_W)] for y in range(TILE_H)]


def sample_grid() -> list[list[int]]:
    """Return an alternate diagonal-weave motif."""
    grid = [[1] * TILE_W for _ in range(TILE_H)]
    for y in range(TILE_H):
        if y in (0, TILE_H - 1):
            grid[y] = [2] * TILE_W
            continue
        phase = (y * 2) % 8
        for x in range(TILE_W):
            if (x + phase) % 8 == 0:
                grid[y][x] = 2
    return grid


def nearest_pen(rgb: tuple[int, int, int]) -> int:
    palette = ((0, 0, 170), (255, 255, 255), (0, 0, 0), (255, 0, 0))
    return min(
        range(4),
        key=lambda pen: sum((palette[pen][component] - rgb[component]) ** 2 for component in range(3)),
    )


class TitleBarEditor(tk.Tk):
    def __init__(self, path: str | None = None):
        super().__init__()
        self.title("GEOBENCH title-bar tile editor")
        self.resizable(False, False)
        self.grid_data = stripe_grid()
        self.close_data = default_close_grid()
        self.max_data = default_max_grid()
        self.path: Path | None = None
        self.pen = tk.IntVar(value=2)
        self.cell_ids: list[list[int]] = []
        self.close_ids: list[list[int]] = []
        self.max_ids: list[list[int]] = []
        self._build()
        self._init_editor_cells()
        if path:
            self.load_tbr(Path(path))
        self._redraw()
        self.bind("<Control-n>", lambda _event: self.new())
        self.bind("<Control-o>", lambda _event: self.open_tbr())
        self.bind("<Control-s>", lambda _event: self.save_tbr())

    def _build(self) -> None:
        toolbar = ttk.Frame(self, padding=6)
        toolbar.pack(side="top", fill="x")
        ttk.Button(toolbar, text="New", command=self.new).pack(side="left")
        ttk.Button(toolbar, text="Sample", command=self.use_sample).pack(side="left", padx=2)
        ttk.Button(toolbar, text="Open .TBR", command=self.open_tbr).pack(side="left", padx=2)
        ttk.Button(toolbar, text="Import .png", command=self.import_png).pack(side="left", padx=2)
        ttk.Button(toolbar, text="Save .TBR", command=self.save_tbr).pack(side="left", padx=2)
        ttk.Button(toolbar, text="Export .png", command=self.export_png).pack(side="left", padx=2)

        pens = ttk.Frame(toolbar)
        pens.pack(side="right")
        ttk.Label(pens, text="Pen:").pack(side="left")
        for value, name in enumerate(PEN_NAME):
            foreground = "#000000" if value == 1 else "#ffffff"
            tk.Radiobutton(
                pens,
                text=name,
                variable=self.pen,
                value=value,
                indicatoron=False,
                width=7,
                bg=PEN_RGB[value],
                fg=foreground,
                selectcolor=PEN_RGB[value],
            ).pack(side="left", padx=1)

        content = ttk.Frame(self, padding=6)
        content.pack(side="top")

        editor_frame = ttk.Frame(content)
        editor_frame.pack(side="left", anchor="n")
        ttk.Label(editor_frame, text="Tile (16x14)").pack()
        self.editor = tk.Canvas(
            editor_frame,
            width=TILE_W * CELL,
            height=TILE_H * CELL,
            highlightthickness=1,
            highlightbackground="#777777",
        )
        self.editor.pack()
        self.editor.bind("<Button-1>", lambda event: self._paint(event, self.pen.get()))
        self.editor.bind("<B1-Motion>", lambda event: self._paint(event, self.pen.get()))
        self.editor.bind("<Button-3>", lambda event: self._paint(event, 0))
        self.editor.bind("<B3-Motion>", lambda event: self._paint(event, 0))

        gadget_frame = ttk.Frame(editor_frame)
        gadget_frame.pack(side="top", pady=(8, 0))
        close_frame = ttk.Frame(gadget_frame)
        close_frame.pack(side="left", anchor="n")
        ttk.Label(close_frame, text="Close tile (8x10)").pack()
        self.close_editor = tk.Canvas(
            close_frame,
            width=CLOSE_W * GADGET_CELL,
            height=CLOSE_H * GADGET_CELL,
            highlightthickness=1,
            highlightbackground="#777777",
        )
        self.close_editor.pack()
        self.close_editor.bind(
            "<Button-1>",
            lambda event: self._paint_gadget(event, self.close_data, self.close_ids, self.pen.get()),
        )
        self.close_editor.bind(
            "<B1-Motion>",
            lambda event: self._paint_gadget(event, self.close_data, self.close_ids, self.pen.get()),
        )
        self.close_editor.bind(
            "<Button-3>", lambda event: self._paint_gadget(event, self.close_data, self.close_ids, 0)
        )

        max_frame = ttk.Frame(gadget_frame)
        max_frame.pack(side="left", padx=(8, 0), anchor="n")
        ttk.Label(max_frame, text="Maximize tile (12x10)").pack()
        self.max_editor = tk.Canvas(
            max_frame,
            width=MAX_W * GADGET_CELL,
            height=MAX_H * GADGET_CELL,
            highlightthickness=1,
            highlightbackground="#777777",
        )
        self.max_editor.pack()
        self.max_editor.bind(
            "<Button-1>",
            lambda event: self._paint_gadget(event, self.max_data, self.max_ids, self.pen.get()),
        )
        self.max_editor.bind(
            "<B1-Motion>",
            lambda event: self._paint_gadget(event, self.max_data, self.max_ids, self.pen.get()),
        )
        self.max_editor.bind(
            "<Button-3>", lambda event: self._paint_gadget(event, self.max_data, self.max_ids, 0)
        )

        preview_frame = ttk.Frame(content)
        preview_frame.pack(side="left", padx=(12, 0), anchor="n")
        ttk.Label(preview_frame, text="Repeated window preview").pack()
        self.preview = tk.Canvas(
            preview_frame,
            width=PREVIEW_W,
            height=PREVIEW_H,
            bg=PEN_RGB[0],
            highlightthickness=1,
            highlightbackground="#777777",
        )
        self.preview.pack()
        self.status = ttk.Label(preview_frame, text="")
        self.status.pack(anchor="w", pady=(4, 0))

    def _init_editor_cells(self) -> None:
        self.cell_ids = [
            [
                self.editor.create_rectangle(
                    x * CELL,
                    y * CELL,
                    (x + 1) * CELL,
                    (y + 1) * CELL,
                    fill=PEN_RGB[0],
                    outline="#555555",
                )
                for x in range(TILE_W)
            ]
            for y in range(TILE_H)
        ]
        self.close_ids = self._create_cells(self.close_editor, CLOSE_W, CLOSE_H, GADGET_CELL)
        self.max_ids = self._create_cells(self.max_editor, MAX_W, MAX_H, GADGET_CELL)

    @staticmethod
    def _create_cells(canvas: tk.Canvas, width: int, height: int, cell: int) -> list[list[int]]:
        return [
            [
                canvas.create_rectangle(
                    x * cell,
                    y * cell,
                    (x + 1) * cell,
                    (y + 1) * cell,
                    fill=PEN_RGB[0],
                    outline="#555555",
                )
                for x in range(width)
            ]
            for y in range(height)
        ]

    def _paint(self, event: tk.Event, pen: int) -> None:
        x = int(event.x) // CELL
        y = int(event.y) // CELL
        if 0 <= x < TILE_W and 0 <= y < TILE_H and self.grid_data[y][x] != pen:
            self.grid_data[y][x] = pen
            self.editor.itemconfig(self.cell_ids[y][x], fill=PEN_RGB[pen])
            self._draw_preview()

    def _paint_gadget(
        self,
        event: tk.Event,
        grid: list[list[int]],
        ids: list[list[int]],
        pen: int,
    ) -> None:
        x = int(event.x) // GADGET_CELL
        y = int(event.y) // GADGET_CELL
        if 0 <= y < len(grid) and 0 <= x < len(grid[0]) and grid[y][x] != pen:
            grid[y][x] = pen
            event.widget.itemconfig(ids[y][x], fill=PEN_RGB[pen])
            self._draw_preview()

    def _draw_gadget(self, grid: list[list[int]], x: int, y: int, scale: int) -> None:
        for gy, row in enumerate(grid):
            for gx, pen in enumerate(row):
                self.preview.create_rectangle(
                    x + gx * scale,
                    y + gy * scale,
                    x + (gx + 1) * scale,
                    y + (gy + 1) * scale,
                    fill=PEN_RGB[pen],
                    outline=PEN_RGB[pen],
                )

    def _draw_window(self, x: int, y: int, width: int, height: int, title: str) -> None:
        scale = 2
        bar_h = TILE_H * scale
        self.preview.create_rectangle(
            x,
            y,
            x + width,
            y + height,
            fill=PEN_RGB[1],
            outline=PEN_RGB[2],
            width=2,
        )
        for py in range(TILE_H):
            for px in range((width + scale - 1) // scale):
                color = PEN_RGB[self.grid_data[py][px % TILE_W]]
                left = x + px * scale
                self.preview.create_rectangle(
                    left,
                    y + py * scale,
                    min(left + scale, x + width),
                    y + (py + 1) * scale,
                    fill=color,
                    outline=color,
                )
        self.preview.create_rectangle(x, y, x + width, y + bar_h, outline=PEN_RGB[2], width=2)

        gy = y + 4
        self._draw_gadget(self.close_data, x + 8, gy, scale)
        self._draw_gadget(self.max_data, x + width - MAX_W * scale - 8, gy, scale)
        self.preview.create_text(
            x + 30,
            y + bar_h // 2,
            text=title,
            anchor="w",
            fill=PEN_RGB[1],
            font=("monospace", 12, "bold"),
        )

    def _draw_preview(self) -> None:
        self.preview.delete("all")
        self._draw_window(18, 20, 570, 105, "File Manager")
        self._draw_window(55, 142, 390, 92, "Settings")
        self._draw_window(170, 250, 410, 88, "Viewer")

    def _redraw(self) -> None:
        for y in range(TILE_H):
            for x in range(TILE_W):
                self.editor.itemconfig(self.cell_ids[y][x], fill=PEN_RGB[self.grid_data[y][x]])
        for y in range(CLOSE_H):
            for x in range(CLOSE_W):
                self.close_editor.itemconfig(
                    self.close_ids[y][x], fill=PEN_RGB[self.close_data[y][x]]
                )
        for y in range(MAX_H):
            for x in range(MAX_W):
                self.max_editor.itemconfig(self.max_ids[y][x], fill=PEN_RGB[self.max_data[y][x]])
        self._draw_preview()
        self.status.config(text=str(self.path) if self.path else "(unsaved)")

    def new(self) -> None:
        self.grid_data = stripe_grid()
        self.close_data = default_close_grid()
        self.max_data = default_max_grid()
        self.path = None
        self._redraw()

    def use_sample(self) -> None:
        self.grid_data = sample_grid()
        self.close_data = default_close_grid()
        self.max_data = default_max_grid()
        self.path = None
        self._redraw()

    def load_tbr(self, path: Path) -> None:
        try:
            self.grid_data, self.close_data, self.max_data = decode_theme(path.read_bytes())
        except (OSError, ValueError) as error:
            messagebox.showerror("Open .TBR", f"{path}: {error}")
            return
        self.path = path

    def open_tbr(self) -> None:
        selected = filedialog.askopenfilename(filetypes=[("Title-bar tile", "*.TBR *.tbr")])
        if selected:
            self.load_tbr(Path(selected))
            self._redraw()

    def import_png(self) -> None:
        selected = filedialog.askopenfilename(filetypes=[("PNG image", "*.png")])
        if not selected:
            return
        try:
            from PIL import Image
        except ImportError:
            messagebox.showerror("Import", "Pillow is required to import PNG images.")
            return
        image = Image.open(selected).convert("RGB").resize((TILE_W, TILE_H), Image.Resampling.NEAREST)
        pixels = image.load()
        self.grid_data = [
            [nearest_pen(pixels[x, y]) for x in range(TILE_W)]
            for y in range(TILE_H)
        ]
        self.path = None
        self._redraw()

    def save_tbr(self) -> None:
        path = self.path
        if path is None or path.suffix.lower() != ".tbr":
            selected = filedialog.asksaveasfilename(
                defaultextension=".TBR",
                filetypes=[("Title-bar tile", "*.TBR")],
            )
            if not selected:
                return
            path = Path(selected)
        try:
            path.write_bytes(encode_theme(self.grid_data, self.close_data, self.max_data))
        except (OSError, ValueError) as error:
            messagebox.showerror("Save .TBR", str(error))
            return
        self.path = path
        self._redraw()

    def export_png(self) -> None:
        try:
            from PIL import Image
        except ImportError:
            messagebox.showerror("Export", "Pillow is required to export PNG images.")
            return
        selected = filedialog.asksaveasfilename(
            defaultextension=".png",
            filetypes=[("PNG image", "*.png")],
        )
        if not selected:
            return
        palette = ((0, 0, 170), (255, 255, 255), (0, 0, 0), (255, 0, 0))
        image = Image.new("RGB", (TILE_W, TILE_H))
        for y in range(TILE_H):
            for x in range(TILE_W):
                image.putpixel((x, y), palette[self.grid_data[y][x]])
        image.save(selected)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tile", nargs="?", help="optional .TBR tile to open")
    parser.add_argument("--write-sample", metavar="PATH", help="write the sample weave and exit")
    parser.add_argument(
        "--upgrade",
        metavar="PATH",
        action="append",
        help="append the traditional gadget tiles to a legacy 56-byte theme",
    )
    args = parser.parse_args()
    if args.upgrade:
        for name in args.upgrade:
            path = Path(name)
            data = path.read_bytes()
            title, close, maximize = decode_theme(data)
            path.write_bytes(encode_theme(title, close, maximize))
        return
    if args.write_sample:
        output = Path(args.write_sample)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(encode_theme(sample_grid(), default_close_grid(), default_max_grid()))
        return
    TitleBarEditor(args.tile).mainloop()


if __name__ == "__main__":
    main()
