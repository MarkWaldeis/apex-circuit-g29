"""Classify F1 car parts by bounds so wheels can stay independent."""
import bpy
import json
import os
from mathutils import Vector

ROOT = r"C:\Users\Mark Waldeis\Desktop\grok f1 try"
OUT = os.path.join(ROOT, "blender", "car_parts.json")


def world_bounds(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    zs = [c.z for c in corners]
    return {
        "min": [min(xs), min(ys), min(zs)],
        "max": [max(xs), max(ys), max(zs)],
        "size": [max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)],
        "center": [(min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2],
    }


car_meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("tripo_part_")]
parts = []
xmin = ymin = zmin = 1e9
xmax = ymax = zmax = -1e9
for o in car_meshes:
    b = world_bounds(o)
    xmin = min(xmin, b["min"][0]); ymin = min(ymin, b["min"][1]); zmin = min(zmin, b["min"][2])
    xmax = max(xmax, b["max"][0]); ymax = max(ymax, b["max"][1]); zmax = max(zmax, b["max"][2])
    sx, sy, sz = b["size"]
    # wheel heuristic: roughly cubic/cylindrical, similar X/Z or Y/Z, modest size
    aspect = max(sx, sy, sz) / max(min(sx, sy, sz), 1e-6)
    parts.append({
        "name": o.name,
        "verts": len(o.data.vertices),
        "faces": len(o.data.polygons),
        "uvs": [u.name for u in o.data.uv_layers],
        "bounds": b,
        "max_dim": max(sx, sy, sz),
        "min_dim": min(sx, sy, sz),
        "aspect": aspect,
    })

parts.sort(key=lambda p: p["name"])
overall = {
    "count": len(parts),
    "aabb": {"min": [xmin, ymin, zmin], "max": [xmax, ymax, zmax],
             "size": [xmax - xmin, ymax - ymin, zmax - zmin]},
    "parts": parts,
}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(overall, f, indent=2)
print("CAR AABB size", overall["aabb"]["size"])
print("CAR AABB min", overall["aabb"]["min"])
print("CAR AABB max", overall["aabb"]["max"])
print("PARTS", len(parts))
for p in parts:
    print(f"{p['name']:16} v={p['verts']:5} f={p['faces']:5} size={[round(x,3) for x in p['bounds']['size']]} c={[round(x,3) for x in p['bounds']['center']]} aspect={p['aspect']:.2f}")
