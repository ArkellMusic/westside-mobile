#!/usr/bin/env python3
"""Sustituye el texto/escudo de condado de la librea del coche patrulla por 'SOUTH VEYRA' / 'SVPD'."""
import sys
from PIL import Image, ImageDraw, ImageFont
p = sys.argv[1]
im = Image.open(p).convert("RGB")
W = im.size[0]
k = W / 1024.0
panel = (196, 200, 208)
def box(x0, y0, x1, y1):
    return tuple(int(v * k) for v in (x0, y0, x1, y1))
d = ImageDraw.Draw(im)
font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
try:
    font = ImageFont.truetype(font_path, int(34 * k))
except Exception:
    font = ImageFont.load_default()
# Panel superior: texto normal.
d.rectangle(box(255, 35, 540, 67), fill=panel)
txt = Image.new("RGB", (int(300 * k), int(44 * k)), panel)
ImageDraw.Draw(txt).text((int(4 * k), int(2 * k)), "SOUTH VEYRA", font=font, fill=(17, 17, 20))
txt = txt.transform(txt.size, Image.AFFINE, (1, 0.28, 0, 0, 1, 0), resample=Image.BICUBIC, fillcolor=panel)
im.paste(txt, box(262, 27, 262, 27)[:2])
# Panel inferior: el mismo texto girado 180 grados.
d.rectangle(box(172, 450, 450, 494), fill=panel)
im.paste(txt.rotate(180), box(180, 447, 180, 447)[:2])
# Escudo: lo cubre un emblema simple.
d.rectangle(box(425, 735, 575, 935), fill=(12, 12, 12))
cx, cy = int(500 * k), int(838 * k)
r = int(58 * k)
d.polygon([(cx - r, cy - r), (cx + r, cy - r), (cx + r, cy + int(0.2 * r)), (cx, cy + int(1.5 * r)), (cx - r, cy + int(0.2 * r))], outline=(235, 235, 235), width=int(5 * k))
f2 = ImageFont.truetype(font_path, int(28 * k)) if font_path else font
d.text((cx - int(37 * k), cy - int(16 * k)), "SVPD", font=f2, fill=(235, 235, 235))
im.save(p, quality=90)
