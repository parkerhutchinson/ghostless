#!/usr/bin/env python3
# Regenerates the macOS app icon. Usage:
#   python3 tool/make_app_icon.py /tmp/app_icon_1024.png
#   then for n in 16 32 64 128 256 512: sips -z $n $n /tmp/app_icon_1024.png \
#     --out macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$n.png
#   (and copy the 1024 one there as app_icon_1024.png).
"""Draws the app icon at 1024x1024: a dark green macOS-style rounded square
with a soft shadow, and a white circle in the middle. Writes a PNG."""
import math, struct, sys, zlib

N = 1024
GREEN = (0x19, 0x45, 0x1C)
# macOS icon grid: the body is 824px, inset 100px, ~185px corners.
INSET, BODY, RADIUS = 100, 824, 185
CIRCLE_R = 0.21 * BODY  # circle diameter ~42% of the body

def rrect_sdf(x, y, cx, cy, half, r):
    qx = abs(x - cx) - (half - r)
    qy = abs(y - cy) - (half - r)
    ox, oy = max(qx, 0.0), max(qy, 0.0)
    return math.hypot(ox, oy) + min(max(qx, qy), 0.0) - r

def cover(d):  # signed distance -> coverage, ~1px anti-aliasing
    return min(max(0.5 - d, 0.0), 1.0)

def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)

c = N / 2
half = BODY / 2
rows = []
for j in range(N):
    y = j + 0.5
    row = bytearray([0])
    for i in range(N):
        x = i + 0.5
        d = rrect_sdf(x, y, c, c, half, RADIUS)
        body = cover(d)
        # Soft shadow below the body.
        ds = rrect_sdf(x, y - 12, c, c, half, RADIUS)
        shadow = 0.35 * (1 - smooth(-4, 28, ds))
        circle = cover(math.hypot(x - c, y - c) - CIRCLE_R)
        # Body color, with the white circle on top.
        r = GREEN[0] + (255 - GREEN[0]) * circle
        g = GREEN[1] + (255 - GREEN[1]) * circle
        b = GREEN[2] + (255 - GREEN[2]) * circle
        # Composite body over shadow (shadow is black).
        a = body + shadow * (1 - body)
        if a > 0:
            r, g, b = (r * body) / a, (g * body) / a, (b * body) / a
        else:
            r = g = b = 0
        row += bytes((round(r), round(g), round(b), round(a * 255)))
    rows.append(bytes(row))

def chunk(t, data):
    return struct.pack('>I', len(data)) + t + data + struct.pack('>I', zlib.crc32(t + data) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0)) \
    + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
