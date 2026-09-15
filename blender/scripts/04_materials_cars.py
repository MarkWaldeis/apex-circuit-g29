"""Unwrap, texture, scale, variant and export the F1 car plus remaining props."""
import bpy
import json
import os
import math
from mathutils import Vector

ROOT = r"C:\Users\Mark Waldeis\Desktop\grok f1 try"
EXPORT = os.path.join(ROOT, "blender", "exports")
CARS_DIR = os.path.join(EXPORT, "cars")
PROPS_DIR = os.path.join(EXPORT, "props")
os.makedirs(CARS_DIR, exist_ok=True)
os.makedirs(PROPS_DIR, exist_ok=True)

WHEEL_SRC = {
    "tripo_part_7": "Wheel_FL",
    "tripo_part_10": "Wheel_FR",
    "tripo_part_8": "Wheel_RL",
    "tripo_part_23": "Wheel_RR",
}

# Real F1 length ~5.5 m. Source AABB Y size is ~0.979 m.
SCALE = 5.5 / 0.9792284965515137

LIVERIES = [
    {"id": "crimson", "paint": (0.74, 0.035, 0.05), "accent": (1.0, 0.95, 0.92), "stripe": (0.02, 0.02, 0.02), "number": "16"},
    {"id": "silver", "paint": (0.62, 0.65, 0.68), "accent": (0.02, 0.12, 0.42), "stripe": (0.05, 0.08, 0.16), "number": "63"},
    {"id": "navy", "paint": (0.02, 0.05, 0.16), "accent": (0.92, 0.78, 0.08), "stripe": (0.85, 0.85, 0.88), "number": "1"},
    {"id": "papaya", "paint": (0.92, 0.38, 0.08), "accent": (0.05, 0.05, 0.06), "stripe": (0.12, 0.16, 0.55), "number": "4"},
    {"id": "green", "paint": (0.02, 0.22, 0.14), "accent": (0.72, 0.78, 0.80), "stripe": (0.95, 0.82, 0.12), "number": "14"},
    {"id": "azure", "paint": (0.05, 0.28, 0.72), "accent": (0.95, 0.35, 0.55), "stripe": (1.0, 1.0, 1.0), "number": "10"},
]


def unhide_all():
    for o in bpy.data.objects:
        o.hide_set(False)
        o.hide_viewport = False
        o.hide_render = False


def descendants(obj):
    out = [obj]
    for c in obj.children:
        out.extend(descendants(c))
    return out


def cube_uv(obj):
    me = obj.data
    if obj.type != "MESH" or me is None:
        return
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                uv[li].uv = (co.y * 2.0 + 0.5, co.z * 2.0 + 0.5)
            elif ax == 1:
                uv[li].uv = (co.x * 2.0 + 0.5, co.z * 2.0 + 0.5)
            else:
                uv[li].uv = (co.x * 2.0 + 0.5, co.y * 2.0 + 0.5)


def bsdf(mat):
    return mat.node_tree.nodes.get("Principled BSDF")


def new_mat(name):
    old = bpy.data.materials.get(name)
    if old:
        bpy.data.materials.remove(old)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_fake_user = True
    return mat


def set_pbr(mat, color, metallic=0.0, roughness=0.5, coat=0.0, coat_rough=0.03, emission=None, emission_strength=0.0):
    node = bsdf(mat)
    node.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    node.inputs["Metallic"].default_value = metallic
    node.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in node.inputs:
        node.inputs["Coat Weight"].default_value = coat
        node.inputs["Coat Roughness"].default_value = coat_rough
    if emission is not None and "Emission Color" in node.inputs:
        node.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        node.inputs["Emission Strength"].default_value = emission_strength
    return mat


