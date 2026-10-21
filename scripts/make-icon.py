#!/usr/bin/env python3
"""Draw the app icon: a black single on record-label red, cream label, offset like it's sliding out of a sleeve."""
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

S = 4096  # draw large, downsample for clean edges
OUT = pathlib.Path(__file__).resolve().parent.parent / "DeepCuts/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
RED, INK, CREAM = (200, 69, 44), (22, 20, 18), (244, 239, 230)

img = Image.new("RGB", (S, S), RED)
d = ImageDraw.Draw(img)

# Sleeve: a cream square on the left, the record slides out to the right.
sleeve = (int(S * 0.10), int(S * 0.20), int(S * 0.62), int(S * 0.80))
shadow = Image.new("L", (S, S), 0)
cx, cy, r = int(S * 0.60), S // 2, int(S * 0.33)
ImageDraw.Draw(shadow).ellipse((cx - r + 40, cy - r + 70, cx + r + 40, cy + r + 70), fill=110)
shadow = shadow.filter(ImageFilter.GaussianBlur(90))
img.paste((60, 20, 10), (0, 0), shadow)

d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=INK)
for i in range(1, 26):
    rr = r - int(r * 0.035) - i * int(r * 0.022)
    if rr < r * 0.36:
        break
    shade = 34 + (10 if i % 4 == 0 else 0)
    d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), outline=(shade, shade - 2, shade - 4), width=6)
# Sheen.
sheen = Image.new("L", (S, S), 0)
sd = ImageDraw.Draw(sheen)
for start in (300, 120):
    sd.pieslice((cx - r, cy - r, cx + r, cy + r), start, start + 22, fill=38)
sheen = sheen.filter(ImageFilter.GaussianBlur(40))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
img.paste((255, 255, 255), (0, 0), Image.composite(sheen, Image.new("L", (S, S), 0), mask))

lr = int(r * 0.34)
d.ellipse((cx - lr, cy - lr, cx + lr, cy + lr), fill=CREAM)
d.ellipse((cx - int(lr * 0.86), cy - int(lr * 0.86), cx + int(lr * 0.86), cy + int(lr * 0.86)), outline=RED, width=18)
hr = int(r * 0.035)
d.ellipse((cx - hr, cy - hr, cx + hr, cy + hr), fill=INK)

# Sleeve drawn last so the record looks tucked into it.
d.rectangle(sleeve, fill=CREAM)
x0, y0, x1, y1 = sleeve
d.rectangle((x1 - 26, y0, x1, y1), fill=(222, 214, 200))
# Two thin rules on the sleeve, like a plain record-store jacket.
for k, w in ((0.70, 30), (0.76, 14)):
    y = y0 + int((y1 - y0) * k)
    d.rectangle((x0 + 150, y, x1 - 190, y + w), fill=RED)

img.resize((1024, 1024), Image.LANCZOS).save(OUT)
print(OUT)
