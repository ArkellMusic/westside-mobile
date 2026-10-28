#!/usr/bin/env python3
"""Descarga la radio de WESTSIDE LEGACY desde la carpeta pública de Drive
(Radio_original), convierte el audio a OGG Vorbis ligero para móvil y genera
data/radio.json. Se ejecuta en GitHub Actions (.github/workflows/radio.yml).

Estructura esperada en Drive: Canciones/<NN_Emisora>/*.mp3|flac|wav,
Anuncios/*.wav|mp3, Sintonizar/*.wav, CREDITOS.txt."""
import json, os, re, shutil, subprocess, sys

FOLDER = "https://drive.google.com/drive/folders/1ro4zPFqfKKwTAk25H0MBuPgbBUodTQM9"
SRC = "radio_src"
OUT = "assets/audio/radio"
AUDIO = (".mp3", ".flac", ".wav", ".ogg", ".m4a")

STATIONS = {
    "PerreoSur": ("Perreo Sur", "97.1", "#E8485F"),
    "PulsoFM": ("Pulso FM", "106.3", "#36C5F0"),
    "RadioSouthVeyra": ("Radio South Veyra", "95.5", "#D4A72C"),
    "Motoveyra": ("MOTOVEYRA", "88.8", "#B05CFF"),
    "WestbrookRock": ("Westbrook Rock", "100.2", "#C0392B"),
    "RuidoBlanco": ("Ruido Blanco", "93.6", "#EEEEEE"),
    "VeyraPopHits": ("Veyra Pop Hits", "102.9", "#FF7AC6"),
    "VeyraGold": ("Veyra Gold", "98.4", "#F5C542"),
    "WestbrookUnderground": ("Westbrook Underground", "101.7", "#7F8C8D"),
    "BassCathedral": ("Bass Cathedral", "104.6", "#00E5A0"),
    "VelvetFM": ("Velvet FM", "91.3", "#9B2D5B"),
    "Desierto879": ("Desierto 87.9", "87.9", "#D9874A"),
    "IslaRoots": ("Isla Roots", "99.9", "#2ECC71"),
}


def run(cmd):
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=False)


def convert(src, dst, kbps_q="2"):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-vn", "-ac", "2", "-ar", "44100",
                        "-c:a", "libvorbis", "-q:a", kbps_q, dst])
    return r.returncode == 0


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path],
                         capture_output=True, text=True).stdout.strip()
    try:
        return round(float(out), 2)
    except ValueError:
        return 0.0


def slug(name):
    s = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_").lower()
    return s[:60] or "pista"


def find_dir(root, name):
    for dp, dns, _ in os.walk(root):
        for d in dns:
            if d.lower() == name.lower():
                return os.path.join(dp, d)
    return None


def main():
    if not os.path.isdir(SRC):
        run([sys.executable, "-m", "gdown", "--folder", FOLDER, "-O", SRC])
    stations = []
    songs_dir = find_dir(SRC, "Canciones") or SRC
    for folder in sorted(os.listdir(songs_dir)):
        d = os.path.join(songs_dir, folder)
        if not os.path.isdir(d):
            continue
        key = re.sub(r"^\d+_", "", folder)
        name, fm, color = STATIONS.get(key, (key, "", "#D4A72C"))
        tracks = []
        for f in sorted(os.listdir(d)):
            if not f.lower().endswith(AUDIO):
                continue
            base = os.path.splitext(f)[0]
            artist, title = (base.split(" - ", 1) + [""])[:2] if " - " in base else ("", base)
            dst = f"{OUT}/{slug(key)}/{slug(base)}.ogg"
            if convert(os.path.join(d, f), dst):
                tracks.append({"title": title.strip(), "artist": artist.strip(), "path": "res://" + dst, "seconds": duration(dst)})
        if tracks:
            stations.append({"id": slug(key), "name": name, "fm": fm, "color": color, "tracks": tracks})
    ads = []
    ads_dir = find_dir(SRC, "Anuncios")
    if ads_dir:
        for f in sorted(os.listdir(ads_dir)):
            if f.lower().endswith(AUDIO):
                dst = f"{OUT}/_anuncios/{slug(os.path.splitext(f)[0])}.ogg"
                if convert(os.path.join(ads_dir, f), dst):
                    ads.append({"title": os.path.splitext(f)[0], "path": "res://" + dst, "seconds": duration(dst)})
    tune = []
    tune_dir = find_dir(SRC, "Sintonizar")
    if tune_dir:
        for f in sorted(os.listdir(tune_dir)):
            if f.lower().endswith(AUDIO):
                dst = f"{OUT}/_sintonizar/{slug(os.path.splitext(f)[0])}.ogg"
                if convert(os.path.join(tune_dir, f), dst, "4"):
                    tune.append("res://" + dst)
    for c in ["CREDITOS.txt"]:
        for dp, _, fs in os.walk(SRC):
            if c in fs:
                os.makedirs("docs", exist_ok=True)
                shutil.copy(os.path.join(dp, c), "docs/CREDITOS_MUSICA.txt")
    data = {"version": 2, "notes": "Generado por tools/fetch_radio.py desde Drive (Radio_original).",
            "stations": stations, "ads": ads, "tune": tune}
    json.dump(data, open("data/radio.json", "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print(len(stations), "emisoras,", sum(len(s["tracks"]) for s in stations), "canciones,", len(ads), "anuncios,", len(tune), "sintonías")
    return 0 if stations else 1


if __name__ == "__main__":
    sys.exit(main())