def make_livery_mat(livery):
    mat = new_mat(f"Paint_{livery['id']}")
    nt = mat.node_tree
    node = bsdf(mat)
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tex.outputs["Generated"], sep.inputs["Vector"])

    # Y stripe band
    map_y = nt.nodes.new("ShaderNodeMapRange")
    map_y.inputs["From Min"].default_value = 0.42
    map_y.inputs["From Max"].default_value = 0.58
    nt.links.new(sep.outputs["Y"], map_y.inputs["Value"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.08
    ramp.color_ramp.elements[0].color = (*livery["paint"], 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (*livery["stripe"], 1)
    extra = ramp.color_ramp.elements.new(0.92)
    extra.color = (*livery["paint"], 1)
    nt.links.new(map_y.outputs["Result"], ramp.inputs["Fac"])

    # nose accent from high Y
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].position = 0.78
    cr.color_ramp.elements[0].color = (0, 0, 0, 1)
    cr.color_ramp.elements[1].position = 0.9
    cr.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(sep.outputs["Y"], cr.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(ramp.outputs["Color"], mix.inputs["A"])
    mix.inputs["B"].default_value = (*livery["accent"], 1)
    nt.links.new(cr.outputs["Color"], mix.inputs["Factor"])

    # side pinstripe from X
    crx = nt.nodes.new("ShaderNodeValToRGB")
    crx.color_ramp.elements[0].position = 0.04
    crx.color_ramp.elements[0].color = (1, 1, 1, 1)
    crx.color_ramp.elements[1].position = 0.12
    crx.color_ramp.elements[1].color = (0, 0, 0, 1)
    extra2 = crx.color_ramp.elements.new(0.88)
    extra2.color = (0, 0, 0, 1)
    extra3 = crx.color_ramp.elements.new(0.96)
    extra3.color = (1, 1, 1, 1)
    nt.links.new(sep.outputs["X"], crx.inputs["Fac"])
    mix2 = nt.nodes.new("ShaderNodeMix")
    mix2.data_type = "RGBA"
    nt.links.new(mix.outputs["Result"], mix2.inputs["A"])
    mix2.inputs["B"].default_value = (*livery["accent"], 1)
    nt.links.new(crx.outputs["Color"], mix2.inputs["Factor"])

    nt.links.new(mix2.outputs["Result"], node.inputs["Base Color"])
    node.inputs["Metallic"].default_value = 0.18
    node.inputs["Roughness"].default_value = 0.16
    if "Coat Weight" in node.inputs:
        node.inputs["Coat Weight"].default_value = 1.0
        node.inputs["Coat Roughness"].default_value = 0.04
    return mat


def make_shared_mats():
    rubber = set_pbr(new_mat("TireRubber"), (0.025, 0.025, 0.027), metallic=0.0, roughness=0.82)
    # add slight bump
    nt = rubber.node_tree
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 80.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf(rubber).inputs["Normal"])

    rim = set_pbr(new_mat("WheelRim"), (0.55, 0.56, 0.58), metallic=1.0, roughness=0.22)
    carbon = set_pbr(new_mat("Carbon"), (0.012, 0.012, 0.014), metallic=0.25, roughness=0.32)
    nt = carbon.node_tree
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 90.0
    wave.wave_type = "BANDS"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = (0.01, 0.01, 0.012, 1)
    mix.inputs["B"].default_value = (0.06, 0.06, 0.07, 1)
    nt.links.new(wave.outputs["Fac"], mix.inputs["Factor"])
    nt.links.new(mix.outputs["Result"], bsdf(carbon).inputs["Base Color"])

    metal = set_pbr(new_mat("HaloMetal"), (0.4, 0.42, 0.45), metallic=1.0, roughness=0.18)
    glass = set_pbr(new_mat("CanopyGlass"), (0.02, 0.03, 0.04), metallic=0.0, roughness=0.05)
    glass.blend_method = "BLEND"
    bsdf(glass).inputs["Alpha"].default_value = 0.35
    if "Transmission Weight" in bsdf(glass).inputs:
        bsdf(glass).inputs["Transmission Weight"].default_value = 0.85

    cone = new_mat("ConeOrange")
    nt = cone.node_tree
    node = bsdf(cone)
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tex.outputs["Generated"], sep.inputs["Vector"])
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.inputs["Scale"].default_value = 6.0
    nt.links.new(tex.outputs["Generated"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.95, 0.28, 0.05, 1)
    ramp.color_ramp.elements[1].position = 0.55
    ramp.color_ramp.elements[1].color = (0.92, 0.92, 0.90, 1)
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], node.inputs["Base Color"])
    node.inputs["Roughness"].default_value = 0.45

    cam = set_pbr(new_mat("CameraBody"), (0.03, 0.03, 0.035), metallic=0.4, roughness=0.28)
    sign = set_pbr(new_mat("SignPanel"), (0.95, 0.95, 0.92), metallic=0.0, roughness=0.4,
                   emission=(0.9, 0.92, 0.85), emission_strength=0.4)
    return {
        "rubber": rubber, "rim": rim, "carbon": carbon, "metal": metal,
        "glass": glass, "cone": cone, "camera": cam, "sign": sign,
    }


