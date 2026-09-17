"""Diagnostic helper: slice a GLB mesh along Z to find the car's nose.

Usage: python tools/glb_probe.py <file.glb> [mesh_index]

Prints a per-Z-slice summary (vertex count, max |x|, min/max y) for the chosen
mesh.  On an F1 car the front wing is extremely wide and very low, while the
rear wing is high up - that tells us which end of the model is the nose.
"""

import json
import struct
import sys


def load_glb(path):
    data = open(path, "rb").read()
    json_len = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + json_len])
    bin_off = 20 + json_len
    bin_len = struct.unpack("<I", data[bin_off:bin_off + 4])[0]
    return doc, data[bin_off + 8:bin_off + 8 + bin_len]


def mesh_positions(doc, blob, mesh_index):
    acc = doc["accessors"]
    views = doc["bufferViews"]
    out = []
    for prim in doc["meshes"][mesh_index]["primitives"]:
        a = acc[prim["attributes"]["POSITION"]]
        v = views[a["bufferView"]]
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = v.get("byteStride") or 12
        for i in range(a["count"]):
            out.append(struct.unpack_from("<fff", blob, off + i * stride))
    return out


def main():
    path = sys.argv[1]
    mesh_index = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    doc, blob = load_glb(path)
    for i, m in enumerate(doc["meshes"]):
        print("mesh", i, m.get("name"), "prims", len(m["primitives"]))
    pos = mesh_positions(doc, blob, mesh_index)
    zs = [p[2] for p in pos]
    ys = [p[1] for p in pos]
    zmin, zmax = min(zs), max(zs)
    print("verts %d  z %.3f..%.3f  y %.3f..%.3f" % (len(pos), zmin, zmax, min(ys), max(ys)))
    bins = 22
    print(" bin      zmid  count  maxAbsX   minY   maxY")
    for b in range(bins):
        sel = [p for p in pos
               if min(bins - 1, int((p[2] - zmin) / (zmax - zmin) * bins)) == b]
        if not sel:
            continue
        zmid = zmin + (b + 0.5) * (zmax - zmin) / bins
        print("%4d %9.2f %6d %8.2f %6.2f %6.2f" % (
            b, zmid, len(sel),
            max(abs(p[0]) for p in sel),
            min(p[1] for p in sel),
            max(p[1] for p in sel)))


if __name__ == "__main__":
    main()
