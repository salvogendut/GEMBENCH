#!/usr/bin/env python3
"""iconedit - Tk editor for GEOBENCH .IST, .SPR, .APP, and icon .asm files.

Edits Amstrad CPC Mode 1 bitmaps (4 colours, 4 pixels per byte) byte-for-byte
compatible with tools/packicons.py and tools/png2spr.py — see
tools/test_iconed_codec.py for the encoding rules.

  * .IST  v2 icon set: header(16) + dir(count*4: off u16le, w_bytes u8, h u8)
          + bitmaps. Each icon keeps its own size; mixed sizes are allowed.
  * .APP  GBAP v1/v2/v3 preamble: executable JP + one canonical 32x32 Mode-1
          icon and, in v2/v3, an optional native Screen-7 icon. Saving preserves
          every non-icon executable byte and unedited resource.
  * .ASM  RASM icon source: one labelled Mode-1 or native MSX Screen-7 bitmap
          with <label>_w and <label>_h dimensions. Mode 7 adds
          <label>_mode equ 7 and packs two 4-bit pixels per byte. Four-colour
          sources remain directly APP_ICON-compatible.
  * .SPR  cursor sprite: 256 bytes = 4 phases of 4x16 bytes (d0, m0, d2, m2).
          We edit a single 16x16 logical grid (pen 0 = transparent) and
          regenerate d0/m0/d2/m2 on save (d2/m2 are the +2 px pre-shift).

Multiple sets can be open at once, each in its own window (File > Open in New
Window), so you can Copy/Paste Icon between two sets side by side.

Run:
    python3 tools/iconedit.py [--platform msx2] [file.IST | file.SPR | file.APP | icon.asm]

All .IST files use the same canonical CPC Mode-1 encoding. --platform msx2 only
selects the V9938 hardware-sprite cursor format for .SPR files (66 bytes,
round-trips with png2spr.py --platform msx2): paint pen 1 (white) for the outline,
pen 3 (red) for the fill, pen 0 to erase. Without it, .SPR is a CPC Mode-1 masked
cursor instead.
"""
import json
import math
import os
import random
import re
import struct
import sys
import tempfile
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from embed_app_icon import (CODEC_MODE1, CODEC_SCREEN7, ICON_H, ICON_WB,
                            parse_resources)

# --- portable .IST pixel packing: canonical CPC Mode 1 on every target --------
# PLATFORM only selects the .SPR cursor codec below; it never changes .IST data.
PLATFORM = 'cpc'

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


def decode_icon16(data, off, wbytes, h):
    """Native Screen-7 4bpp: high nibble left, low nibble right."""
    grid = [[0] * (wbytes * 2) for _ in range(h)]
    for y in range(h):
        for bx in range(wbytes):
            value = data[off + y * wbytes + bx]
            grid[y][bx * 2] = value >> 4
            grid[y][bx * 2 + 1] = value & 0x0F
    return grid


def encode_icon16(grid, wbytes, h):
    out = bytearray(wbytes * h)
    for y in range(h):
        for bx in range(wbytes):
            out[y * wbytes + bx] = (
                (grid[y][bx * 2] << 4) | grid[y][bx * 2 + 1]
            )
    return bytes(out)


def shift_grid(grid, dx, dy):
    """Move a pixel grid by (dx, dy), clipping overflow and clearing edges."""
    if not grid:
        return []
    width = len(grid[0])
    height = len(grid)
    shifted = [[0] * width for _ in range(height)]
    for y in range(height):
        src_y = y - dy
        if not 0 <= src_y < height:
            continue
        for x in range(width):
            src_x = x - dx
            if 0 <= src_x < width:
                shifted[y][x] = grid[src_y][src_x]
    return shifted


def normalize_rect(x0, y0, x1, y1):
    """Return an inclusive rectangle with ordered coordinates."""
    return min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)


def flood_fill_grid(grid, x, y, pen):
    """Four-way flood fill. Mutates grid and returns the changed coordinates."""
    if not grid or not 0 <= y < len(grid) or not 0 <= x < len(grid[0]):
        return []
    source = grid[y][x]
    if source == pen:
        return []
    width = len(grid[0])
    height = len(grid)
    changed = []
    pending = [(x, y)]
    grid[y][x] = pen
    while pending:
        px, py = pending.pop()
        changed.append((px, py))
        for nx, ny in ((px - 1, py), (px + 1, py),
                       (px, py - 1), (px, py + 1)):
            if (0 <= nx < width and 0 <= ny < height
                    and grid[ny][nx] == source):
                grid[ny][nx] = pen
                pending.append((nx, ny))
    return changed


def spray_points(width, height, x, y, rng, radius=2, drops=8):
    """Return bounded pseudo-random points for one spray-paint pulse."""
    points = {(x, y)} if 0 <= x < width and 0 <= y < height else set()
    for _ in range(drops):
        dx = rng.randint(-radius, radius)
        dy = rng.randint(-radius, radius)
        if dx * dx + dy * dy > radius * radius:
            continue
        px, py = x + dx, y + dy
        if 0 <= px < width and 0 <= py < height:
            points.add((px, py))
    return sorted(points)


def copy_grid_region(grid, rect):
    """Copy an inclusive rectangle into a clipboard-sized pixel grid."""
    x0, y0, x1, y1 = normalize_rect(*rect)
    return {
        "pixel_w": x1 - x0 + 1,
        "h": y1 - y0 + 1,
        "grid": [row[x0:x1 + 1] for row in grid[y0:y1 + 1]],
    }


def pasted_grid(grid, payload, dst_x, dst_y, max_pen):
    """Return a copy of grid with a clipboard region pasted and clipped."""
    result = [row[:] for row in grid]
    if not result:
        return result, None
    source = payload.get("grid", [])
    if not source:
        return result, None
    width = len(result[0])
    height = len(result)
    changed = False
    min_x, min_y = width, height
    max_x = max_y = -1
    for sy, row in enumerate(source):
        py = dst_y + sy
        if not 0 <= py < height:
            continue
        for sx, value in enumerate(row):
            px = dst_x + sx
            if not 0 <= px < width:
                continue
            value = max(0, min(int(value), max_pen))
            if result[py][px] != value:
                result[py][px] = value
                changed = True
            min_x, min_y = min(min_x, px), min(min_y, py)
            max_x, max_y = max(max_x, px), max(max_y, py)
    bounds = (min_x, min_y, max_x, max_y) if max_x >= 0 else None
    return (result if changed else grid), bounds

