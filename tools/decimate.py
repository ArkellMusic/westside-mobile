#!/usr/bin/env python3
"""Decima una malla con meshoptimizer (simplify con atributos: normales + UV).
uso: decimate.py entrada.bin salida.bin objetivo_triangulos
entrada: int32 nv, int32 ni, float32 V[nv*3], float32 N[nv*3], float32 UV[nv*2], int32 I[ni]
salida: int32 ni_out, int32 I[ni_out] (índices sobre los mismos vértices)"""
import sys, struct
import numpy as np
import ctypes
import meshoptimizer as mo
from meshoptimizer import simplifier as _S

P = ctypes.POINTER
_f = _S.lib.meshopt_simplifyWithAttributes
_f.restype = ctypes.c_size_t
_f.argtypes = [P(ctypes.c_uint), P(ctypes.c_uint), ctypes.c_size_t, P(ctypes.c_float), ctypes.c_size_t, ctypes.c_size_t,
               P(ctypes.c_float), ctypes.c_size_t, P(ctypes.c_float), ctypes.c_size_t, P(ctypes.c_ubyte), ctypes.c_size_t,
               ctypes.c_float, ctypes.c_uint, P(ctypes.c_float)]


def simplify_attr(I, V, A, W, target_idx, err, opts):
    out = np.zeros(len(I), dtype=np.uint32)
    V = np.ascontiguousarray(V, dtype=np.float32); A = np.ascontiguousarray(A, dtype=np.float32)
    n = _f(out.ctypes.data_as(P(ctypes.c_uint)), I.ctypes.data_as(P(ctypes.c_uint)), len(I), V.ctypes.data_as(P(ctypes.c_float)),
           len(V), 12, A.ctypes.data_as(P(ctypes.c_float)), A.shape[1] * 4, W.ctypes.data_as(P(ctypes.c_float)), A.shape[1],
           P(ctypes.c_ubyte)(), target_idx, ctypes.c_float(err), opts, P(ctypes.c_float)())
    return out[:n]

def main():
    src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
    uvw = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    raw = open(src, 'rb').read()
    nv, ni = struct.unpack_from('<ii', raw, 0)
    off = 8
    V = np.frombuffer(raw, np.float32, nv * 3, off).reshape(nv, 3).copy(); off += nv * 12
    N = np.frombuffer(raw, np.float32, nv * 3, off).reshape(nv, 3).copy(); off += nv * 12
    UV = np.frombuffer(raw, np.float32, nv * 2, off).reshape(nv, 2).copy(); off += nv * 8
    I = np.frombuffer(raw, np.int32, ni, off).astype(np.uint32).copy()
    ext = float((V.max(0) - V.min(0)).max()) or 1.0
    attrs = np.concatenate([N, UV], axis=1).astype(np.float32)
    # error de posición relativo a la extensión; los atributos pesan poco para priorizar la forma
    w = np.array([0.4, 0.4, 0.4, uvw, uvw], dtype=np.float32)
    res = simplify_attr(I, V, attrs, w, target * 3, 1.0, mo.SIMPLIFY_PRUNE)
    # PRUNE puede borrar piezas pequeñas enteras: si queda casi vacío, repetir sin podar.
    if len(res) < min(target * 3 * 0.4, ni * 0.5):
        res = simplify_attr(I, V, attrs, w, target * 3, 1.0, 0)
    n = len(res)
    # si queda muy por encima del objetivo, segunda vuelta más agresiva sin topología estricta
    if n > target * 3 * 1.35:
        out2 = np.zeros(ni, dtype=np.uint32)
        n2 = mo.simplify(out2, res.copy(), V, target_index_count=target * 3, target_error=1.0, options=mo.SIMPLIFY_PRUNE)
        if n2 < n:
            res = out2[:n2]
    with open(dst, 'wb') as f:
        f.write(struct.pack('<i', len(res)))
        f.write(res.astype(np.int32).tobytes())
    print(f"{ni//3} -> {len(res)//3} (objetivo {target})")

main()
