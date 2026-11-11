#!/usr/bin/env python3
"""Valida data/missions/mNN.json contra docs/MISIONES_FORMATO.md. Sale con 1 si hay errores.
Uso: python3 tools/validate_missions.py [desde] [hasta]"""
import json, os, sys

TYPES = {"phase", "scene", "call", "goto", "drive_to", "timed_drive", "steal", "fight", "defend", "sneak", "chase",
         "collect", "lose_cops", "give", "time", "toast", "checkpoint", "reward", "complete", "wait"}
LANDMARKS = {"terminal", "bus_bay", "veyra_mart", "mart_stop", "mack_house", "mack_house_curb", "mack_door", "vargas_garage",
             "vargas_front", "loco", "dre_corner", "keisha", "ghost", "viper", "pinta_listo", "comisaria", "hospital", "beach",
             "pier", "bridge", "player", "big_ray", "neighbor"}
ZONES = {"westbrook": 1, "south_veyra": 1, "san_cordova": 23, "las_brisas": 43, "northpoint": 63, "bahia_solana": 70,
         "isla_brava": 71, "isla_coral": 73, "isla_nacar": 75}
CAST = {"big_ray", "dre", "ghost", "loco", "keisha", "viper", "okafor"}
MAIN_SPEAKERS = {"Mack", "Big Ray", "Dre", "Ghost", "Loco", "K", "Viper", "Okafor"}
SPEAKER_OF = {"big_ray": "Big Ray", "dre": "Dre", "ghost": "Ghost", "loco": "Loco", "keisha": "K", "viper": "Viper", "okafor": "Okafor"}
FACTIONS = {"redline_kings", "midnight_locos", "the_syndicate", "guards", "westbrook_saints"}
NEED = {"scene": ["at", "cast", "lines"], "call": ["lines"], "goto": ["target", "objective"], "drive_to": ["target", "objective"],
        "timed_drive": ["target", "objective"], "steal": ["objective"], "fight": ["at", "count", "objective"],
        "defend": ["at", "count", "time", "objective"], "sneak": ["target", "guards", "objective"], "chase": ["at", "objective"],
        "collect": ["at", "count", "label", "objective"], "lose_cops": ["stars", "objective"], "phase": ["n"], "time": ["hour"],
        "reward": ["money"], "complete": ["next_objective"]}


def check_point(p, n, errs, where):
    if isinstance(p, str):
        if p not in LANDMARKS:
            errs.append(f"{where}: lugar desconocido '{p}'")
    elif isinstance(p, list):
        if len(p) != 2 or not (-260 <= p[0] <= 320 and -260 <= p[1] <= 260):
            errs.append(f"{where}: punto [x, z] fuera de Westbrook: {p}")
    elif isinstance(p, dict):
        z = p.get("zone")
        if z not in ZONES:
            errs.append(f"{where}: zona desconocida '{z}'")
        elif ZONES[z] > n:
            errs.append(f"{where}: la zona {z} no está abierta en la misión {n}")
        if abs(p.get("dx", 0)) > 200 or abs(p.get("dz", 0)) > 200:
            errs.append(f"{where}: dx/dz demasiado grandes")
    else:
        errs.append(f"{where}: punto inválido {p!r}")


def check_lines(lines, errs, where, allowed=None):
    if not isinstance(lines, list) or not lines:
        errs.append(f"{where}: sin líneas")
        return
    for i, l in enumerate(lines):
        for k in ("speaker", "en", "es", "t"):
            if k not in l or l[k] in ("", None):
                errs.append(f"{where} línea {i + 1}: falta '{k}'")
        if allowed is not None and l.get("speaker") not in allowed:
            errs.append(f"{where} línea {i + 1}: '{l.get('speaker')}' no está en el reparto de la escena")
        if isinstance(l.get("t"), (int, float)) and not (1.5 <= l["t"] <= 12):
            errs.append(f"{where} línea {i + 1}: t fuera de rango")


def validate(path, n):
    errs = []
    try:
        m = json.load(open(path, encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return [f"JSON inválido: {e}"]
    if m.get("id") != f"m{n:02d}" or m.get("number") != n:
        errs.append("id/number no coinciden con el fichero")
    for k in ("title", "title_es", "act", "start", "steps"):
        if k not in m:
            errs.append(f"falta '{k}'")
    if "start" in m:
        check_point(m["start"], max(n - 1, 1), errs, "start")
    steps = m.get("steps", [])
    if not (20 <= len(steps) <= 40):
        errs.append(f"{len(steps)} pasos (deben ser 22-34)")
    phases = [s.get("n") for s in steps if s.get("type") == "phase"]
    if phases != list(range(1, 8)):
        errs.append(f"fases {phases} (deben ser 1..7 en orden)")
    scenes = [s for s in steps if s.get("type") == "scene"]
    if len(scenes) < 2:
        errs.append("faltan escenas (apertura y cierre)")
    elif not scenes[0].get("title_card") or not (10 <= len(scenes[0].get("lines", [])) <= 18):
        errs.append("la escena de apertura necesita title_card y 10-16 líneas")
    if sum(1 for s in steps if s.get("type") == "checkpoint") < 3:
        errs.append("faltan checkpoints (3)")
    if not steps or steps[-1].get("type") != "complete" or steps[-2].get("type") != "reward":
        errs.append("debe terminar en reward + complete")
    play = sum(1 for s in steps if s.get("type") in ("goto", "drive_to", "timed_drive", "steal", "fight", "defend", "sneak", "chase", "collect", "lose_cops"))
    if play < 8:
        errs.append(f"solo {play} pasos jugables (mínimo 8)")
    trips = set()
    for i, s in enumerate(steps):
        t = s.get("type")
        w = f"paso {i + 1} ({t})"
        if t not in TYPES:
            errs.append(f"{w}: tipo desconocido")
            continue
        for k in NEED.get(t, []):
            if k not in s:
                errs.append(f"{w}: falta '{k}'")
        for k in ("at", "target"):
            if k in s:
                check_point(s[k], n, errs, w)
                if isinstance(s[k], dict):
                    trips.add(s[k].get("zone"))
                elif s[k] != "player":
                    trips.add("westbrook")
        if t == "scene":
            cast = s.get("cast", [])
            allowed = {"Mack"} | {SPEAKER_OF.get(c, c) for c in cast}
            check_lines(s.get("lines"), errs, w, allowed)
        elif t == "call":
            check_lines(s.get("lines"), errs, w)
        if "faction" in s and s["faction"] not in FACTIONS:
            errs.append(f"{w}: banda desconocida {s['faction']}")
        if t in ("fight", "defend") and not (1 <= s.get("count", 0) <= 6):
            errs.append(f"{w}: count 1-6")
        if t == "reward":
            for f in s.get("reputation", {}):
                if f not in FACTIONS:
                    errs.append(f"{w}: banda desconocida {f}")
    trips = {("westbrook" if z in ("westbrook", "south_veyra") else z) for z in trips if z}
    if len(trips) > 2:
        errs.append(f"demasiadas ciudades en una misión: {sorted(trips)}")
    return errs


def main():
    a = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    b = int(sys.argv[2]) if len(sys.argv) > 2 else 80
    bad = 0
    for n in range(a, b + 1):
        path = f"data/missions/m{n:02d}.json"
        if not os.path.exists(path):
            print(f"m{n:02d}: FALTA")
            bad += 1
            continue
        errs = validate(path, n)
        if errs:
            bad += 1
            print(f"m{n:02d}: {len(errs)} errores")
            for e in errs[:12]:
                print("   -", e)
    print(f"{b - a + 1 - bad} de {b - a + 1} misiones válidas")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
