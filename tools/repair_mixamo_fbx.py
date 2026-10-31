#!/usr/bin/env python3
"""Repara FBX binarios de Mixamo truncados (subida cortada): reconstruye la seccion Connections.
sin ella Godot no los importa ("ufbx: Failed to load"). Solo para fuentes en res://in del proyecto de trabajo.
uso: repair_fbx.py personaje|anim entrada.fbx salida.fbx [plantilla.fbx]"""
import sys, struct, re
import numpy as np
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fbxlib import read_node, objects_tolerant, top, nm

def raw_props(d, c):
    return d[c['pos'] + 25 + len(c['name']): c['pos'] + 25 + len(c['name']) + 0]  # placeholder (no usado)

def ser(name, rawprops, nprop, children, pos):
    """serializa un nodo v7500 en la posicion absoluta pos"""
    nb = name.encode('latin1')
    hdr_len = 25 + len(nb)
    body = b''
    p = pos + hdr_len + len(rawprops)
    for ch in children:
        b = ser(ch[0], ch[1], ch[2], ch[3], p)
        body += b; p += len(b)
    if children:
        body += b'\0' * 25; p += 25
    end = p
    return struct.pack('<QQQB', end, nprop, len(rawprops), len(nb)) + nb + rawprops + body

def pstr(s):
    b = s.encode('latin1'); return b'S' + struct.pack('<I', len(b)) + b
def plong(v): return b'L' + struct.pack('<q', v)

def conn(kind, child, parent, prop=None):
    raw = pstr(kind) + plong(child) + plong(parent) + (pstr(prop) if prop else b'')
    return ('C', raw, 3 + (1 if prop else 0), [])

def node_to_tuple(d, c):
    """convierte un nodo parseado en tupla serializable conservando propiedades crudas"""
    pstart = c['pos'] + 25 + len(c['name'])
    # longitud de props: leer de cabecera
    plen = struct.unpack('<Q', d[c['pos'] + 16:c['pos'] + 24])[0]
    raw = d[pstart:pstart + plen]
    return (c['name'], raw, len(c['props']), [node_to_tuple(d, x) for x in c['children']])

def get_id(c): return c['props'][0][1]

def parent_map_from(template_fbx):
    d = open(template_fbx, 'rb').read()
    t = top(d)
    ob = [x for x in t if x['name'] == 'Objects'][0]
    co = [x for x in t if x['name'] == 'Connections'][0]
    by = {get_id(c): c for c in ob['children']}
    pm = {}
    for c in co['children']:
        p = [x[1] for x in c['props']]
        if p[1] in by and by[p[1]]['name'] == 'Model' and by[p[1]]['props'][2][1] == 'LimbNode' and (p[2] not in by or by[p[2]]['name'] == 'Model'):
            ch = nm(by[p[1]]).split(':', 1)[1]
            pm[ch] = nm(by[p[2]]).split(':', 1)[1] if p[2] in by else None
    return pm

def bone_world(models, pm):
    """posicion global de cada hueso: suma de Lcl Translation (y rotacion Pre/Lcl si existe)"""
    loc = {}
    for c in models:
        short = nm(c).split(':', 1)[-1]
        t = np.zeros(3); r = np.zeros(3); pre = np.zeros(3); s = np.ones(3)
        for ch in c['children']:
            if ch['name'] == 'Properties70':
                for pp in ch['children']:
                    k = pp['props'][0][1]; v = [x[1] for x in pp['props'][4:]]
                    if k == 'Lcl Translation': t = np.array(v)
                    elif k == 'Lcl Rotation': r = np.array(v)
                    elif k == 'PreRotation': pre = np.array(v)
                    elif k == 'Lcl Scaling': s = np.array(v)
        loc[short] = (t, r, pre, s)
    def rot(e):
        a, b, c = np.radians(e)
        rx = np.array([[1, 0, 0], [0, np.cos(a), -np.sin(a)], [0, np.sin(a), np.cos(a)]])
        ry = np.array([[np.cos(b), 0, np.sin(b)], [0, 1, 0], [-np.sin(b), 0, np.cos(b)]])
        rz = np.array([[np.cos(c), -np.sin(c), 0], [np.sin(c), np.cos(c), 0], [0, 0, 1]])
        return rz @ ry @ rx
    W = {}
    def world(n):
        if n in W: return W[n]
        t, r, pre, s = loc[n]
        local = np.eye(4); local[:3, :3] = rot(pre) @ rot(r) @ np.diag(s); local[:3, 3] = t
        par = pm.get(n)
        W[n] = (world(par) @ local) if par in loc else local
        return W[n]
    for n in loc: world(n)
    return W

