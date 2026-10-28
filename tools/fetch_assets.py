#!/usr/bin/env python3
"""Descarga las texturas PBR y cielos HDRI CC0 de Poly Haven listados en
tools/assets_manifest.json a assets/textures/<id>/ y assets/sky/<id>.hdr.
Se ejecuta en GitHub Actions (el entorno de desarrollo no tiene acceso a la web)."""
import json, os, sys, urllib.request

API = "https://api.polyhaven.com"
UA = {"User-Agent": "WestsideLegacyMobile-assets/1.0"}
MAPS = {"Diffuse": "albedo", "nor_gl": "normal", "Rough": "roughness", "AO": "ao"}


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r, open(dest, "wb") as f:
        f.write(r.read())
    print("  ->", dest, os.path.getsize(dest), "bytes")


def resolve(entry, kind):
    if "slug" in entry:
        return entry["slug"]
    assets = get_json(f"{API}/assets?t={kind}&categories={entry['category']}")
    best = sorted(assets.items(), key=lambda kv: -kv[1].get("download_count", 0))
    return best[0][0]


def main():
    manifest = json.load(open("tools/assets_manifest.json"))
    credits = []
    failed = 0
    for t in manifest["textures"]:
        if os.path.exists(f"assets/textures/{t['id']}/albedo.jpg"):
            credits.append(f"{t['id']}: ya descargada (Poly Haven, CC0)")
            continue
        try:
            slug = resolve(t, "textures")
            files = get_json(f"{API}/files/{slug}")
            print(t["id"], "=", slug)
            for key, name in MAPS.items():
                if key in files and t["res"] in files[key]:
                    download(files[key][t["res"]]["jpg"]["url"], f"assets/textures/{t['id']}/{name}.jpg")
            credits.append(f"{t['id']}: {slug} (Poly Haven, CC0)")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("ERROR", t, e)
    for mdl in manifest.get("models", []):
        try:
            files = get_json(f"{API}/files/{mdl['slug']}")
            g = files["gltf"][mdl["res"]]["gltf"]
            base = f"assets/props/{mdl['id']}/"
            download(g["url"], base + os.path.basename(g["url"]))
            for rel, info in g.get("include", {}).items():
                download(info["url"], base + rel)
            credits.append(f"modelo {mdl['id']}: {mdl['slug']} (Poly Haven, CC0)")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("ERROR", mdl, e)
    for h in manifest["hdris"]:
        if os.path.exists(f"assets/sky/{h['id']}.hdr"):
            continue
        try:
            files = get_json(f"{API}/files/{h['slug']}")
            download(files["hdri"][h["res"]]["hdr"]["url"], f"assets/sky/{h['id']}.hdr")
            credits.append(f"cielo {h['id']}: {h['slug']} (Poly Haven, CC0)")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("ERROR", h, e)
    with open("assets/CREDITOS.md", "w") as f:
        f.write("# Créditos de recursos\n\nTexturas y cielos de Poly Haven (https://polyhaven.com), licencia CC0.\n\n")
        f.write("\n".join(f"- {c}" for c in credits) + "\n")
    print("fallos:", failed)
    sys.exit(1 if failed > 3 else 0)


if __name__ == "__main__":
    main()
