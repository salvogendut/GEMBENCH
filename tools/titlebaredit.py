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
import math
from pathlib import Path
import random
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from iconedit import flood_fill_grid, shift_grid, spray_points


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


def line_points(x0: int, y0: int, x1: int, y1: int) -> list[tuple[int, int]]:
    """Return an inclusive Bresenham line."""
    points = []
    dx = abs(x1 - x0)
    sx = 1 if x0 < x1 else -1
    dy = -abs(y1 - y0)
    sy = 1 if y0 < y1 else -1
    error = dx + dy
    while True:
        points.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return points
        twice = 2 * error
        if twice >= dy:
            error += dy
            x0 += sx
        if twice <= dx:
            error += dx
            y0 += sy


def rectangle_points(
    x0: int, y0: int, x1: int, y1: int, filled: bool
) -> list[tuple[int, int]]:
    """Return the pixels in an inclusive outlined or filled rectangle."""
    lo_x, hi_x = sorted((x0, x1))
    lo_y, hi_y = sorted((y0, y1))
    return [
        (x, y)
        for y in range(lo_y, hi_y + 1)
        for x in range(lo_x, hi_x + 1)
        if filled or x in (lo_x, hi_x) or y in (lo_y, hi_y)
    ]


def ellipse_points(
    x0: int, y0: int, x1: int, y1: int, filled: bool
) -> list[tuple[int, int]]:
    """Return bounded pixels for an inclusive outlined or filled ellipse."""
    lo_x, hi_x = sorted((x0, x1))
    lo_y, hi_y = sorted((y0, y1))
    center_x = (lo_x + hi_x) / 2.0
    center_y = (lo_y + hi_y) / 2.0
    radius_x = max(0.5, (hi_x - lo_x) / 2.0)
    radius_y = max(0.5, (hi_y - lo_y) / 2.0)
    if filled:
        return [
            (x, y)
            for y in range(lo_y, hi_y + 1)
            for x in range(lo_x, hi_x + 1)
            if ((x - center_x) / radius_x) ** 2
            + ((y - center_y) / radius_y) ** 2
            <= 1.0
        ]
    points = set()
    steps = int(2 * math.pi * max(radius_x, radius_y) * 4) + 8
    for step in range(steps):
        angle = 2 * math.pi * step / steps
        points.add((
            int(round(center_x + radius_x * math.cos(angle))),
            int(round(center_y + radius_y * math.sin(angle))),
        ))
    return sorted(points)


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
        self.tool = tk.StringVar(value="pen")
        self.active_name = "title"
        self.drag: tuple[str, tk.Canvas, int, int, int, int] | None = None
        self.undo_stack: list[tuple[list[list[int]], list[list[int]], list[list[int]]]] = []
        self.rng = random.Random()
        self.tool_buttons: dict[str, tuple[tk.Frame, bool]] = {}
        self.tooltip_window: tk.Toplevel | None = None
        self.tooltip_job: str | None = None
        self.cell_ids: list[list[int]] = []
        self.close_ids: list[list[int]] = []
        self.max_ids: list[list[int]] = []
        self._build()
        self._init_editor_cells()
        self._activate(self.editor)
        if path:
            self.load_tbr(Path(path))
        self._redraw()
        self.bind("<Control-n>", lambda _event: self.new())
        self.bind("<Control-o>", lambda _event: self.open_tbr())
        self.bind("<Control-s>", lambda _event: self.save_tbr())
        self.bind("<Control-z>", lambda _event: self.undo())

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

        for canvas in (self.editor, self.close_editor, self.max_editor):
            self._bind_editor(canvas)

        tool_panel = ttk.Frame(content)
        tool_panel.pack(side="left", padx=(12, 0), anchor="n")
        toolchest = ttk.LabelFrame(tool_panel, text="Toolchest", padding=4)
        toolchest.pack(anchor="n")
        tools = (
            ("circle_fill", "Filled circle", 0, 0, None),
            ("circle", "Outline circle", 0, 1, None),
            ("rect_fill", "Filled square", 0, 2, None),
            ("rect", "Outline square", 1, 0, None),
            ("pen", "Pencil", 1, 1, None),
            ("line", "Line", 1, 2, None),
            ("bucket", "Fill bucket", 2, 0, None),
            ("spray", "Spray paint", 2, 1, None),
            ("undo", "Undo", 2, 2, self.undo),
        )
        for key, label, row, column, command in tools:
            self._add_tool_button(toolchest, key, label, row, column, command)

        shift = ttk.LabelFrame(tool_panel, text="Shift active canvas", padding=4)
        shift.pack(anchor="n", pady=(8, 0))
        self._add_tool_button(shift, "up", "Shift up one pixel", 0, 1,
                              lambda: self.shift_active(0, -1))
        self._add_tool_button(shift, "left", "Shift left one pixel", 1, 0,
                              lambda: self.shift_active(-1, 0))
        self._add_tool_button(shift, "right", "Shift right one pixel", 1, 2,
                              lambda: self.shift_active(1, 0))
        self._add_tool_button(shift, "down", "Shift down one pixel", 2, 1,
                              lambda: self.shift_active(0, 1))
        self.active_label = ttk.Label(tool_panel, text="Editing: title")
        self.active_label.pack(anchor="center", pady=(6, 0))
        self.tool_label = ttk.Label(tool_panel, text="Tool: Pencil", wraplength=125)
        self.tool_label.pack(anchor="center", pady=(2, 0))
        self._select_tool("pen")

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

    def _bind_editor(self, canvas: tk.Canvas) -> None:
        canvas.bind("<ButtonPress-1>", self._on_press)
        canvas.bind("<B1-Motion>", self._on_drag)
        canvas.bind("<ButtonRelease-1>", self._on_release)
        canvas.bind("<ButtonPress-3>", self._on_erase_press)
        canvas.bind("<B3-Motion>", self._on_drag)
        canvas.bind("<ButtonRelease-3>", self._on_release)

    def _add_tool_button(
        self,
        parent: ttk.LabelFrame,
        key: str,
        label: str,
        row: int,
        column: int,
        command,
    ) -> None:
        """Create one fixed-size icon button matching the icon editor."""
        holder = tk.Frame(
            parent,
            width=36,
            height=36,
            borderwidth=2,
            relief="raised",
            background="#e6e6e6",
            takefocus=1,
        )
        holder.grid(row=row, column=column, padx=2, pady=2)
        holder.grid_propagate(False)
        icon = tk.Canvas(
            holder,
            width=28,
            height=28,
            background="#e6e6e6",
            highlightthickness=0,
            cursor="hand2",
        )
        icon.place(relx=0.5, rely=0.5, anchor="center")
        self._draw_tool_icon(icon, key)
        selectable = command is None
        self.tool_buttons[key] = (holder, selectable)

        def invoke(_event=None):
            if selectable:
                self._select_tool(key)
            else:
                command()
            return "break"

        for widget in (holder, icon):
            widget.bind("<Button-1>", invoke)
            widget.bind(
                "<Enter>",
                lambda _event, target=holder, text=label: self._queue_tooltip(target, text),
            )
            widget.bind("<Leave>", lambda _event: self._hide_tooltip())
        holder.bind("<Return>", invoke)
        holder.bind("<space>", invoke)

    @staticmethod
    def _draw_tool_icon(canvas: tk.Canvas, key: str) -> None:
        """Draw compact tool glyphs without adding image dependencies."""
        foreground = "#202020"
        accent = "#1769b0"
        if key == "circle_fill":
            canvas.create_oval(4, 4, 24, 24, fill=foreground, outline=foreground)
        elif key == "circle":
            canvas.create_oval(4, 4, 24, 24, outline=foreground, width=3)
        elif key == "rect_fill":
            canvas.create_rectangle(5, 5, 23, 23, fill=foreground, outline=foreground)
        elif key == "rect":
            canvas.create_rectangle(5, 5, 23, 23, outline=foreground, width=3)
        elif key == "pen":
            canvas.create_line(6, 22, 20, 8, fill=accent, width=5)
            canvas.create_polygon(4, 24, 7, 18, 10, 21,
                                  fill=foreground, outline=foreground)
        elif key == "line":
            canvas.create_line(5, 23, 23, 5, fill=foreground, width=3)
            canvas.create_oval(3, 21, 7, 25, fill=accent, outline=accent)
            canvas.create_oval(21, 3, 25, 7, fill=accent, outline=accent)
        elif key == "bucket":
            canvas.create_polygon(5, 12, 15, 5, 23, 15, 13, 23,
                                  fill="#ffffff", outline=foreground, width=2)
            canvas.create_line(8, 13, 20, 16, fill=accent, width=3)
            canvas.create_oval(20, 20, 24, 26, fill=accent, outline=accent)
        elif key == "spray":
            canvas.create_rectangle(5, 10, 13, 24, fill="#ffffff",
                                    outline=foreground, width=2)
            canvas.create_rectangle(8, 6, 15, 11, fill="#ffffff",
                                    outline=foreground, width=2)
            for x, y in ((18, 8), (22, 6), (20, 13), (25, 11), (17, 17), (23, 18)):
                canvas.create_oval(x - 1, y - 1, x + 1, y + 1,
                                   fill=accent, outline=accent)
        elif key == "undo":
            canvas.create_arc(5, 5, 24, 24, start=35, extent=260,
                              style="arc", outline=accent, width=4)
            canvas.create_polygon(4, 8, 11, 5, 10, 13, fill=accent, outline=accent)
        elif key in ("up", "down", "left", "right"):
            endpoints = {
                "up": (14, 23, 14, 5),
                "down": (14, 5, 14, 23),
                "left": (23, 14, 5, 14),
                "right": (5, 14, 23, 14),
            }
            canvas.create_line(*endpoints[key], fill=accent, width=4, arrow="last")

    def _select_tool(self, key: str) -> None:
        self.tool.set(key)
        for name, (holder, selectable) in self.tool_buttons.items():
            holder.config(relief="sunken" if selectable and name == key else "raised")
        labels = {
            "pen": "Pencil",
            "line": "Line",
            "bucket": "Fill bucket",
            "spray": "Spray paint",
            "rect": "Outline square",
            "rect_fill": "Filled square",
            "circle": "Outline circle",
            "circle_fill": "Filled circle",
        }
        if hasattr(self, "tool_label"):
            self.tool_label.config(text=f"Tool: {labels.get(key, key)}")

    def _queue_tooltip(self, widget: tk.Widget, label: str) -> None:
        self._hide_tooltip()
        self.tooltip_job = self.after(450, lambda: self._show_tooltip(widget, label))

    def _show_tooltip(self, widget: tk.Widget, label: str) -> None:
        self.tooltip_job = None
        tip = tk.Toplevel(self)
        tip.wm_overrideredirect(True)
        tip.wm_geometry(
            f"+{widget.winfo_rootx() + 8}"
            f"+{widget.winfo_rooty() + widget.winfo_height() + 2}"
        )
        ttk.Label(tip, text=label, padding=(5, 2), relief="solid").pack()
        self.tooltip_window = tip

    def _hide_tooltip(self) -> None:
        if self.tooltip_job is not None:
            self.after_cancel(self.tooltip_job)
            self.tooltip_job = None
        if self.tooltip_window is not None:
            self.tooltip_window.destroy()
            self.tooltip_window = None

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

    def _target(self, canvas: tk.Canvas):
        if canvas is self.editor:
            return "title", self.grid_data, self.cell_ids, CELL
        if canvas is self.close_editor:
            return "close", self.close_data, self.close_ids, GADGET_CELL
        if canvas is self.max_editor:
            return "maximize", self.max_data, self.max_ids, GADGET_CELL
        raise ValueError("unknown editor canvas")

    def _active_target(self):
        canvases = {
            "title": self.editor,
            "close": self.close_editor,
            "maximize": self.max_editor,
        }
        canvas = canvases[self.active_name]
        return canvas, *self._target(canvas)[1:]

    def _activate(self, canvas: tk.Canvas) -> None:
        self.active_name = self._target(canvas)[0]
        for candidate in (self.editor, self.close_editor, self.max_editor):
            candidate.config(
                highlightbackground="#1769b0" if candidate is canvas else "#777777"
            )
        self.active_label.config(text=f"Editing: {self.active_name}")

    def _cell_at(self, canvas: tk.Canvas, sx: int, sy: int, clamp: bool = False):
        _name, grid, _ids, cell = self._target(canvas)
        x = sx // cell
        y = sy // cell
        width = len(grid[0])
        height = len(grid)
        if clamp:
            return max(0, min(width - 1, x)), max(0, min(height - 1, y))
        if 0 <= x < width and 0 <= y < height:
            return x, y
        return None

    def _push_undo(self) -> None:
        self.undo_stack.append((
            [row[:] for row in self.grid_data],
            [row[:] for row in self.close_data],
            [row[:] for row in self.max_data],
        ))
        if len(self.undo_stack) > 40:
            self.undo_stack.pop(0)

    def undo(self) -> None:
        if not self.undo_stack:
            return
        self.grid_data, self.close_data, self.max_data = self.undo_stack.pop()
        self.drag = None
        self._redraw()

    def shift_active(self, dx: int, dy: int) -> None:
        _canvas, grid, _ids, _cell = self._active_target()
        shifted = shift_grid(grid, dx, dy)
        if shifted == grid:
            return
        self._push_undo()
        grid[:] = shifted
        self._redraw()

    def _apply_points(self, canvas: tk.Canvas, points, pen: int) -> int:
        _name, grid, ids, _cell = self._target(canvas)
        width = len(grid[0])
        height = len(grid)
        changed = 0
        for x, y in set(points):
            if 0 <= x < width and 0 <= y < height and grid[y][x] != pen:
                grid[y][x] = pen
                canvas.itemconfig(ids[y][x], fill=PEN_RGB[pen])
                changed += 1
        if changed:
            self._draw_preview()
        return changed

    def _spray_line(self, canvas: tk.Canvas, x0: int, y0: int, x1: int, y1: int) -> None:
        _name, grid, _ids, _cell = self._target(canvas)
        width = len(grid[0])
        height = len(grid)
        points = []
        for x, y in line_points(x0, y0, x1, y1):
            points.extend(spray_points(width, height, x, y, self.rng))
        self._apply_points(canvas, points, self.pen.get())

    def _on_press(self, event: tk.Event) -> None:
        canvas = event.widget
        self._activate(canvas)
        cell = self._cell_at(canvas, int(event.x), int(event.y))
        if cell is None:
            return
        tool = self.tool.get()
        if tool == "bucket":
            _name, grid, _ids, _cell = self._target(canvas)
            if grid[cell[1]][cell[0]] == self.pen.get():
                return
            self._push_undo()
            flood_fill_grid(grid, cell[0], cell[1], self.pen.get())
            self._redraw()
            return
        self._push_undo()
        self.drag = (tool, canvas, cell[0], cell[1], cell[0], cell[1])
        if tool == "pen":
            self._apply_points(canvas, [cell], self.pen.get())
        elif tool == "spray":
            self._spray_line(canvas, cell[0], cell[1], cell[0], cell[1])
        else:
            self._draw_drag_preview()

    def _on_erase_press(self, event: tk.Event) -> None:
        canvas = event.widget
        self._activate(canvas)
        cell = self._cell_at(canvas, int(event.x), int(event.y))
        if cell is None:
            return
        self._push_undo()
        self.drag = ("erase", canvas, cell[0], cell[1], cell[0], cell[1])
        self._apply_points(canvas, [cell], 0)

    def _on_drag(self, event: tk.Event) -> None:
        if self.drag is None or event.widget is not self.drag[1]:
            return
        tool, canvas, x0, y0, old_x, old_y = self.drag
        x, y = self._cell_at(canvas, int(event.x), int(event.y), clamp=True)
        if (x, y) == (old_x, old_y):
            return
        if tool in ("pen", "erase"):
            self._apply_points(
                canvas, line_points(old_x, old_y, x, y), 0 if tool == "erase" else self.pen.get()
            )
            self.drag = (tool, canvas, x, y, x, y)
        elif tool == "spray":
            self._spray_line(canvas, old_x, old_y, x, y)
            self.drag = (tool, canvas, x, y, x, y)
        else:
            self.drag = (tool, canvas, x0, y0, x, y)
            self._draw_drag_preview()

    def _on_release(self, event: tk.Event) -> None:
        if self.drag is None or event.widget is not self.drag[1]:
            return
        tool, canvas, x0, y0, x1, y1 = self.drag
        release = self._cell_at(canvas, int(event.x), int(event.y), clamp=True)
        if tool not in ("pen", "erase", "spray"):
            x1, y1 = release
        self.drag = None
        canvas.delete("drag-preview")
        if tool == "line":
            self._apply_points(canvas, line_points(x0, y0, x1, y1), self.pen.get())
        elif tool in ("rect", "rect_fill"):
            self._apply_points(
                canvas,
                rectangle_points(x0, y0, x1, y1, tool == "rect_fill"),
                self.pen.get(),
            )
        elif tool in ("circle", "circle_fill"):
            self._apply_points(
                canvas,
                ellipse_points(x0, y0, x1, y1, tool == "circle_fill"),
                self.pen.get(),
            )

    def _draw_drag_preview(self) -> None:
        if self.drag is None:
            return
        tool, canvas, x0, y0, x1, y1 = self.drag
        canvas.delete("drag-preview")
        _name, _grid, _ids, cell = self._target(canvas)
        color = PEN_RGB[self.pen.get()]
        if tool == "line":
            canvas.create_line(
                (x0 + 0.5) * cell,
                (y0 + 0.5) * cell,
                (x1 + 0.5) * cell,
                (y1 + 0.5) * cell,
                fill=color,
                width=3,
                tags="drag-preview",
            )
            return
        if tool not in ("rect", "rect_fill", "circle", "circle_fill"):
            return
        lo_x, hi_x = sorted((x0, x1))
        lo_y, hi_y = sorted((y0, y1))
        coords = (lo_x * cell, lo_y * cell, (hi_x + 1) * cell, (hi_y + 1) * cell)
        options = {
            "outline": color,
            "width": 3,
            "fill": color if tool.endswith("_fill") else "",
            "tags": "drag-preview",
        }
        if tool.endswith("_fill"):
            options["stipple"] = "gray50"
        if tool.startswith("rect"):
            canvas.create_rectangle(*coords, **options)
        else:
            canvas.create_oval(*coords, **options)

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
        for canvas in (self.editor, self.close_editor, self.max_editor):
            canvas.delete("drag-preview")
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
        self.undo_stack.clear()
        self.drag = None
        self._redraw()

    def use_sample(self) -> None:
        self.grid_data = sample_grid()
        self.close_data = default_close_grid()
        self.max_data = default_max_grid()
        self.path = None
        self.undo_stack.clear()
        self.drag = None
        self._redraw()

    def load_tbr(self, path: Path) -> None:
        try:
            self.grid_data, self.close_data, self.max_data = decode_theme(path.read_bytes())
        except (OSError, ValueError) as error:
            messagebox.showerror("Open .TBR", f"{path}: {error}")
            return
        self.path = path
        self.undo_stack.clear()
        self.drag = None

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
        self.undo_stack.clear()
        self.drag = None
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