def repair_character(src, dst, template):
    d = open(src, 'rb').read(); n = len(d)
    os_, oe, ch, pend, partial = objects_tolerant(d)
    pm = parent_map_from(template)
    pm.setdefault('HeadTop_End', 'Head'); pm.setdefault('LeftEye', 'Head'); pm.setdefault('RightEye', 'Head')
    models = [c for c in ch if c['name'] == 'Model']
    bones = [c for c in models if c['props'][2][1] == 'LimbNode']
    meshes = [c for c in models if c['props'][2][1] == 'Mesh']
    geoms = [c for c in ch if c['name'] == 'Geometry']
    mats = [c for c in ch if c['name'] == 'Material']
    texs = [c for c in ch if c['name'] == 'Texture']
    vids = [c for c in ch if c['name'] == 'Video']
    nas = [c for c in ch if c['name'] == 'NodeAttribute']
    skins = [c for c in ch if c['name'] == 'Deformer' and c['props'][2][1] == 'Skin']
    cls = [c for c in ch if c['name'] == 'Deformer' and c['props'][2][1] == 'Cluster']
    print(src, 'bones', len(bones), 'meshes', len(meshes), 'geoms', len(geoms), 'skins', len(skins), 'clusters', len(cls), 'mats', len(mats))
    out = []
    bone_by_short = {nm(b).split(':', 1)[1]: b for b in bones}
    for b in bones:
        short = nm(b).split(':', 1)[1]
        par = pm.get(short)
        if short not in pm: print('  AVISO hueso sin padre en plantilla', short)
        out.append(conn('OO', get_id(b), get_id(bone_by_short[par]) if par in bone_by_short else 0))
    for m in meshes: out.append(conn('OO', get_id(m), 0))
    for a, b in zip(nas, bones): out.append(conn('OO', get_id(a), get_id(b)))
    assert len(geoms) == len(meshes)
    for g, m in zip(geoms, meshes): out.append(conn('OO', get_id(g), get_id(m)))
    # materiales -> cada malla (se decide por nombre en el script de horneado; aqui todos en orden)
    for m in meshes:
        for mt in mats: out.append(conn('OO', get_id(mt), get_id(m)))
    # videos -> texturas (mismo nombre)
    vby = {nm(v): v for v in vids}
    for t in texs:
        v = vby.get(nm(t))
        if v: out.append(conn('OO', get_id(v), get_id(t)))
    # skin -> geometria, clusters por suma de pesos
    W = bone_world(bones, pm)
    names = list(W.keys())
    pos_arr = np.array([W[k][:3, 3] for k in names])
    import zlib
    def arr(x):
        _, cnt, enc, p, clen = x['props'][0][1]
        raw = d[p:p + clen]
        return zlib.decompress(raw) if enc else raw
    cdata = []
    for c in cls:
        idx = wts = tl = None
        for x in c['children']:
            if x['name'] == 'Indexes': idx = np.frombuffer(arr(x), dtype='<i4')
            if x['name'] == 'Weights': wts = np.frombuffer(arr(x), dtype='<f8')
            if x['name'] == 'TransformLink': tl = np.frombuffer(arr(x), dtype='<f8').reshape(4, 4)
        cdata.append((idx, wts, tl))
    nvs = []
    for g in geoms:
        for x in g['children']:
            if x['name'] == 'Vertices': nvs.append(x['props'][0][1][1] // 3)
    # hueso de cada cluster (por TransformLink) y segmentacion en grupos por skin
    bone_of = []
    for j in range(len(cls)):
        tl = cdata[j][2]
        dist = np.linalg.norm(pos_arr - tl[3, :3], axis=1)
        q = int(np.argmin(dist))
        if dist[q] > 0.05: print('  AVISO cluster', j, 'dist', dist[q], names[q])
        bone_of.append(q)
    def candidates(ci, gi):
        nv = nvs[gi]; acc = np.zeros(nv); good = []
        e = ci
        while e < len(cls):
            idx, wts, tl = cdata[e]
            if e > ci and bone_of[e] <= bone_of[e - 1]: break
            if idx is not None:
                if idx.max() >= nv: break
                np.add.at(acc, idx, wts)
                if acc.max() > 1.03: break
            e += 1
            if acc.min() >= 0.97: good.append(e)
        return good
    def solve(ci, free, k):
        if k == len(skins): return [] if ci == len(cls) else None
        for gi in free:
            for e in reversed(candidates(ci, gi)):
                rest = solve(e, [x for x in free if x != gi], k + 1)
                if rest is not None: return [(gi, ci, e)] + rest
        return None
    sol = solve(0, list(range(len(geoms))), 0)
    assert sol, 'no se pudo segmentar los clusters'
    for k, (gi, c0, c1) in enumerate(sol):
        s = skins[k]
        out.append(conn('OO', get_id(s), get_id(geoms[gi])))
        for j in range(c0, c1):
            out.append(conn('OO', get_id(cls[j]), get_id(s)))
            out.append(conn('OO', get_id(bone_by_short[names[bone_of[j]]]), get_id(cls[j])))
        print('  skin', k, '->', nm(meshes[gi]), 'nv', nvs[gi], 'clusters', c1 - c0, [names[bone_of[j]] for j in (c0, c1 - 1)])
    ci = len(cls)
    return d, os_, ch, pend, out

def finish(d, os_, ch, pend, extra_obj, conns, takes, dst):
    head = bytearray(d[:pend])
    body = bytes(head)
    pos = len(body)
    for e in extra_obj:
        b = ser(*e, pos); body += b; pos += len(b)
    body += b'\0' * 25; pos += 25
    objects_end = pos
    body = bytearray(body)
    struct.pack_into('<Q', body, os_, objects_end)
    cb = ser('Connections', b'', 0, conns, pos)
    body += cb
    if takes is not None:
        tb = ser(*takes, len(body)); body += tb
    body += b'\0' * 25
    open(dst, 'wb').write(bytes(body))
    print('escrito', dst, len(body))

def repair_anim(src, dst, running):
    d = open(src, 'rb').read()
    os_, oe, ch, pend, partial = objects_tolerant(d)
    rd = open(running, 'rb').read()
    rt = top(rd)
    rob = [x for x in rt if x['name'] == 'Objects'][0]
    rco = [x for x in rt if x['name'] == 'Connections'][0]
    rtakes = [x for x in rt if x['name'] == 'Takes'][0]
    r_children = rob['children']
    assert len(ch) <= len(r_children)
    for a, b in zip(ch, r_children): assert a['name'] == b['name'], (a['name'], b['name'])
    # validacion de curvas: la primera es traslacion de Hips
    idmap = {get_id(b): get_id(a) for a, b in zip(ch, r_children)}
    extra = []
    import random
    rnd = random.Random(7)
    used = set(get_id(c) for c in ch)
    for b in r_children[len(ch):]:
        if b['name'] in ('AnimationCurveNode', 'AnimationLayer'):
            nid = rnd.randrange(10**8, 10**9)
            while nid in used: nid += 1
            used.add(nid); idmap[get_id(b)] = nid
            t = node_to_tuple(rd, b)
            raw = bytearray(t[1]); raw[1:9] = struct.pack('<q', nid)
            extra.append((t[0], bytes(raw), t[2], t[3]))
    conns = []
    for c in rco['children']:
        p = [x[1] for x in c['props']]
        if p[1] in idmap and (p[2] in idmap or p[2] == 0):
            conns.append(conn(p[0], idmap[p[1]], idmap.get(p[2], 0), p[3] if len(p) > 3 else None))
    takes = node_to_tuple(rd, rtakes)
    print(src, 'objetos', len(ch), 'de', len(r_children), 'conexiones', len(conns), 'extra', len(extra))
    finish(d, os_, ch, pend, extra, conns, takes, dst)

if __name__ == '__main__':
    mode, src, dst = sys.argv[1:4]
    tpl = sys.argv[4]
    if mode == 'char':
        d, os_, ch, pend, out = repair_character(src, dst, tpl)
        finish(d, os_, ch, pend, [], out, None, dst)
    else:
        repair_anim(src, dst, tpl)