# --- .SPR cursor: CPC Mode-1 masked, pre-shifted (256 bytes) ----------------
# Layout matches png2spr.py + lib/cursor_data.asm (-> DEFAULT.SPR): two phases
# (shift 0, then shift 2) back to back, each CUR_H rows of CUR_W byte-columns with
# mask,data INTERLEAVED per column - the kernel composites (bg AND mask) OR data
# reading one advancing pointer. We edit phase 0's unshifted 16x16 grid and
# regenerate both phases on save. (The old d0,m0,d2,m2 block order garbled it.)
CUR_W = 4         # byte-columns per row
CUR_H = 16
CPC_SPR_LEN = 2 * CUR_H * CUR_W * 2   # 256: 2 phases x rows x cols x (mask,data)

def _m1_decode(b, i):     # CPC Mode-1: pixel i (0..3) of byte b -> pen 0..3
    return ((b >> (7 - i)) & 1) | (((b >> (3 - i)) & 1) << 1)

def _m1_set(b, i, pen):
    if pen & 1:
        b |= 1 << (7 - i)
    if pen & 2:
        b |= 1 << (3 - i)
    return b

def decode_cursor_phase0(data):
    """Phase 0 of a CPC .SPR -> 16x16 grid (0 = transparent, 1..3 = pen)."""
    grid = [[0] * (CUR_W * 4) for _ in range(CUR_H)]
    for y in range(CUR_H):
        for bx in range(CUR_W):
            off = y * (CUR_W * 2) + bx * 2      # phase 0, row y, col bx: mask,data
            m, d = data[off], data[off + 1]
            for i in range(4):
                if (m >> (7 - i)) & 1:
                    grid[y][bx * 4 + i] = 0     # mask bit set = transparent
                else:
                    grid[y][bx * 4 + i] = _m1_decode(d, i)
    return grid

def encode_cursor_file(grid):
    """16x16 grid -> 256-byte CPC .SPR: 2 interleaved, pre-shifted phases."""
    blob = bytearray()
    for shift in (0, 2):
        for y in range(CUR_H):
            for bx in range(CUR_W):
                d = m = 0
                for i in range(4):
                    x = bx * 4 + i - shift
                    pen = grid[y][x] if 0 <= x < CUR_W * 4 else 0
                    if pen == 0:
                        m = _m1_set(m, i, 3)    # both mask bits = transparent
                    else:
                        d = _m1_set(d, i, pen)
                blob += bytes((m, d))           # mask, data interleaved
    return bytes(blob)

# --- MSX2 .SPR: V9938 hardware-sprite cursor (66 bytes) ---------------------
# +0 hotspot_x, +1 hotspot_y, +2..33 outline plane, +34..65 fill plane. Each
# plane is a 16x16 sprite pattern: 16 bytes for the left 8-px column (rows 0..15,
# bit7 = leftmost pixel), then 16 bytes for the right column - byte-for-byte
# compatible with png2spr.py --platform msx2. We edit it as a 16x16 pen grid:
# pen 1 (white) = outline, pen 3 (red) = fill, pen 0 = transparent, matching the
# two sprite-plane colours in lib/msx/cursor.asm.
MSX_SPR_LEN = 66
MSPR_OUTLINE_PEN = 1
MSPR_FILL_PEN = 3

def _msx_unpack(plane):          # 32 bytes -> 16x16 [0/1] rows
    rows = [[0] * 16 for _ in range(16)]
    idx = 0
    for col in (0, 8):
        for y in range(16):
            b = plane[idx]; idx += 1
            for i in range(8):
                if b & (0x80 >> i):
                    rows[y][col + i] = 1
    return rows

def _msx_pack(rows):             # 16x16 [0/1] rows -> 32 bytes
    blob = bytearray()
    for col in (0, 8):
        for y in range(16):
            b = 0
            for i in range(8):
                if rows[y][col + i]:
                    b |= 0x80 >> i
            blob.append(b)
    return blob

def decode_msx_sprite(data):     # 66 bytes -> (16x16 pen grid, (hx, hy))
    outline = _msx_unpack(data[2:34])
    fill = _msx_unpack(data[34:66])
    grid = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            if outline[y][x]:
                grid[y][x] = MSPR_OUTLINE_PEN
            elif fill[y][x]:
                grid[y][x] = MSPR_FILL_PEN
    return grid, (data[0], data[1])

def encode_msx_sprite(grid, hot):
    outline = [[1 if grid[y][x] == MSPR_OUTLINE_PEN else 0 for x in range(16)] for y in range(16)]
    fill = [[1 if grid[y][x] == MSPR_FILL_PEN else 0 for x in range(16)] for y in range(16)]
    return bytes(bytearray((hot[0], hot[1])) + _msx_pack(outline) + _msx_pack(fill))

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

# --- canonical RASM icon source --------------------------------------------

ASM_EQU_RE = re.compile(
    r"^([A-Za-z_][A-Za-z0-9_]*)_(w|h|mode)\s+equ\s+(\S+)$",
    re.IGNORECASE)
ASM_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
ASM_LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):?$")
ASM_DB_RE = re.compile(r"^db\s+(.+)$", re.IGNORECASE)


def _asm_int(text):
    text = text.strip()
    if text.startswith(("#", "$")):
        value = int(text[1:], 16)
    elif text.lower().startswith("0x"):
        value = int(text[2:], 16)
    else:
        value = int(text, 10)
    return value


def asm_label_from_path(path):
    """Derive a RASM-safe label from a new source file's basename."""
    stem = os.path.splitext(os.path.basename(path))[0]
    label = re.sub(r"[^A-Za-z0-9_]", "_", stem)
    if not label:
        label = "appicon"
    if label[0].isdigit():
        label = "icon_" + label
    return label


