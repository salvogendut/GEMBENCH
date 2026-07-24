#!/usr/bin/env python3
"""Focused codec checks for picconv's GBPC four- and sixteen-colour modes."""

import struct
import tempfile
from pathlib import Path

from PIL import Image

import picconv


def main() -> None:
    pens4 = [[0, 1, 2, 3]]
    assert picconv.pack(pens4) == bytes([0x53])

    pens16 = [[0, 1, 14, 15]]
    assert picconv.pack16(pens16) == bytes([0x01, 0xEF])
    image = Image.new("RGB", (16, 1))
    image.putdata(picconv.PAL16_RGB)
    assert picconv.quantize(image, "none", picconv.PAL16_RGB)[0] == list(range(16))

    portrait = Image.new("RGB", (200, 300))
    assert picconv.prepare(portrait, 200, 0).size == (200, 300)
    assert picconv.prepare(portrait, 0, 255).size == (168, 255)
    assert picconv.prepare(portrait, 200, 255).size == (200, 255)
    assert picconv.prepare(portrait, 0, 0).size == (200, 300)

    with tempfile.TemporaryDirectory() as tmp:
        out4 = Path(tmp) / "FOUR.PIC"
        out16 = Path(tmp) / "SIXTEEN.PIC"
        picconv.save_pic(out4, pens4, 4, 1, 4)
        picconv.save_pic(out16, pens16, 4, 1, 16)
        data4 = out4.read_bytes()
        data16 = out16.read_bytes()
        assert data4[:6] == b"GBPC\x02\x01"
        assert data16[:6] == b"GBPC\x02\x07"
        assert struct.unpack("<HH", data16[6:10]) == (4, 1)
        assert data4[14:] == bytes([0x53])
        assert data16[14:] == bytes([0x01, 0xEF])

        try:
            picconv.save_pic(out16, [[0] * 516], 516, 1, 16)
        except ValueError:
            pass
        else:
            raise AssertionError("oversize Screen-7 picture was accepted")

    print("picconv codec tests passed")


if __name__ == "__main__":
    main()
