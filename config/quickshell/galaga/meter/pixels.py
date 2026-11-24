"""Aperture and export calculations for packed, full-range SDR RGB."""

import base64
import struct
import zlib


def png(width, height, pixels, space="capture"):
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data))
        )

    header = struct.pack(">2I5B", width, height, 8, 2, 0, 0, 0)
    result = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
    if space == "sRGB":
        result += chunk(b"sRGB", b"\0")
    elif space == "Adobe RGB":
        # Adobe RGB (1998) uses D65, a 563/256 exponent and these primaries.
        result += chunk(b"gAMA", struct.pack(">I", round(100000 * 256 / 563)))
        result += chunk(
            b"cHRM",
            struct.pack(">8I", 31270, 32900, 64000, 33000, 21000, 71000, 15000, 6000),
        )
    scanlines = b"".join(
        b"\0" + pixels[y * width * 3 : (y + 1) * width * 3] for y in range(height)
    )
    return result + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b"")


def encode_colour(rgb, space):
    if space == "Adobe RGB":

        def linear(v):
            v /= 255
            return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

        r, g, b = map(linear, rgb)
        # D65 sRGB -> D65 Adobe RGB in linear light.
        rgb = [
            255 * max(0, v) ** (256 / 563)
            for v in (0.715125 * r + 0.284875 * g, g, 0.041162 * g + 0.958838 * b)
        ]
    return [max(0, min(255, round(v))) for v in rgb]


def aperture(read, width, height, x, y, size):
    """read(x,y,n) returns one contiguous row as RGB triples."""
    half = size // 2
    left, right = max(0, x - half), min(width, x + half + 1)
    top, bottom = max(0, y - half), min(height, y + half + 1)
    values = b"".join(read(left, row, right - left) for row in range(top, bottom))
    count = (right - left) * (bottom - top)
    return [sum(values[c::3]) / count for c in range(3)], [right - left, bottom - top]


def loupe(read, width, height, x, y):
    tile = bytearray()
    for row in range(y - 5, y + 6):
        left, right = max(0, x - 5), min(width, x + 6)
        pixels = read(left, max(0, min(height - 1, row)), right - left)
        tile.extend(
            pixels[:3] * (left - x + 5) + pixels + pixels[-3:] * (x + 6 - right)
        )
    return "data:image/png;base64," + base64.b64encode(png(11, 11, tile)).decode()