def load_asm_icon(path):
    widths = {}
    heights = {}
    modes = {}
    bare_labels = []
    bitmap = bytearray()

    with open(path, encoding="ascii") as source:
        for lineno, raw in enumerate(source, 1):
            code = raw.split(";", 1)[0].strip()
            if not code:
                continue
            match = ASM_EQU_RE.fullmatch(code)
            if match:
                label, kind, value_text = match.groups()
                try:
                    value = _asm_int(value_text)
                except ValueError as error:
                    raise ValueError(
                        f"{path}:{lineno}: invalid {kind} value {value_text!r}"
                    ) from error
                kind = kind.lower()
                dimensions = widths if kind == "w" else \
                             heights if kind == "h" else modes
                if label in dimensions:
                    raise ValueError(f"{path}:{lineno}: duplicate {label}_{kind}")
                dimensions[label] = value
                continue
            match = ASM_DB_RE.fullmatch(code)
            if match:
                operands = [operand.strip() for operand in match.group(1).split(",")]
                if not operands or any(not operand for operand in operands):
                    raise ValueError(f"{path}:{lineno}: malformed db directive")
                for operand in operands:
                    try:
                        value = _asm_int(operand)
                    except ValueError as error:
                        raise ValueError(
                            f"{path}:{lineno}: invalid byte {operand!r}"
                        ) from error
                    if not 0 <= value <= 255:
                        raise ValueError(
                            f"{path}:{lineno}: byte {operand!r} is outside 0..255"
                        )
                    bitmap.append(value)
                continue
            match = ASM_LABEL_RE.fullmatch(code)
            if match:
                bare_labels.append(match.group(1))

    pairs = set(widths).intersection(heights)
    labelled_pairs = [label for label in bare_labels if label in pairs]
    if len(labelled_pairs) == 1:
        label = labelled_pairs[0]
    elif len(pairs) == 1:
        label = next(iter(pairs))
    elif not pairs:
        raise ValueError(f"{path}: missing matching <label>_w and <label>_h")
    else:
        raise ValueError(f"{path}: contains more than one icon definition")

    wbytes, height = widths[label], heights[label]
    mode = modes.get(label, 1)
    if mode not in (1, 7):
        raise ValueError(f"{path}: unsupported icon packing mode {mode}")
    if wbytes <= 0 or height <= 0:
        raise ValueError(f"{path}: icon dimensions must be positive")
    if mode == 7 and wbytes & 1:
        raise ValueError(
            f"{path}: Screen-7 width must be an even byte count "
            "(four-pixel editor cells)"
        )
    expected = wbytes * height
    if len(bitmap) != expected:
        width_px = wbytes * (4 if mode == 1 else 2)
        raise ValueError(
            f"{path}: expected {expected} bitmap bytes for "
            f"{width_px}x{height}, got {len(bitmap)}"
        )
    icon = {
        "w": wbytes if mode == 1 else wbytes // 2,
        "h": height,
        "codec": mode,
        "grid": decode_icon(bitmap, 0, wbytes, height) if mode == 1
                else decode_icon16(bitmap, 0, wbytes, height),
    }
    return [icon], label


def save_asm_icon(path, icons, label):
    if len(icons) != 1:
        raise ValueError("an icon ASM source contains exactly one icon")
    if not label or not ASM_NAME_RE.fullmatch(label):
        raise ValueError(f"invalid RASM label {label!r}")
    mode = icons[0].get("codec", 1)
    if mode not in (1, 7):
        raise ValueError(f"unsupported icon packing mode {mode}")
    icon = icons[0]
    editor_wbytes, height = icon["w"], icon["h"]
    if editor_wbytes <= 0 or height <= 0:
        raise ValueError("icon dimensions must be positive")
    if len(icon["grid"]) != height or any(
            len(row) != editor_wbytes * 4 for row in icon["grid"]):
        raise ValueError("icon grid does not match its dimensions")
    colors = 4 if mode == 1 else 16
    if any(not 0 <= pen < colors for row in icon["grid"] for pen in row):
        raise ValueError(f"mode {mode} icon contains a pen outside 0..{colors - 1}")
    wbytes = editor_wbytes if mode == 1 else editor_wbytes * 2
    bitmap = encode_icon(icon["grid"], wbytes, height) if mode == 1 \
             else encode_icon16(icon["grid"], wbytes, height)
    width_px = editor_wbytes * 4

    with open(path, "w", encoding="ascii", newline="\n") as target:
        target.write(
            f"; generated by GEOBENCH iconedit ({width_px}x{height} px)\n"
        )
        if mode == 7:
            target.write(
                f"{label + '_mode':<16} equ   7"
                "            ; native MSX Screen-7 4bpp\n"
            )
        target.write(
            f"{label + '_w':<16} equ   {wbytes}"
            f"            ; width in packed bytes ({width_px}px)\n"
        )
        target.write(
            f"{label + '_h':<16} equ   {height}"
            "            ; height in rows\n"
        )
        target.write(f"{label}\n")
        for row in range(height):
            start = row * wbytes
            values = ",".join(f"#{value:02X}"
                              for value in bitmap[start:start + wbytes])
            target.write(f"                db    {values}\n")

# --- embedded .APP icon ----------------------------------------------------

APP_ICON_OFF = 16
APP_ICON_WB = ICON_WB
APP_ICON_H = ICON_H
APP_ICON_LEN = APP_ICON_WB * APP_ICON_H


def load_app_icon(path):
    data = bytearray(open(path, "rb").read())
    try:
        _, resources = parse_resources(data)
    except ValueError as error:
        raise ValueError(f"{path}: application has no editable GBAP icon") from error
    icons = []
    for resource in resources:
        codec = resource["codec"]
        width = resource["wbytes"]
        height = resource["height"]
        offset = resource["offset"]
        if codec == CODEC_MODE1:
            grid = decode_icon(data, offset, width, height)
            editor_width = width
        elif codec == CODEC_SCREEN7:
            grid = decode_icon16(data, offset, width, height)
            editor_width = width // 2
        else:
            continue
        icons.append({
            "w": editor_width,
            "h": height,
            "codec": codec,
            "offset": offset,
            "packed_w": width,
            "grid": grid,
        })
    if not icons:
        raise ValueError(f"{path}: GBAP preamble has no editable icon resource")
    return icons, data


def save_app_icon(path, icons, data):
    _, resources = parse_resources(data)
    if len(icons) != len(resources):
        raise ValueError("APP icon resource count changed")
    for icon, resource in zip(icons, resources):
        codec = resource["codec"]
        if icon.get("codec", codec) != codec:
            raise ValueError("APP icon resource codec changed")
        if codec == CODEC_MODE1:
            bitmap = encode_icon(icon["grid"], resource["wbytes"],
                                 resource["height"])
        elif codec == CODEC_SCREEN7:
            bitmap = encode_icon16(icon["grid"], resource["wbytes"],
                                   resource["height"])
        else:
            raise ValueError(f"unsupported APP icon codec {codec}")
        start = resource["offset"]
        data[start:start + resource["length"]] = bitmap
    with open(path, "wb") as target:
        target.write(data)

