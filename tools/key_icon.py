"""Keys a generated badge off its flat blue background into a transparent PNG.

usage: key_icon.py <raw image> <out png> [<reference png for size>]
"""
import sys
from PIL import Image, ImageFilter

src, out = sys.argv[1], sys.argv[2]
ref = sys.argv[3] if len(sys.argv) > 3 else None

im = Image.open(src).convert("RGB")
w, h = im.size

# Background colour from the four corners.
corners = [im.getpixel(p) for p in ((2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3))]
bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))
print("background", bg)

px = im.load()
alpha = Image.new("L", (w, h))
ap = alpha.load()
for y in range(h):
    for x in range(w):
        r, g, b = px[x, y]
        # Blueness: how far blue rises above the warm channels. Gold sits near
        # or below zero; the key colour sits near bg_blue - max(bg_r, bg_g).
        key = b - max(r, g)
        full = bg[2] - max(bg[0], bg[1])
        a = 1.0 - (key - 20) / (full - 60)
        a = 0.0 if a < 0 else 1.0 if a > 1 else a
        ap[x, y] = int(a * 255)
        if 0 < a < 1 or key > 0:
            # Remove blue spill on antialiased edges.
            px[x, y] = (r, g, min(b, max(r, g)))

alpha = alpha.filter(ImageFilter.MedianFilter(3))
rgba = im.copy()
rgba.putalpha(alpha)

bbox = alpha.point(lambda v: 255 if v > 8 else 0).getbbox()
rgba = rgba.crop(bbox)
cw, ch = rgba.size
side = int(max(cw, ch) * 1.06)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.paste(rgba, ((side - cw) // 2, (side - ch) // 2))

size = Image.open(ref).size if ref else (256, 256)
canvas = canvas.resize(size, Image.LANCZOS)
canvas.save(out, optimize=True)

a = canvas.getchannel("A")
hist = a.histogram()
print("saved", out, canvas.size, "transparent px", hist[0], "opaque px", hist[255],
      "corner alpha", [a.getpixel(p) for p in ((0, 0), (size[0] - 1, size[1] - 1))])
