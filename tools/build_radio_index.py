#!/usr/bin/env python3
"""Genera data/radio.json a partir de las carpetas assets/audio/radio/<emisora>/.

Cada carpeta es una emisora. Opcionalmente puede tener un station.json con
{"name": "...", "genre": "...", "color": "#RRGGBB"}. Las pistas (.ogg/.mp3/.wav)
se ordenan por nombre. Se guarda la duración si mutagen está instalado
(pip install mutagen); si no, el juego la calcula al cargar.
"""
import json, os, sys

ROOT = "assets/audio/radio"


def duration(path):
    try:
        import mutagen  # type: ignore
        f = mutagen.File(path)
        return round(float(f.info.length), 2) if f and f.info else 0.0
    except Exception:  # noqa: BLE001
        return 0.0


def main():
    stations = []
    if os.path.isdir(ROOT):
        for folder in sorted(os.listdir(ROOT)):
            d = os.path.join(ROOT, folder)
            if not os.path.isdir(d):
                continue
            meta = {"name": folder.replace("_", " ").upper(), "genre": "", "color": "#D4A72C"}
            mp = os.path.join(d, "station.json")
            if os.path.exists(mp):
                meta.update(json.load(open(mp, encoding="utf-8")))
            tracks = []
            for f in sorted(os.listdir(d)):
                if f.lower().endswith((".ogg", ".mp3", ".wav")):
                    p = os.path.join(d, f)
                    tracks.append({"title": os.path.splitext(f)[0], "path": "res://" + p.replace(os.sep, "/"), "seconds": duration(p)})
            if tracks:
                stations.append({"id": folder, **meta, "tracks": tracks})
    out = {"version": 1, "notes": "Generado por tools/build_radio_index.py. Música original o con licencia.", "stations": stations}
    json.dump(out, open("data/radio.json", "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    print(len(stations), "emisoras,", sum(len(s["tracks"]) for s in stations), "pistas")


if __name__ == "__main__":
    sys.exit(main())