# --- palette ----------------------------------------------------------------

# The Screen-7 extension entries mirror tools/picconv.py and
# lib/msx/screen7.asm. Entries 0..3 remain the configurable UI roles; these RGB
# values show the stock GEOBENCH palette in the editor.
PEN_RGB = [
    "#000080", "#ffffff", "#000000", "#ff0000",
    "#00ff00", "#0000ff", "#ffff00", "#ff00ff",
    "#00ffff", "#ff9200", "#ff9292", "#0092ff",
    "#92ff00", "#9200ff", "#929292", "#92ff92",
]
PEN_NAME = [
    "blue", "white", "black", "red",
    "green", "bright blue", "yellow", "magenta",
    "cyan", "orange", "pink", "sky blue",
    "lime", "violet", "gray", "mint",
]

# Copy/Paste Icon share this file so a SECOND iconedit window can paste an icon
# copied in the first - the workflow for moving an icon between two .IST sets.
CLIP_PATH = os.path.join(tempfile.gettempdir(), "geobench_iconedit_clip.json")

# --- slot names -------------------------------------------------------------
# The .IST format stores each icon's size but NOT its name - an icon's meaning
# comes from its POSITION in the set, the order the desktop loads them in. These
# tables mirror that order so the editor can label each slot. KEEP IN SYNC with
# the packicons.py argument lists in tools/build_kernel.sh (the source of truth).
#
# Desktop icon sets (DEFAULT.IST, REFINED.IST, any ICONS= set) - 21 resident
# system/file-type slots. Application-owned icons live in GBAP headers.
DESKTOP_SLOTS = [
    "Floppy disk",   # 0  icon_floppy
    "Clock",         # 1  icon_clock
    "Trash",         # 2  icon_trash
    "GEOBENCH",      # 3  icon_geobench
    "BASIC file",    # 4  icon_basic
    "Binary file",   # 5  icon_binary
    "Picture",       # 6  icon_picture
    "Text file",     # 7  icon_text
    "Folder",        # 8  icon_folder
    "App (.APP)",    # 9  icon_app
    "Font (.FNT)",   # 10 icon_font
    "Desktop",       # 11 icon_desktop
    "File manager",  # 12 icon_filemanager
    "SD card",       # 13 icon_sd
    "Up (..)",       # 14 icon_up
    "Screensaver",   # 15 icon_screensaver
]
# App toolchests carry their own order, keyed by file stem:
TOOL_SLOTS = {
    "PAINT": [
        "Pencil",
        "Line",
        "Rectangle",
        "Filled rectangle",
        "Circle",
        "Filled circle",
        "Fill bucket",
        "Spray",
        "Select",
        "Cut",
        "Copy",
        "Paste",
        "Undo",
    ],
}
GRID_LINE = "#404060"
CHECKER_A = "#bdbdbd"
CHECKER_B = "#8a8a8a"

# Real-size preview inset (lower-right): one icon pixel -> PREVIEW_SCALE screen px,
# so you see the final effect while editing the zoomed grid.
PREVIEW_SCALE = 2
PREVIEW_MARGIN = 12

# ----------------------------------------------------------------------------

