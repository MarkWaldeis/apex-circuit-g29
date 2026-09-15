"""Frame a named root in the 3D viewport. Reads blender/frame_config.json."""
import bpy
import json
import os
from mathutils import Euler, Vector

ROOT = r"C:\Users\Mark Waldeis\Desktop\grok f1 try"
CFG = os.path.join(ROOT, "blender", "frame_config.json")

with open(CFG, encoding="utf-8") as f:
    cfg = json.load(f)

target = cfg["target"]
rot = tuple(cfg.get("rotation", [1.05, 0.15, 0.85]))
margin = float(cfg.get("margin", 2.8))
hide_others = bool(cfg.get("hide_others", True))
shading = cfg.get("shading", "MATERIAL")


def descendants(obj):
    out = [obj]
    for c in obj.children:
        out.extend(descendants(c))
    return out


obj = bpy.data.objects.get(target)
if obj is None:
    raise RuntimeError(f"missing {target}")

keep = set()
for o in descendants(obj):
    keep.add(o.name)

if hide_others:
    for o in bpy.data.objects:
        if o.type in {"LIGHT", "CAMERA"}:
            o.hide_set(False)
            continue
        o.hide_set(o.name not in keep)

# world AABB of visible keep meshes
mins = Vector((1e9, 1e9, 1e9))
maxs = Vector((-1e9, -1e9, -1e9))
count = 0
for name in keep:
    o = bpy.data.objects[name]
    if o.type != "MESH":
        continue
    count += 1
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        mins.x = min(mins.x, w.x); mins.y = min(mins.y, w.y); mins.z = min(mins.z, w.z)
        maxs.x = max(maxs.x, w.x); maxs.y = max(maxs.y, w.y); maxs.z = max(maxs.z, w.z)

center = (mins + maxs) * 0.5
size = maxs - mins
dist = max(size.x, size.y, size.z) * margin
if dist < 0.5:
    dist = 2.0

for area in bpy.context.screen.areas:
    if area.type != "VIEW_3D":
        continue
    space = area.spaces.active
    space.shading.type = shading
    if hasattr(space.shading, "use_scene_lights"):
        space.shading.use_scene_lights = True
        space.shading.use_scene_world = True
    space.overlay.show_overlays = False
    r3d = space.region_3d
    r3d.view_perspective = "PERSP"
    r3d.view_location = center
    r3d.view_rotation = Euler(rot).to_quaternion()
    r3d.view_distance = dist
    print("FRAMED", target, "meshes", count, "center", list(center), "size", list(size), "dist", dist, "rot", list(rot))