def assign_mat(obj, mat):
    if obj.type != "MESH":
        return
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def classify_and_assign(meshes, shared, paint):
    for o in meshes:
        name = o.name
        verts = len(o.data.vertices)
        bb = [Vector(c) for c in o.bound_box]
        size = Vector((
            max(v.x for v in bb) - min(v.x for v in bb),
            max(v.y for v in bb) - min(v.y for v in bb),
            max(v.z for v in bb) - min(v.z for v in bb),
        ))
        src_name = name
        # after rename, wheels already named
        if name in WHEEL_SRC or name.startswith("Wheel_"):
            assign_mat(o, shared["rubber"])
            continue
        # tiny rods / halo
        if min(size) < 0.012 and max(size) < 0.08:
            assign_mat(o, shared["metal"])
            continue
        if verts < 90:
            assign_mat(o, shared["carbon"])
            continue
        if size.z > 0.09 and size.x < 0.13 and verts < 800:
            assign_mat(o, shared["carbon"])
            continue
        assign_mat(o, paint)


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def apply_scale(objs):
    select_only(objs)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def origin_geometry(obj):
    select_only([obj])
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")


def duplicate_hierarchy(root, new_root_name):
    objs = descendants(root)
    select_only(objs)
    bpy.ops.object.duplicate()
    dup_root = bpy.context.view_layer.objects.active
    # the active after duplicate should be the duplicated root if it was active
    # fallback: newly selected empty
    selected = [o for o in bpy.context.selected_objects]
    # find the new root: empty with no parent among selected, or the one that was root-type
    new_root = None
    for o in selected:
        if o.type == "EMPTY" and o.parent is None:
            new_root = o
            break
    if new_root is None:
        # pick selected whose parent is not in selected
        selset = set(selected)
        for o in selected:
            if o.parent not in selset:
                new_root = o
                break
    if new_root is None:
        new_root = selected[0]
    new_root.name = new_root_name
    return new_root, selected


def join_meshes(meshes, name):
    meshes = [m for m in meshes if m.type == "MESH"]
    if not meshes:
        return None
    select_only(meshes)
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    return body


def decimate(obj, ratio):
    if obj is None or obj.type != "MESH":
        return
    select_only([obj])
    mod = obj.modifiers.new("LOD", "DECIMATE")
    mod.ratio = ratio
    bpy.ops.object.modifier_apply(modifier="LOD")


def collection_of(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def move_to_collection(obj, col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)


def export_glb(objs, path):
    select_only(objs)
    extra = []
    for o in list(objs):
        extra.extend(descendants(o))
    select_only(list({o.name: o for o in extra}.values()))
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
    )
    print("EXPORT", path)