class IconEditor(tk.Toplevel):
    # Every open editor window, so File > Open in New Window can spawn more and the
    # app quits only when the last one closes (the real Tk root stays hidden).
    _windows = []

    def __init__(self, master, path=None):
        super().__init__(master)
        IconEditor._windows.append(self)
        self.protocol("WM_DELETE_WINDOW", self.close_window)
        self.title("GEOBENCH Icon Editor")
        self.geometry("900x640")

        self.icons = []         # list of {"w","h","grid"}
        self.path = None
        self.mode = None        # "IST", "ASM", "APP", "SPR" (CPC), or "MSPR"
        self.app_data = None    # complete executable, preserved around APP icon edits
        self.asm_label = None   # source symbol for one-icon "ASM" documents
        self.msx_hotspot = (1, 0)   # hotspot for a "MSPR" sprite (x, y)
        self.index = 0
        self.scale = 24
        self.preview_scale = PREVIEW_SCALE
        self.tool = tk.StringVar(value="pen")
        self.pen = tk.IntVar(value=2)
        self.dirty = False
        self.undo_stack = []
        self.preview = None     # (tool, x0, y0, x1, y1) during a drag
        self.selection = None   # inclusive (x0, y0, x1, y1) marquee
        self.clipboard_icon = None   # {"w","h","grid"} copied by Edit > Copy Icon
        self.rng = random.Random()
        self.tool_buttons = {}
        self.tooltip_window = None
        self.tooltip_job = None

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
        m_file.add_command(label="New 4-color APP Icon ASM",
                           command=lambda: self._new_app_asm(CODEC_MODE1))
        m_file.add_command(label="New 16-color APP Icon ASM",
                           command=lambda: self._new_app_asm(CODEC_SCREEN7))
        m_file.add_command(label="New SPR", command=self._new_spr)
        m_file.add_command(label="Open...", accelerator="Ctrl+O", command=self.open_dialog)
        m_file.add_command(label="Open in New Window...", accelerator="Ctrl+Shift+O",
                           command=self.open_new_window)
        m_file.add_command(label="Save", accelerator="Ctrl+S", command=self.save)
        m_file.add_command(label="Save As...", command=self.save_as)
        m_file.add_separator()
        m_file.add_command(label="Close Window", accelerator="Ctrl+W", command=self.close_window)
        m_file.add_command(label="Quit", command=self.quit_all)
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

        # right: palette, view controls, then the compact toolchest
        right = ttk.Frame(root, padding=(8, 4))
        right.pack(side="right", fill="y")

        ttk.Label(right, text="Color", font=("TkDefaultFont", 10, "bold"))\
            .pack(anchor="w")
        self.swatches = []
        sw_frame = ttk.Frame(right)
        sw_frame.pack(anchor="w", pady=2)
        for p in range(16):
            sw = tk.Label(sw_frame, width=3, height=1, relief="raised",
                          bg=PEN_RGB[p], borderwidth=2)
            sw.grid(row=p // 4, column=p % 4, padx=2, pady=2)
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

        toolchest = ttk.LabelFrame(right, text="Toolchest", padding=4)
        toolchest.pack(anchor="w", pady=(10, 2))
        tools = [
            ("circle_fill", "Filled circle", 0, 0, None),
            ("circle", "Outline circle", 0, 1, None),
            ("rect_fill", "Filled square", 0, 2, None),
            ("rect", "Outline square", 0, 3, None),
            ("pen", "Pen", 1, 0, None),
            ("line", "Line", 1, 1, None),
            ("erase", "Eraser", 1, 2, None),
            ("bucket", "Fill bucket", 1, 3, None),
            ("spray", "Spray paint", 2, 0, None),
            ("undo", "Undo", 2, 1, self.undo),
            ("select", "Select region", 2, 2, None),
            ("copy", "Copy selection or icon", 3, 0, self.copy_icon),
            ("paste", "Paste selection or icon", 3, 1, self.paste_icon),
        ]
        for key, label, row, col, command in tools:
            self._add_tool_button(toolchest, key, label, row, col, command)
        self._select_tool("pen")

        ttk.Separator(right, orient="horizontal").pack(fill="x", pady=4)
        self.status = ttk.Label(right, text="", foreground="#666", wraplength=150)
        self.status.pack(anchor="w")
        self._select_tool(self.tool.get())

    def _add_tool_button(self, parent, key, label, row, col, command):
        """Create one fixed-size icon button in the compact toolchest."""
        holder = tk.Frame(parent, width=36, height=36, borderwidth=2,
                          relief="raised", background="#e6e6e6",
                          takefocus=1)
        holder.grid(row=row, column=col, padx=2, pady=2)
        holder.grid_propagate(False)
        icon = tk.Canvas(holder, width=28, height=28, background="#e6e6e6",
                         highlightthickness=0, cursor="hand2")
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
            widget.bind("<Enter>",
                        lambda e, w=holder, text=label: self._queue_tooltip(w, text))
            widget.bind("<Leave>", lambda e: self._hide_tooltip())
        holder.bind("<Return>", invoke)
        holder.bind("<space>", invoke)

    @staticmethod
    def _draw_tool_icon(canvas, key):
        """Draw small theme-neutral tool glyphs without external image assets."""
        fg = "#202020"
        accent = "#1769b0"
        if key == "circle_fill":
            canvas.create_oval(4, 4, 24, 24, fill=fg, outline=fg)
        elif key == "circle":
            canvas.create_oval(4, 4, 24, 24, outline=fg, width=3)
        elif key == "rect_fill":
            canvas.create_rectangle(5, 5, 23, 23, fill=fg, outline=fg)
        elif key == "rect":
            canvas.create_rectangle(5, 5, 23, 23, outline=fg, width=3)
        elif key == "pen":
            canvas.create_line(6, 22, 20, 8, fill=accent, width=5)
            canvas.create_polygon(4, 24, 7, 18, 10, 21,
                                  fill=fg, outline=fg)
        elif key == "line":
            canvas.create_line(5, 23, 23, 5, fill=fg, width=3)
            canvas.create_oval(3, 21, 7, 25, fill=accent, outline=accent)
            canvas.create_oval(21, 3, 25, 7, fill=accent, outline=accent)
        elif key == "erase":
            canvas.create_polygon(5, 19, 16, 7, 23, 14, 12, 25,
                                  fill="#ffffff", outline=fg, width=2)
            canvas.create_line(9, 21, 19, 11, fill=accent, width=2)
        elif key == "bucket":
            canvas.create_polygon(5, 12, 15, 5, 23, 15, 13, 23,
                                  fill="#ffffff", outline=fg, width=2)
            canvas.create_line(8, 13, 20, 16, fill=accent, width=3)
            canvas.create_oval(20, 20, 24, 26, fill=accent, outline=accent)
        elif key == "spray":
            canvas.create_rectangle(5, 10, 13, 24, fill="#ffffff",
                                    outline=fg, width=2)
            canvas.create_rectangle(8, 6, 15, 11, fill="#ffffff",
                                    outline=fg, width=2)
            for x, y in ((18, 8), (22, 6), (20, 13), (25, 11),
                         (17, 17), (23, 18)):
                canvas.create_oval(x - 1, y - 1, x + 1, y + 1,
                                   fill=accent, outline=accent)
        elif key == "undo":
            canvas.create_arc(5, 5, 24, 24, start=35, extent=260,
                              style="arc", outline=accent, width=4)
            canvas.create_polygon(4, 8, 11, 5, 10, 13,
                                  fill=accent, outline=accent)
        elif key == "select":
            canvas.create_rectangle(4, 4, 20, 21, outline=fg,
                                    width=2, dash=(3, 2))
            canvas.create_polygon(15, 14, 25, 20, 20, 22, 18, 27,
                                  fill=fg, outline=fg)
        elif key == "copy":
            canvas.create_rectangle(4, 4, 18, 19, fill="#ffffff",
                                    outline="#777777", width=2)
            canvas.create_rectangle(10, 10, 25, 25, fill="#ffffff",
                                    outline=fg, width=2)
        elif key == "paste":
            canvas.create_rectangle(5, 7, 23, 25, fill="#ffffff",
                                    outline=fg, width=2)
            canvas.create_rectangle(9, 3, 19, 9, fill="#aeb7c0",
                                    outline=fg, width=2)

    def _select_tool(self, key):
        self.tool.set(key)
        for name, (holder, selectable) in self.tool_buttons.items():
            holder.config(relief=("sunken" if selectable and name == key
                                  else "raised"))
        labels = {
            "pen": "Pen", "line": "Line", "erase": "Eraser",
            "bucket": "Fill bucket",
            "spray": "Spray paint", "select": "Select region",
            "rect": "Outline square", "rect_fill": "Filled square",
            "circle": "Outline circle", "circle_fill": "Filled circle",
        }
        if hasattr(self, "status"):
            self.status.config(text=f"Tool: {labels.get(key, key)}")

    def _queue_tooltip(self, widget, text):
        self._hide_tooltip()
        self.tooltip_job = self.after(
            450, lambda: self._show_tooltip(widget, text))

    def _show_tooltip(self, widget, text):
        self.tooltip_job = None
        tip = tk.Toplevel(self)
        tip.wm_overrideredirect(True)
        tip.wm_geometry(f"+{widget.winfo_rootx() + 8}"
                        f"+{widget.winfo_rooty() + widget.winfo_height() + 2}")
        ttk.Label(tip, text=text, padding=(5, 2), relief="solid")\
            .pack()
        self.tooltip_window = tip

    def _hide_tooltip(self):
        if self.tooltip_job is not None:
            self.after_cancel(self.tooltip_job)
            self.tooltip_job = None
        if self.tooltip_window is not None:
            self.tooltip_window.destroy()
            self.tooltip_window = None

    def _bind_keys(self):
        self.bind("<Control-s>", lambda e: self.save())
        self.bind("<Control-o>", lambda e: self.open_dialog())
        self.bind("<Control-O>", lambda e: self.open_new_window())   # Ctrl+Shift+O
        self.bind("<Control-w>", lambda e: self.close_window())
        self.bind("<Control-z>", lambda e: self.undo())
        self.bind("<Control-c>", lambda e: self.copy_icon())
        self.bind("<Control-v>", lambda e: self.paste_icon())
        self.bind("<Escape>", self.clear_selection)
        self.bind("<Left>",  lambda e: self.shift_current(-1, 0))
        self.bind("<Right>", lambda e: self.shift_current(1, 0))
        self.bind("<Up>",    lambda e: self.shift_current(0, -1))
        self.bind("<Down>",  lambda e: self.shift_current(0, 1))
        for k in "1234":
            self.bind(k, lambda e, p=int(k) - 1: self._select_pen(p))

    # -- windows -------------------------------------------------------------

    def open_new_window(self):
        """Open an icon source/set/cursor/app in a separate editor window."""
        p = filedialog.askopenfilename(
            title="Open in new window",
            filetypes=[("Icon / cursor / app",
                        "*.IST *.ist *.SPR *.spr *.APP *.app *.ASM *.asm"),
                       ("All files", "*.*")])
        if p:
            IconEditor(self.master, p)        # a fresh window on the shared root

    def close_window(self):
        """Close just this window; quit the app when the last one closes."""
        self._hide_tooltip()
        IconEditor._windows.remove(self)
        self.destroy()
        if not IconEditor._windows:
            self.master.destroy()             # no windows left -> end the app

    def quit_all(self):
        self.master.destroy()                 # File > Quit closes every window

    def _select_pen(self, p):
        if p >= self._palette_size():
            return
        self.pen.set(p)
        for i, sw in enumerate(self.swatches):
            sw.config(relief=("sunken" if i == p else "raised"))
        self.pen_label.config(text=f"Pen {p} ({PEN_NAME[p]})")

    def _palette_size(self):
        icon = self._cur()
        return 16 if icon and icon.get("codec", CODEC_MODE1) == CODEC_SCREEN7 \
            else 4

    def _sync_palette(self):
        size = self._palette_size()
        if self.pen.get() >= size:
            self.pen.set(2)
        for index, swatch in enumerate(self.swatches):
            if index < size:
                swatch.grid(row=index // 4, column=index % 4, padx=2, pady=2)
            else:
                swatch.grid_remove()
        self._select_pen(self.pen.get())

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
        self.app_data = None
        self.asm_label = None
        self.index = 0
        self.dirty = False
        self.undo_stack.clear()
        self.selection = None
        self.preview = None
        self._refresh_title()
        self._redraw()

    def _new_app_asm(self, codec):
        self.icons = [{
            "w": APP_ICON_WB,
            "h": APP_ICON_H,
            "codec": codec,
            "grid": [[0] * (APP_ICON_WB * 4) for _ in range(APP_ICON_H)],
        }]
        self.path = None
        self.mode = "ASM"
        self.app_data = None
        self.asm_label = None
        self.index = 0
        self.dirty = False
        self.undo_stack.clear()
        self.selection = None
        self.preview = None
        self._refresh_title()
        self._redraw()

    def _new_spr(self):
        self.icons = [{"w": CUR_W, "h": CUR_H,
                       "grid": [[0] * (CUR_W * 4) for _ in range(CUR_H)]}]
        self.path = None
        self.mode = "MSPR" if PLATFORM == 'msx2' else "SPR"
        self.app_data = None
        self.asm_label = None
        self.msx_hotspot = (1, 0)
        self.index = 0
        self.dirty = False
        self.undo_stack.clear()
        self.selection = None
        self.preview = None
        self._refresh_title()
        self._redraw()

    def open_dialog(self):
        p = filedialog.askopenfilename(
            title="Open icon source, set, cursor, or application",
            filetypes=[("Icon / cursor / app",
                        "*.IST *.ist *.SPR *.spr *.APP *.app *.ASM *.asm"),
                       ("All files", "*.*")])
        if p:
            self.open_file(p)

    def open_file(self, path):
        try:
            ext = os.path.splitext(path)[1].lower()
            self.app_data = None
            self.asm_label = None
            if ext == ".ist":
                self.icons = load_ist(path)
                self.mode = "IST"
            elif ext == ".asm":
                self.icons, self.asm_label = load_asm_icon(path)
                self.mode = "ASM"
            elif ext == ".app":
                self.icons, self.app_data = load_app_icon(path)
                self.mode = "APP"
            elif ext == ".spr":
                # Auto-detect the cursor kind by size (unambiguous): 66 bytes = an
                # MSX2 V9938 hardware sprite, 256 = a CPC Mode-1 masked cursor. No
                # --platform flag needed to open the right one.
                data = open(path, "rb").read()
                if len(data) == MSX_SPR_LEN:
                    grid, self.msx_hotspot = decode_msx_sprite(data)
                    self.icons = [{"w": 4, "h": 16, "grid": grid}]
                    self.mode = "MSPR"
                elif len(data) == CPC_SPR_LEN:
                    self.icons = [{"w": CUR_W, "h": CUR_H,
                                   "grid": decode_cursor_phase0(data)}]
                    self.mode = "SPR"
                else:
                    raise ValueError(f"{path}: not a cursor .SPR (expected "
                                     f"{MSX_SPR_LEN} bytes for MSX2 or {CPC_SPR_LEN} "
                                     f"for CPC, got {len(data)})")
            else:
                raise ValueError(f"unknown extension: {ext}")
        except Exception as e:
            messagebox.showerror("Open failed", str(e))
            return
        self.path = path
        self.index = 0
        self.dirty = False
        self.undo_stack.clear()
        self.selection = None
        self.preview = None
        self._refresh_title()
        self._redraw()

    def save(self):
        if self.path is None:
            return self.save_as()
        try:
            if self.mode == "IST":
                save_ist(self.path, self.icons)
            elif self.mode == "ASM":
                save_asm_icon(self.path, self.icons, self.asm_label)
            elif self.mode == "APP":
                save_app_icon(self.path, self.icons, self.app_data)
            elif self.mode == "MSPR":
                with open(self.path, "wb") as f:
                    f.write(encode_msx_sprite(self.icons[0]["grid"], self.msx_hotspot))
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
        default_ext = ".APP" if self.mode == "APP" else \
                      ".ASM" if self.mode == "ASM" else \
                      ".IST" if self.mode == "IST" else ".SPR"
        kinds = [("Application", "*.APP")] if self.mode == "APP" else \
                [("Icon source", "*.ASM")] if self.mode == "ASM" else \
                [("Icon set", "*.IST"), ("Cursor", "*.SPR")]
        p = filedialog.asksaveasfilename(
            defaultextension=default_ext,
            filetypes=kinds)
        if p:
            if self.mode == "ASM" and self.asm_label is None:
                self.asm_label = asm_label_from_path(p)
            self.path = p
            self.save()

    # -- icon ops ------------------------------------------------------------

    def clear_current(self):
        ic = self._cur()
        if ic is None:
            return
        self._push_undo()
        self.selection = None
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
            self.selection = None
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
        self.selection = None
        self._touched()

    def _clip_save(self):
        """Share the clipboard with other iconedit windows (a temp file)."""
        try:
            with open(CLIP_PATH, "w") as f:
                json.dump(self.clipboard_icon, f)
        except OSError:
            pass

    def _clip_load(self):
        """Pick up an icon another iconedit window may have copied since."""
        try:
            with open(CLIP_PATH) as f:
                self.clipboard_icon = json.load(f)
        except (OSError, ValueError):
            pass

    def copy_icon(self):
        ic = self._cur()
        if ic is None:
            return
        if self.selection is not None:
            self.clipboard_icon = copy_grid_region(ic["grid"], self.selection)
            self.clipboard_icon.update({
                "kind": "selection",
                "codec": ic.get("codec", CODEC_MODE1),
            })
            width = self.clipboard_icon["pixel_w"]
            height = self.clipboard_icon["h"]
            description = f"{width}x{height} selection"
        else:
            self.clipboard_icon = {
                "kind": "icon",
                "w": ic["w"],
                "pixel_w": ic["w"] * 4,
                "h": ic["h"],
                "codec": ic.get("codec", CODEC_MODE1),
                "grid": [row[:] for row in ic["grid"]],
            }
            description = f"{ic['w'] * 4}x{ic['h']} icon"
        self._clip_save()                            # so a second window can paste it
        self.status.config(text=f"Copied {description}")

    def paste_icon(self):
        self._clip_load()                            # share across iconedit windows
        if self.clipboard_icon is None:
            messagebox.showinfo("Paste Icon", "Nothing copied yet.")
            return
        ic = self._cur()
        if ic is None:
            return
        cb = self.clipboard_icon
        if cb.get("kind") == "selection":
            dst_x, dst_y = (self.selection[0], self.selection[1]) \
                if self.selection is not None else (0, 0)
            grid, bounds = pasted_grid(
                ic["grid"], cb, dst_x, dst_y, self._palette_size() - 1)
            if grid is ic["grid"]:
                self.status.config(text="Paste made no changes")
                return
            self._push_undo()
            ic["grid"] = grid
            self.selection = bounds
            self.preview = None
            self._touched()
            self.status.config(
                text=f"Pasted {cb.get('pixel_w', len(cb['grid'][0]))}"
                     f"x{cb['h']} selection")
            return

        cb_w = cb.get("w")
        if cb_w is None:
            cb_w = (cb.get("pixel_w", len(cb["grid"][0])) + 3) // 4
        if self.mode in ("SPR", "MSPR", "APP", "ASM"):
            # Single-resource documents keep their dimensions: paste top-left,
            # clipping or padding rather than producing an invalid file.
            grid = [[0] * (ic["w"] * 4) for _ in range(ic["h"])]
            for y in range(ic["h"]):
                for x in range(ic["w"] * 4):
                    inside = (y < cb["h"] and y < len(cb["grid"])
                              and x < cb_w * 4
                              and x < len(cb["grid"][y]))
                    value = cb["grid"][y][x] if inside else 0
                    grid[y][x] = max(
                        0, min(int(value), self._palette_size() - 1))
            if grid == ic["grid"]:
                self.status.config(text="Paste made no changes")
                return
            self._push_undo()
            ic["grid"] = grid
        else:
            # IST icons keep their own size: replace this one wholesale
            grid = [[max(0, min(int(value), 3)) for value in row]
                    for row in cb["grid"]]
            if ic["w"] == cb_w and ic["h"] == cb["h"] and ic["grid"] == grid:
                self.status.config(text="Paste made no changes")
                return
            self._push_undo()
            ic["w"] = cb_w
            ic["h"] = cb["h"]
            ic["codec"] = CODEC_MODE1
            ic["grid"] = grid
        self.selection = None
        self.preview = None
        self._touched()
        self.status.config(text=f"Pasted {cb_w * 4}x{cb['h']} icon")

    def prev_icon(self):
        if not self.icons:
            return
        self.index = (self.index - 1) % len(self.icons)
        self.selection = None
        self.preview = None
        self._redraw()

    def next_icon(self):
        if not self.icons:
            return
        self.index = (self.index + 1) % len(self.icons)
        self.selection = None
        self.preview = None
        self._redraw()

    def shift_current(self, dx, dy):
        ic = self._cur()
        if ic is None:
            return "break"
        shifted = shift_grid(ic["grid"], dx, dy)
        if shifted != ic["grid"]:
            self._push_undo()
            ic["grid"] = shifted
            self.selection = None
            self.preview = None
            self._touched()
        return "break"

    def clear_selection(self, _event=None):
        if self.selection is not None or self.preview is not None:
            self.selection = None
            self.preview = None
            self._redraw()
            self.status.config(text="Selection cleared")
        return "break"

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
        tool = self.tool.get()
        if tool == "select":
            self.preview = (tool, cell[0], cell[1], cell[0], cell[1])
            self._redraw()
            return
        if tool == "bucket":
            ic = self._cur()
            target = ic["grid"][cell[1]][cell[0]]
            if target == self.pen.get():
                self.status.config(text="Area already uses that color")
                return
            self._push_undo()
            self.selection = None
            changed = flood_fill_grid(
                ic["grid"], cell[0], cell[1], self.pen.get())
            self.preview = None
            self._touched()
            self.status.config(text=f"Filled {len(changed)} pixels")
            return

        self._push_undo()
        self.selection = None
        if tool in ("pen", "erase"):
            self._paint(cell[0], cell[1], 0 if tool == "erase" else self.pen.get())
            self.preview = (tool, cell[0], cell[1], cell[0], cell[1])
        elif tool == "spray":
            self._spray_at(cell[0], cell[1])
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
        elif tool == "spray":
            self._spray_line(x0, y0, cell[0], cell[1])
            self.preview = (tool, cell[0], cell[1], cell[0], cell[1])
        else:
            self.preview = (tool, x0, y0, cell[0], cell[1])
            self._redraw()

    def _on_release(self, ev):
        if self.preview is None:
            return
        tool, x0, y0, x1, y1 = self.preview
        if tool in ("rect", "rect_fill"):
            self._draw_rect(
                x0, y0, x1, y1, self.pen.get(), tool == "rect_fill")
        elif tool in ("circle", "circle_fill"):
            self._draw_ellipse(
                x0, y0, x1, y1, self.pen.get(), tool == "circle_fill")
        elif tool == "line":
            self._line(x0, y0, x1, y1, self.pen.get())
        elif tool == "select":
            self.selection = normalize_rect(x0, y0, x1, y1)
            self.preview = None
            self._redraw()
            width = self.selection[2] - self.selection[0] + 1
            height = self.selection[3] - self.selection[1] + 1
            self.status.config(text=f"Selected {width}x{height} pixels")
            return
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

    def _spray_at(self, x, y):
        ic = self._cur()
        for px, py in spray_points(
                ic["w"] * 4, ic["h"], x, y, self.rng):
            self._paint(px, py, self.pen.get())

    def _spray_line(self, x0, y0, x1, y1):
        """Pulse the spray along a Bresenham path so fast drags have no gaps."""
        dx = abs(x1 - x0); sx = 1 if x0 < x1 else -1
        dy = -abs(y1 - y0); sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self._spray_at(x0, y0)
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
                           "codec": i.get("codec", CODEC_MODE1),
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
        self.selection = None
        self.preview = None
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
        self._sync_palette()
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
            if tool == "line":
                col = PEN_RGB[self.pen.get()]
                self.canvas.create_line(
                    ox + (x0 + 0.5) * s, oy + (y0 + 0.5) * s,
                    ox + (x1 + 0.5) * s, oy + (y1 + 0.5) * s,
                    fill=col, width=3)
            elif tool in ("rect", "rect_fill", "circle", "circle_fill",
                          "select"):
                lo_x, lo_y, hi_x, hi_y = normalize_rect(x0, y0, x1, y1)
                rx = ox + lo_x * s
                ry = oy + lo_y * s
                rxe = ox + (hi_x + 1) * s
                rye = oy + (hi_y + 1) * s
                if tool == "select":
                    self.canvas.create_rectangle(rx, ry, rxe, rye,
                                                 outline="#00d8ff", width=2,
                                                 dash=(6, 4))
                else:
                    col = PEN_RGB[self.pen.get()]
                    filled = tool.endswith("_fill")
                    options = {
                        "outline": col,
                        "width": 2,
                        "fill": col if filled else "",
                    }
                    if filled:
                        options["stipple"] = "gray50"
                    if tool.startswith("rect"):
                        self.canvas.create_rectangle(rx, ry, rxe, rye,
                                                     **options)
                    else:
                        self.canvas.create_oval(rx, ry, rxe, rye, **options)
        if self.selection is not None:
            x0, y0, x1, y1 = self.selection
            self.canvas.create_rectangle(
                ox + x0 * s, oy + y0 * s,
                ox + (x1 + 1) * s, oy + (y1 + 1) * s,
                outline="#00d8ff", width=2, dash=(6, 4),
                tags="selection")
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

    def _slot_names(self):
        """The slot-name list for the open set (None for cursors): the app-specific
        toolchest order if known, else the desktop icon-set order."""
        if self.mode != "IST":
            return None
        stem = os.path.splitext(os.path.basename(self.path))[0].upper() if self.path else ""
        return TOOL_SLOTS.get(stem, DESKTOP_SLOTS)

    def _info_text(self):
        ic = self._cur()
        if ic is None:
            return "—"
        w, h, i, n = ic["w"] * 4, ic["h"], self.index, len(self.icons)
        if self.mode == "SPR":
            return f"cursor  ·  {w}x{h} px"
        if self.mode == "APP":
            colors = 16 if ic.get("codec", 1) == CODEC_SCREEN7 else 4
            return f"application icon  ·  {colors} colors  ·  {w}x{h} px  ·  {i + 1}/{n}"
        if self.mode == "ASM":
            label = self.asm_label or "new source"
            colors = 16 if ic.get("codec", 1) == CODEC_SCREEN7 else 4
            return f"icon source  ·  {label}  ·  {colors} colors  ·  {w}x{h} px"
        names = self._slot_names()
        name = f"{names[i]}  ·  " if names and i < len(names) else ""
        return f"slot {i}  ·  {name}{w}x{h} px  ·  {i + 1}/{n}"

    def _refresh_title(self):
        name = os.path.basename(self.path) if self.path else f"(untitled {self.mode or 'IST'})"
        mark = "*" if self.dirty else ""
        self.title(f"GEOBENCH Icon Editor — {mark}{name}")


def main():
    global PLATFORM
    argv = sys.argv[1:]
    if len(argv) >= 2 and argv[0] == '--platform':
        PLATFORM, argv = argv[1], argv[2:]
    path = argv[0] if argv else None
    root = tk.Tk()
    root.withdraw()                      # the real root stays hidden; editors are Toplevels
    IconEditor(root, path)               # the first window (File > Open in New Window adds more)
    root.mainloop()


if __name__ == "__main__":
    main()
