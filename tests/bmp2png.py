#!/usr/bin/env python3
"""Convert a 24-bit uncompressed BMP (ZEsarUX save-screen output) to PNG. Pure stdlib."""
import struct, zlib, sys


def convert(src, dst):
    d = open(src, "rb").read()
    off = struct.unpack_from("<I", d, 10)[0]
    w, h = struct.unpack_from("<ii", d, 18)
    bpp = struct.unpack_from("<H", d, 28)[0]
    if bpp != 24:
        raise SystemExit(f"expected 24bpp, got {bpp}")
    flip = h > 0
    h = abs(h)
    stride = (w * 3 + 3) & ~3
    rows = []
    for y in range(h):
        sy = (h - 1 - y) if flip else y
        base = off + sy * stride
        line = bytearray(b"\x00")          # PNG filter byte: none
        for x in range(w):
            b, g, r = d[base + x * 3: base + x * 3 + 3]
            line += bytes((r, g, b))       # BMP is BGR
        rows.append(bytes(line))
    raw = b"".join(rows)

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(dst, "wb").write(png)
    return w, h


if __name__ == "__main__":
    print(convert(sys.argv[1], sys.argv[2]))
