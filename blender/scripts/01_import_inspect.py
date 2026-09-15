"""Import all source GLBs into Blender collections and dump a JSON inspection report."""
import bpy
import json
import os
from mathutils import Vector

ROOT = r"C:\Users\Mark Waldeis\Desktop\grok f1 try"
SRC = os.path.join(ROOT, "blender", "source_assets")
REPORT = os.path.join(ROOT, "blender", "import_report.json")

ASSETS = [
    ("f1_car", "f1 race car 3d model.glb"),
    ("steering_wheel", "gaming steering wheel 3d model.glb"),
    ("bar_counter", "bar counter 3d model.glb"),
    ("cinema_camera", "cinema camera 3d model.glb"),
    ("guard_tower", "industrial guard tower 3d model.glb"),
    ("signboard", "signboard 3d model.glb"),
    ("stadium_seating", "stadium seating 3d model.glb"),
    ("tire_rack", "tire rack 3d model.glb"),
    ("tire_stack", "tire stack 3d model.glb"),
    ("traffic_cone", "traffic cone 3d model.glb"),
    ("traffic_light_gantry", "traffic light gantry 3d model.glb"),
]


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.armatures, bpy.data.cameras, bpy.data.lights, bpy.data.collections):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    # Keep Scene collection; drop extras
    scene_col = bpy.context.scene.collection
    for child in list(scene_col.children):
        scene_col.children.unlink(child)


def ensure_collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    return col


def object_bounds(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    zs = [c.z for c in corners]
    return {
        "min": [min(xs), min(ys), min(zs)],
        "max": [max(xs), max(ys), max(zs)],
        "size": [max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)],
    }


def mesh_stats(obj):
    if obj.type != "MESH" or obj.data is None:
        return None
    me = obj.data
    return {
        "verts": len(me.vertices),
        "edges": len(me.edges),
        "faces": len(me.polygons),
        "uv_layers": [uv.name for uv in me.uv_layers],
        "materials": [slot.material.name if slot.material else None for slot in obj.material_slots],
        "has_ngons": any(len(p.vertices) > 4 for p in me.polygons),
    }


def dump_tree(obj, depth=0):
    info = {
        "name": obj.name,
        "type": obj.type,
        "location": list(obj.location),
        "rotation_euler": list(obj.rotation_euler),
        "scale": list(obj.scale),
        "parent": obj.parent.name if obj.parent else None,
        "children": [c.name for c in obj.children],
        "hidden": obj.hide_get(),
        "bounds": object_bounds(obj) if obj.type == "MESH" else None,
        "mesh": mesh_stats(obj),
    }
    return info


def import_glb(key, filename, offset_x):
    path = os.path.join(SRC, filename)
    if not os.path.isfile(path):
        return {"key": key, "error": f"missing {path}"}

    col = ensure_collection(key)
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=path)
    after = set(bpy.data.objects.keys())
    new_names = sorted(after - before)
    new_objs = [bpy.data.objects[n] for n in new_names]

    # Parent roots into an empty so we can offset the whole asset
    empty = bpy.data.objects.new(f"{key}_ROOT", None)
    col.objects.link(empty)
    if empty.name not in bpy.context.scene.collection.objects:
        pass
    else:
        bpy.context.scene.collection.objects.unlink(empty)

    roots = [o for o in new_objs if o.parent is None]
    for o in new_objs:
        # Move into asset collection
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
    for r in roots:
        r.parent = empty
    empty.location.x = offset_x

    objects = [dump_tree(o) for o in new_objs]
    objects.insert(0, dump_tree(empty))
    total_verts = sum((o["mesh"]["verts"] if o.get("mesh") else 0) for o in objects)
    total_faces = sum((o["mesh"]["faces"] if o.get("mesh") else 0) for o in objects)
    return {
        "key": key,
        "file": filename,
        "offset_x": offset_x,
        "object_count": len(new_objs),
        "total_verts": total_verts,
        "total_faces": total_faces,
        "materials": sorted({m for o in objects if o.get("mesh") for m in o["mesh"]["materials"] if m}),
        "objects": objects,
    }


def setup_studio():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE"
    if hasattr(scene, "eevee"):
        pass
    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.12, 0.14, 0.16, 1.0)
        bg.inputs[1].default_value = 0.6

    sun = bpy.data.lights.new("StudioSun", "SUN")
    sun.energy = 6.0
    sun.angle = 0.15
    sun_obj = bpy.data.objects.new("StudioSun", sun)
    sun_obj.rotation_euler = (0.7, 0.2, 0.9)
    bpy.context.scene.collection.objects.link(sun_obj)

    fill = bpy.data.lights.new("StudioFill", "AREA")
    fill.energy = 400.0
    fill.size = 8.0
    fill_obj = bpy.data.objects.new("StudioFill", fill)
    fill_obj.location = (-6, -8, 6)
    fill_obj.rotation_euler = (0.9, 0, -0.4)
    bpy.context.scene.collection.objects.link(fill_obj)


def main():
    clear_scene()
    setup_studio()
    report = []
    x = 0.0
    for key, filename in ASSETS:
        info = import_glb(key, filename, x)
        # next offset based on size if available
        sizes = []
        for o in info.get("objects", []):
            if o.get("bounds"):
                sizes.append(o["bounds"]["size"][0])
        span = max(sizes) if sizes else 8.0
        x += max(span, 6.0) + 6.0
        report.append(info)
    with open(REPORT, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print("WROTE", REPORT)
    print("ASSETS", len(report), "NEXT_X", x)
    for r in report:
        print(f"  {r['key']}: objs={r.get('object_count')} verts={r.get('total_verts')} faces={r.get('total_faces')} mats={r.get('materials')}")


main()
