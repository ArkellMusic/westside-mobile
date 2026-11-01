#!/usr/bin/env python3
"""Empaqueta las texturas del terreno en dos tiras verticales (albedo y normal) que Godot
importa como Texture2DArray (una capa por textura). Uso: python3 tools/build_terrain_arrays.py"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
LAYERS = ["grass", "grass_mix", "hill_grass", "forest", "desert_red", "desert_rocks", "desert_cracked",
          "sand", "beach_aerial", "cliff", "coast_rocks", "snow", "dirt_road", "seabed", "coral_gravel"]

# Medias de color objetivo (algunas fotos vienen muy oscuras o amarillas): se corrige la
# ganancia por canal para que las capas casen entre sí.
TARGET = {
    "grass": (78, 96, 46), "grass_mix": (92, 92, 52), "hill_grass": (98, 100, 52), "forest": (52, 68, 38),
    "desert_cracked": (182, 132, 98), "desert_rocks": (150, 104, 74), "coast_rocks": (96, 88, 76),
}

def fix(name, im, kind):
    if kind != "albedo" or name not in TARGET:
        return im
    from PIL import ImageStat
    mean = ImageStat.Stat(im.resize((64, 64))).mean
    gains = [max(0.4, min(6.0, t / max(m, 1.0))) for t, m in zip(TARGET[name], mean)]
    chans = [c.point(lambda v, g=g: min(255, int(v * g))) for c, g in zip(im.split(), gains)]
    return Image.merge("RGB", chans)

def strip(kind, size):
    out = Image.new("RGB", (size, size * len(LAYERS)))
    for i, name in enumerate(LAYERS):
        im = Image.open(os.path.join(ROOT, name, kind + ".jpg")).convert("RGB").resize((size, size), Image.LANCZOS)
        im = fix(name, im, kind)
        out.paste(im, (0, i * size))
    path = os.path.join(ROOT, "terrain", kind + "_array.jpg")
    out.save(path, quality=90)
    print(path, out.size)

strip("albedo", 1024)
strip("normal", 512)