def world_center(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return sum(corners, Vector()) / 8.0


def main():
    unhide_all()
    shared = make_shared_mats()
    car_root = bpy.data.objects.get("f1_car_ROOT")
    if car_root is None:
        raise RuntimeError("f1_car_ROOT missing")

    car_meshes = [o for o in descendants(car_root) if o.type == "MESH"]
    for o in car_meshes:
        cube_uv(o)

    # Scale the whole car
    car_root.scale = (SCALE, SCALE, SCALE)
    apply_scale(descendants(car_root))

    # Rename + origin wheels
    wheel_objs = {}
    for src, dest in WHEEL_SRC.items():
        obj = bpy.data.objects.get(src)
        if obj is None:
            raise RuntimeError(f"missing wheel {src}")
        obj.name = dest
        origin_geometry(obj)
        wheel_objs[dest] = obj

    paint0 = make_livery_mat(LIVERIES[0])
    classify_and_assign(car_meshes, shared, paint0)

    # Rig JSON from scaled source
    rig = {"scale": 1.0, "wheel_radius": 0.0, "wheels": {}, "body_size": None}
    for wname, obj in wheel_objs.items():
        c = world_center(obj)
        size = obj.dimensions
        radius = max(size.z, size.y, size.x) * 0.5
        rig["wheels"][wname] = {
            "location": [c.x, c.y, c.z],
            "dimensions": [size.x, size.y, size.z],
            "radius": radius,
        }
        rig["wheel_radius"] = max(rig["wheel_radius"], radius)
    # body AABB
    mins = Vector((1e9, 1e9, 1e9)); maxs = Vector((-1e9, -1e9, -1e9))
    for o in car_meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mins.x = min(mins.x, w.x); mins.y = min(mins.y, w.y); mins.z = min(mins.z, w.z)
            maxs.x = max(maxs.x, w.x); maxs.y = max(maxs.y, w.y); maxs.z = max(maxs.z, w.z)
    rig["body_size"] = [maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z]
    rig["aabb_min"] = list(mins)
    rig["aabb_max"] = list(maxs)
    with open(os.path.join(CARS_DIR, "car_rig.json"), "w", encoding="utf-8") as f:
        json.dump(rig, f, indent=2)
    print("RIG", json.dumps(rig, indent=2))

    cars_col = collection_of("car_variants")
    exports = []

    for i, liv in enumerate(LIVERIES):
        new_root, selected = duplicate_hierarchy(car_root, f"car_{liv['id']}_ROOT")
        new_root.location.x = 18.0 * (i + 1)
        paint = make_livery_mat(liv)
        meshes = [o for o in descendants(new_root) if o.type == "MESH"]
        wheels = []
        body_parts = []
        for o in meshes:
            # duplicated wheel names: Wheel_FL.001 etc
            base = o.name.split(".")[0]
            if base in ("Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"):
                o.name = f"{liv['id']}_{base}"
                assign_mat(o, shared["rubber"])
                origin_geometry(o)
                wheels.append(o)
            else:
                body_parts.append(o)
        classify_and_assign(body_parts, shared, paint)
        body = join_meshes(body_parts, f"{liv['id']}_Body")
        decimate(body, 0.55)
        cube_uv(body)
        assign_mat(body, paint)
        # collection
        for o in descendants(new_root):
            move_to_collection(o, cars_col)
        export_path = os.path.join(CARS_DIR, f"car_{liv['id']}.glb")
        export_glb([new_root], export_path)
        exports.append(export_path)
        print(f"VARIANT {liv['id']} body_faces={len(body.data.polygons) if body else 0} wheels={len(wheels)}")

    # Props that still lack image textures
    prop_map = {
        "traffic_cone_ROOT": ("cone", "traffic_cone.glb"),
        "cinema_camera_ROOT": ("camera", "cinema_camera.glb"),
        "signboard_ROOT": ("sign", "signboard.glb"),
    }
    for root_name, (mat_key, filename) in prop_map.items():
        root = bpy.data.objects.get(root_name)
        if root is None:
            print("MISSING PROP", root_name)
            continue
        for o in descendants(root):
            if o.type == "MESH":
                cube_uv(o)
                assign_mat(o, shared[mat_key])
        export_glb([root], os.path.join(PROPS_DIR, filename))

    # Re-export textured tripo props as-is
    textured = [
        ("steering_wheel_ROOT", "steering_wheel.glb"),
        ("bar_counter_ROOT", "bar_counter.glb"),
        ("guard_tower_ROOT", "guard_tower.glb"),
        ("stadium_seating_ROOT", "stadium_seating.glb"),
        ("tire_rack_ROOT", "tire_rack.glb"),
        ("tire_stack_ROOT", "tire_stack.glb"),
        ("traffic_light_gantry_ROOT", "traffic_light_gantry.glb"),
    ]
    for root_name, filename in textured:
        root = bpy.data.objects.get(root_name)
        if root is None:
            print("MISSING", root_name)
            continue
        export_glb([root], os.path.join(PROPS_DIR, filename))

    blend_path = os.path.join(ROOT, "blender", "apex_circuit.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("SAVED", blend_path)
    print("DONE_CARS", exports)


main()
