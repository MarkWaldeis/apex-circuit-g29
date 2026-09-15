"""Re-export livery cars from the world origin so Godot spawns them on the grid."""
import bpy
import os

ROOT = r"C:\Users\Mark Waldeis\Desktop\grok f1 try"
CARS_DIR = os.path.join(ROOT, "blender", "exports", "cars")

LIVERIES = ["crimson", "silver", "navy", "papaya", "green", "azure"]


def descendants(obj):
    out = [obj]
    for c in obj.children:
        out.extend(descendants(c))
    return out


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


for liv in LIVERIES:
    name = f"car_{liv}_ROOT"
    root = bpy.data.objects.get(name)
    if root is None:
        print("MISSING", name)
        continue
    old = root.location.copy()
    root.location = (0.0, 0.0, 0.0)
    objs = descendants(root)
    select_only(objs)
    path = os.path.join(CARS_DIR, f"car_{liv}.glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    root.location = old
    print("REEXPORT", path, "from", list(old))

print("DONE")
