"""Build Apex Circuit: smooth GP track, kerbs, runoff, barriers, props, export."""
import bpy
import json
import math
import os
import random
from mathutils import Vector, Matrix, Euler

ROOT = r"C:\Users\Mark Waldeis\Desktop\grok f1 try"
EXPORT = os.path.join(ROOT, "blender", "exports")
TRACK_DIR = os.path.join(EXPORT, "track")
TEX_DIR = os.path.join(ROOT, "blender", "textures")
os.makedirs(TRACK_DIR, exist_ok=True)
os.makedirs(TEX_DIR, exist_ok=True)

# Closed non-self-intersecting GP loop. Start/finish at origin heading +Y.
# Rounded rectangle: long straight, T1 90, north esses, east back straight,
# SE hairpin, south return, SW corner onto the main straight.
CENTERLINE = [
    # Main straight heading +Y
    (0.0, 0.0, 0.0),
    (0.0, 70.0, 0.0),
    (0.0, 140.0, 0.0),
    (0.0, 210.0, 0.0),
    (0.0, 280.0, 0.0),
    (2.0, 340.0, 0.0),
    (8.0, 390.0, 0.0),
    # T1 right 90 — slow, wide radius
    (22.0, 425.0, 0.0),
    (50.0, 448.0, 0.1),
    (90.0, 458.0, 0.2),
    (135.0, 458.0, 0.3),
    (175.0, 448.0, 0.5),
    # T2-T3 esses along the north, staying y>410
    (210.0, 438.0, 0.8),
    (240.0, 452.0, 1.2),
    (275.0, 442.0, 1.6),
    (310.0, 455.0, 2.0),
    (350.0, 450.0, 2.2),
    # T4 right onto east back straight
    (385.0, 430.0, 2.0),
    (408.0, 395.0, 1.6),
    (418.0, 350.0, 1.2),
    (422.0, 290.0, 0.8),
    (422.0, 220.0, 0.5),
    (420.0, 150.0, 0.3),
    (416.0, 90.0, 0.1),
    # T5-T6 hairpin right at south-east
    (405.0, 50.0, 0.0),
    (385.0, 25.0, 0.0),
    (355.0, 10.0, 0.0),
    (320.0, 4.0, 0.0),
    (285.0, 8.0, 0.0),
    (255.0, 22.0, 0.0),
    # Short south chute
    (230.0, 38.0, 0.0),
    (205.0, 42.0, 0.0),
    # T7-T8 chicane, still south of the main straight
    (175.0, 32.0, 0.0),
    (150.0, 18.0, 0.0),
    (120.0, 22.0, 0.0),
    (95.0, 30.0, 0.0),
    # T9 left onto main straight
    (65.0, 22.0, 0.0),
    (38.0, 12.0, 0.0),
    (16.0, 4.0, 0.0),
]

ROAD_WIDTH = 12.0
KERB_WIDTH = 0.85
RUNOFF_WIDTH = 10.0
BARRIER_OFFSET = 16.0
BARRIER_H = 1.15
SPACING = 1.15


def new_mat(name):
    old = bpy.data.materials.get(name)
    if old:
        bpy.data.materials.remove(old)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat


def set_pbr(mat, color, metallic=0.0, roughness=0.6, emission=None, emission_strength=0.0, spec=0.5):
    n = mat.node_tree.nodes.get("Principled BSDF")
    n.inputs["Base Color"].default_value = (*color, 1.0)
    n.inputs["Metallic"].default_value = metallic
    n.inputs["Roughness"].default_value = roughness
    if emission is not None and "Emission Color" in n.inputs:
        n.inputs["Emission Color"].default_value = (*emission, 1.0)
        n.inputs["Emission Strength"].default_value = emission_strength
    return mat


def add_image_tex(mat, img, roughness=0.7):
    nt = mat.node_tree
    n = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Smart"
    nt.links.new(tex.outputs["Color"], n.inputs["Base Color"])
    n.inputs["Roughness"].default_value = roughness
    return mat


def save_image(name, w, h, pixels, path):
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels = pixels
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def gen_asphalt(path):
    w = h = 512
    rnd = random.Random(7)
    pix = [0.0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            n = rnd.random() * 0.07
            g = 0.07 + n
            # faint darker patches
            patch = 0.02 * math.sin(x * 0.11) * math.sin(y * 0.09)
            c = max(0.04, min(0.14, g + patch))
            i = (y * w + x) * 4
            pix[i:i + 4] = [c, c, c * 0.98, 1.0]
    return save_image("tex_asphalt", w, h, pix, path)


def gen_kerb(path):
    w, h = 256, 64
    pix = [0.0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            band = (x // 128) % 2
            if band == 0:
                col = (0.85, 0.05, 0.06, 1.0)
            else:
                col = (0.93, 0.93, 0.91, 1.0)
            # rubber edge
            if y < 6 or y > h - 7:
                col = (0.08, 0.08, 0.08, 1.0)
            i = (y * w + x) * 4
            pix[i:i + 4] = list(col)
    return save_image("tex_kerb", w, h, pix, path)


def gen_grass(path):
    w = h = 512
    rnd = random.Random(3)
    pix = [0.0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            n = rnd.random()
            r = 0.07 + 0.04 * n
            g = 0.22 + 0.10 * n
            b = 0.06 + 0.03 * n
            i = (y * w + x) * 4
            pix[i:i + 4] = [r, g, b, 1.0]
    return save_image("tex_grass", w, h, pix, path)


def gen_runoff(path):
    w = h = 256
    rnd = random.Random(11)
    pix = [0.0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            n = rnd.random()
            c = 0.22 + 0.08 * n
            i = (y * w + x) * 4
            pix[i:i + 4] = [c * 0.95, c, c * 0.55, 1.0]
    return save_image("tex_runoff", w, h, pix, path)


def gen_gravel(path):
    w = h = 256
    rnd = random.Random(21)
    pix = [0.0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            n = rnd.random()
            r = 0.42 + 0.18 * n
            g = 0.36 + 0.14 * n
            b = 0.24 + 0.10 * n
            i = (y * w + x) * 4
            pix[i:i + 4] = [r, g, b, 1.0]
    return save_image("tex_gravel", w, h, pix, path)


def gen_barrier(path):
    w, h = 128, 64
    pix = [0.0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            # blue SAFER with white stripe
            if 24 <= y <= 40:
                col = (0.92, 0.92, 0.93, 1.0)
            else:
                col = (0.05, 0.18, 0.55, 1.0)
            i = (y * w + x) * 4
            pix[i:i + 4] = list(col)
    return save_image("tex_barrier", w, h, pix, path)


def catmull(p0, p1, p2, p3, t):
    t2 = t * t
    t3 = t2 * t
    return 0.5 * (
        (2.0 * p1)
        + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
    )


def closed_samples(points, spacing=SPACING):
    pts = [Vector(p) for p in points]
    n = len(pts)
    dense = []
    steps = 16
    for i in range(n):
        p0 = pts[(i - 1) % n]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n]
        for s in range(steps):
            dense.append(catmull(p0, p1, p2, p3, s / steps))
    # arc-length resample
    dists = [0.0]
    for i in range(1, len(dense)):
        dists.append(dists[-1] + (dense[i] - dense[i - 1]).length)
    total = dists[-1] + (dense[0] - dense[-1]).length
    count = max(32, int(total / spacing))
    out = []
    target = 0.0
    step = total / count
    j = 0
    for k in range(count):
        while j < len(dists) - 1 and dists[j + 1] < target:
            j += 1
        if j >= len(dists) - 1:
            out.append(dense[0].copy())
        else:
            span = dists[j + 1] - dists[j]
            u = 0.0 if span < 1e-8 else (target - dists[j]) / span
            out.append(dense[j].lerp(dense[j + 1], u))
        target += step
    return out, total


def frames(centerline):
    """Per-point position, tangent, right, up."""
    n = len(centerline)
    out = []
    for i, p in enumerate(centerline):
        nxt = centerline[(i + 1) % n]
        prv = centerline[(i - 1) % n]
        tan = (nxt - prv)
        if tan.length < 1e-8:
            tan = Vector((0, 1, 0))
        tan.normalize()
        up = Vector((0, 0, 1))
        right = tan.cross(up)
        if right.length < 1e-6:
            right = Vector((1, 0, 0))
        right.normalize()
        up = right.cross(tan).normalized()
        out.append((p, tan, right, up))
    return out


def make_mesh(name, verts, faces, uvs, mat, smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    # from_pydata loops match faces in order
    li = 0
    for fi, face in enumerate(faces):
        for k in range(len(face)):
            uv.data[li].uv = uvs[fi][k]
            li += 1
    if smooth:
        for p in mesh.polygons:
            p.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    mesh.materials.append(mat)
    return obj


def ribbon(frm, inner, outer, z_extra, u_scale, v0, v1, closed=True):
    n = len(frm)
    verts = []
    faces = []
    uvs = []
    dist = 0.0
    for i, (p, tan, right, up) in enumerate(frm):
        a = p + right * inner + Vector((0, 0, z_extra))
        b = p + right * outer + Vector((0, 0, z_extra))
        verts.extend([a, b])
        if i > 0:
            d = (frm[i][0] - frm[i - 1][0]).length
            dist += d
            u0 = (dist - d) * u_scale
            u1 = dist * u_scale
            ia = (i - 1) * 2
            faces.append((ia, ia + 1, ia + 3, ia + 2))
            uvs.append(((u0, v0), (u0, v1), (u1, v1), (u1, v0)))
    if closed:
        d = (frm[0][0] - frm[-1][0]).length
        u0 = dist * u_scale
        u1 = (dist + d) * u_scale
        ia = (n - 1) * 2
        faces.append((ia, ia + 1, 1, 0))
        uvs.append(((u0, v0), (u0, v1), (u1, v1), (u1, v0)))
    return verts, faces, uvs


def wall(frm, offset, height, u_scale, side=1.0):
    n = len(frm)
    verts = []
    faces = []
    uvs = []
    dist = 0.0
    for i, (p, tan, right, up) in enumerate(frm):
        base = p + right * (offset * side)
        verts.extend([base, base + Vector((0, 0, height))])
        if i > 0:
            d = (frm[i][0] - frm[i - 1][0]).length
            dist += d
            u0 = (dist - d) * u_scale
            u1 = dist * u_scale
            ia = (i - 1) * 2
            faces.append((ia, ia + 1, ia + 3, ia + 2))
            uvs.append(((u0, 0.0), (u0, 1.0), (u1, 1.0), (u1, 0.0)))
    d = (frm[0][0] - frm[-1][0]).length
    u0 = dist * u_scale
    u1 = (dist + d) * u_scale
    ia = (n - 1) * 2
    faces.append((ia, ia + 1, 1, 0))
    uvs.append(((u0, 0.0), (u0, 1.0), (u1, 1.0), (u1, 0.0)))
    return verts, faces, uvs


def link_col(obj, col):
    col.objects.link(obj)


def descendants(obj):
    out = [obj]
    for c in obj.children:
        out.extend(descendants(c))
    return out


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def duplicate_root(root, name):
    objs = descendants(root)
    select_only(objs)
    bpy.ops.object.duplicate()
    selected = list(bpy.context.selected_objects)
    selset = set(selected)
    new_root = None
    for o in selected:
        if o.parent not in selset:
            new_root = o
            break
    if new_root is None:
        new_root = selected[0]
    new_root.name = name
    return new_root


def origin_geometry(obj):
    select_only([obj])
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")


def unhide_tree(obj):
    for o in descendants(obj):
        o.hide_set(False)
        o.hide_viewport = False
        o.hide_render = False


def hide_park_sources():
    park = bpy.data.collections.get("parked_sources")
    if park is None:
        park = bpy.data.collections.new("parked_sources")
        bpy.context.scene.collection.children.link(park)
    keep_lights = {"StudioSun", "StudioFill"}
    for o in list(bpy.data.objects):
        if o.name in keep_lights:
            continue
        if o.name.startswith("Track") or o.name.startswith("COL_") or o.name.startswith("Apex"):
            continue
        o.hide_set(True)
        o.hide_viewport = True


def make_box(name, size, loc, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat)
    return obj


def export_glb(objs, path):
    extra = []
    for o in objs:
        extra.extend(descendants(o))
    uniq = list({o.name: o for o in extra}.values())
    for o in uniq:
        o.hide_set(False)
        o.hide_viewport = False
    select_only(uniq)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )
    print("EXPORT", path)


def main():
    hide_park_sources()
    prefixes = (
        "Stand_", "Tower_", "Tires_", "Cone_", "Cam_", "Board_",
        "StartGantry", "Paddock", "PitRack_", "PitBuilding", "PitRoof",
        "Road", "COL_", "Kerb", "Runoff", "GrassGround", "PitLane",
        "StartFinish", "Grid_", "StartMarker",
    )
    for o in list(bpy.data.objects):
        if o.name.startswith(prefixes):
            bpy.data.objects.remove(o, do_unlink=True)
    track_col = bpy.data.collections.get("ApexCircuit")
    if track_col:
        for o in list(track_col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        track_col = bpy.data.collections.new("ApexCircuit")
        bpy.context.scene.collection.children.link(track_col)

    asphalt_img = gen_asphalt(os.path.join(TEX_DIR, "asphalt.png"))
    kerb_img = gen_kerb(os.path.join(TEX_DIR, "kerb.png"))
    grass_img = gen_grass(os.path.join(TEX_DIR, "grass.png"))
    runoff_img = gen_runoff(os.path.join(TEX_DIR, "runoff.png"))
    gravel_img = gen_gravel(os.path.join(TEX_DIR, "gravel.png"))
    barrier_img = gen_barrier(os.path.join(TEX_DIR, "barrier.png"))

    mat_asphalt = add_image_tex(set_pbr(new_mat("Asphalt"), (0.08, 0.08, 0.08), roughness=0.72), asphalt_img, 0.72)
    mat_kerb = add_image_tex(set_pbr(new_mat("Kerb"), (0.8, 0.1, 0.1), roughness=0.4), kerb_img, 0.38)
    mat_grass = add_image_tex(set_pbr(new_mat("Grass"), (0.12, 0.28, 0.08), roughness=0.85), grass_img, 0.88)
    mat_runoff = add_image_tex(set_pbr(new_mat("Runoff"), (0.25, 0.28, 0.16), roughness=0.8), runoff_img, 0.82)
    mat_gravel = add_image_tex(set_pbr(new_mat("Gravel"), (0.45, 0.38, 0.25), roughness=0.9), gravel_img, 0.9)
    mat_barrier = add_image_tex(set_pbr(new_mat("Barrier"), (0.1, 0.2, 0.55), roughness=0.45), barrier_img, 0.42)
    mat_paint = set_pbr(new_mat("WhitePaint"), (0.92, 0.92, 0.9), roughness=0.35)
    mat_pit = set_pbr(new_mat("PitAsphalt"), (0.12, 0.12, 0.13), roughness=0.7)
    mat_concrete = set_pbr(new_mat("Concrete"), (0.45, 0.44, 0.42), roughness=0.7)
    mat_metal = set_pbr(new_mat("Steel"), (0.4, 0.42, 0.45), metallic=1.0, roughness=0.25)
    mat_emissive = set_pbr(new_mat("StartLight"), (0.8, 0.05, 0.05), roughness=0.2,
                           emission=(1.0, 0.1, 0.05), emission_strength=12.0)

    samples, length = closed_samples(CENTERLINE, SPACING)
    frm = frames(samples)
    print(f"TRACK length={length:.1f}m samples={len(samples)}")

    half = ROAD_WIDTH * 0.5
    # Road slightly above grass
    v, f, u = ribbon(frm, -half, half, 0.04, 0.125, 0.0, 1.0)
    road = make_mesh("Road", v, f, u, mat_asphalt)
    link_col(road, track_col)

    # Collision copy of road, thicker via duplicate Z
    v2, f2, u2 = ribbon(frm, -half, half, 0.04, 0.125, 0.0, 1.0)
    col_road = make_mesh("COL_Road", v2, f2, u2, mat_asphalt)
    col_road.hide_render = True
    link_col(col_road, track_col)

    # Kerbs
    v, f, u = ribbon(frm, -half - KERB_WIDTH, -half, 0.07, 1.25, 0.0, 1.0)
    kerb_l = make_mesh("KerbInner", v, f, u, mat_kerb)
    link_col(kerb_l, track_col)
    v, f, u = ribbon(frm, half, half + KERB_WIDTH, 0.07, 1.25, 0.0, 1.0)
    kerb_r = make_mesh("KerbOuter", v, f, u, mat_kerb)
    link_col(kerb_r, track_col)

    # Runoff
    v, f, u = ribbon(frm, -half - KERB_WIDTH - RUNOFF_WIDTH, -half - KERB_WIDTH, 0.01, 0.08, 0.0, 1.0)
    run_l = make_mesh("RunoffInner", v, f, u, mat_runoff)
    link_col(run_l, track_col)
    v, f, u = ribbon(frm, half + KERB_WIDTH, half + KERB_WIDTH + RUNOFF_WIDTH, 0.01, 0.08, 0.0, 1.0)
    run_r = make_mesh("RunoffOuter", v, f, u, mat_runoff)
    link_col(run_r, track_col)

    # Gravel trap around hairpin (T6 ~ samples near (350,198))
    v, f, u = wall(frm, BARRIER_OFFSET, BARRIER_H, 0.15, side=1.0)
    bar_r = make_mesh("COL_BarrierOuter", v, f, u, mat_barrier)
    link_col(bar_r, track_col)
    v, f, u = wall(frm, BARRIER_OFFSET, BARRIER_H, 0.15, side=-1.0)
    bar_l = make_mesh("COL_BarrierInner", v, f, u, mat_barrier)
    link_col(bar_l, track_col)

    # Ground
    bpy.ops.mesh.primitive_plane_add(size=900, location=(180, 250, -0.02))
    ground = bpy.context.active_object
    ground.name = "GrassGround"
    ground.data.materials.append(mat_grass)
    # UV scale
    uv = ground.data.uv_layers.active
    for loop in uv.data:
        loop.uv *= 40.0
    link_col(ground, track_col)

    # Pit lane: parallel to first ~220 m of straight, offset -X (left of heading +Y)
    pit_pts = []
    acc = 0.0
    for i in range(len(samples)):
        if i == 0:
            p = samples[i]
        else:
            acc += (samples[i] - samples[i - 1]).length
            p = samples[i]
        if acc > 220:
            break
        _p, tan, right, up = frm[i]
        pit_pts.append(p + right * -22.0 + Vector((0, 0, 0.03)))
    if len(pit_pts) > 4:
        # local frames along pit
        pit_frm = []
        for i, p in enumerate(pit_pts):
            nxt = pit_pts[min(i + 1, len(pit_pts) - 1)]
            prv = pit_pts[max(i - 1, 0)]
            tan = (nxt - prv)
            if tan.length < 1e-6:
                tan = Vector((0, 1, 0))
            tan.normalize()
            right = tan.cross(Vector((0, 0, 1))).normalized()
            pit_frm.append((p, tan, right, Vector((0, 0, 1))))
        v, f, u = ribbon(pit_frm, -4.5, 4.5, 0.0, 0.12, 0.0, 1.0, closed=False)
        pit = make_mesh("PitLane", v, f, u, mat_pit)
        link_col(pit, track_col)

    # Start/finish stripe
    p0, tan0, right0, _ = frm[0]
    stripe_verts = [
        p0 - tan0 * 1.2 - right0 * half + Vector((0, 0, 0.05)),
        p0 - tan0 * 1.2 + right0 * half + Vector((0, 0, 0.05)),
        p0 + tan0 * 1.2 + right0 * half + Vector((0, 0, 0.05)),
        p0 + tan0 * 1.2 - right0 * half + Vector((0, 0, 0.05)),
    ]
    stripe = make_mesh(
        "StartFinish",
        stripe_verts,
        [(0, 1, 2, 3)],
        [((0, 0), (1, 0), (1, 1), (0, 1))],
        mat_paint,
        smooth=False,
    )
    link_col(stripe, track_col)

    # Grid boxes on the straight behind start (negative tangent)
    for i in range(8):
        along = -8.0 - i * 7.5
        side = -3.2 if i % 2 == 0 else 3.2
        c = p0 + tan0 * along + right0 * side + Vector((0, 0, 0.051))
        box_v = [
            c - tan0 * 2.4 - right0 * 1.1,
            c - tan0 * 2.4 + right0 * 1.1,
            c + tan0 * 2.4 + right0 * 1.1,
            c + tan0 * 2.4 - right0 * 1.1,
        ]
        box = make_mesh(
            f"Grid_{i+1}",
            box_v,
            [(0, 1, 2, 3)],
            [((0, 0), (1, 0), (1, 1), (0, 1))],
            mat_paint,
            smooth=False,
        )
        link_col(box, track_col)

    # Pit building (simple concrete block)
    garage = make_box("PitBuilding", (8, 70, 6), (-36, 110, 3.0), mat_concrete)
    link_col(garage, track_col)
    roof = make_box("PitRoof", (10, 72, 0.4), (-36, 110, 6.3), mat_metal)
    link_col(roof, track_col)

    # Start marker triangle (orientation debug)
    mk = make_mesh(
        "StartMarker",
        [
            p0 + tan0 * 4 + Vector((0, 0, 0.2)),
            p0 - right0 * 1.5 + Vector((0, 0, 0.2)),
            p0 + right0 * 1.5 + Vector((0, 0, 0.2)),
        ],
        [(0, 1, 2)],
        [((0.5, 1), (0, 0), (1, 0))],
        mat_emissive,
        smooth=False,
    )
    link_col(mk, track_col)

    # Instance props
    def place(src_name, dest_name, loc, rot, scale):
        src = bpy.data.objects.get(src_name)
        if src is None:
            print("NO PROP", src_name)
            return None
        unhide_tree(src)
        root = duplicate_root(src, dest_name)
        src.hide_set(True)
        src.hide_viewport = True
        root.location = loc
        root.rotation_euler = rot
        if isinstance(scale, (int, float)):
            root.scale = (scale, scale, scale)
        else:
            root.scale = scale
        unhide_tree(root)
        for o in descendants(root):
            if o.name not in track_col.objects:
                for c in list(o.users_collection):
                    try:
                        c.objects.unlink(o)
                    except Exception:
                        pass
                track_col.objects.link(o)
        return root

    # Grandstands along main straight (left, -X)
    for i, y in enumerate((40, 95, 150, 205, 260)):
        place("stadium_seating_ROOT", f"Stand_L_{i}", Vector((-28, y, 0)), Euler((0, 0, math.pi / 2)), 18.0)
    for i, y in enumerate((70, 140, 210)):
        place("stadium_seating_ROOT", f"Stand_R_{i}", Vector((28, y, 0)), Euler((0, 0, -math.pi / 2)), 16.0)

    # Gantry over start
    place("traffic_light_gantry_ROOT", "StartGantry", p0 + Vector((0, 0, 0)), Euler((0, 0, 0)), (14.0, 8.0, 10.0))

    # Towers
    place("guard_tower_ROOT", "Tower_T1", Vector((55, 410, 0)), Euler((0, 0, 0.4)), 9.0)
    place("guard_tower_ROOT", "Tower_T5", Vector((440, 280, 0)), Euler((0, 0, 1.2)), 9.0)
    place("guard_tower_ROOT", "Tower_Hairpin", Vector((340, 28, 0)), Euler((0, 0, 0.2)), 8.0)

    # Tire barriers at hairpin and T1
    for i, loc in enumerate((
        Vector((360, 22, 0)), Vector((390, 35, 0)), Vector((320, 22, 0)),
        Vector((40, 430, 0)), Vector((80, 445, 0)), Vector((20, 400, 0)),
    )):
        place("tire_stack_ROOT", f"Tires_{i}", loc, Euler((0, 0, i * 0.4)), 1.8)

    # Cones pit exit
    for i in range(10):
        place("traffic_cone_ROOT", f"Cone_{i}", Vector((-10, 230 + i * 4.0, 0)), Euler((0, 0, 0)), 0.55)

    # Cameras
    place("cinema_camera_ROOT", "Cam_T1", Vector((30, 410, 0)), Euler((0, 0, 0.6)), 1.4)
    place("cinema_camera_ROOT", "Cam_Hairpin", Vector((330, 28, 0)), Euler((0, 0, 2.2)), 1.4)
    place("cinema_camera_ROOT", "Cam_Straight", Vector((18, 80, 0)), Euler((0, 0, math.pi)), 1.4)

    # Signboards
    for i, (loc, rot) in enumerate((
        (Vector((18, 40, 0)), 0.0),
        (Vector((18, 180, 0)), 0.0),
        (Vector((250, 470, 0)), 3.14),
        (Vector((445, 250, 0)), 1.57),
        (Vector((280, 25, 0)), 0.2),
    )):
        place("signboard_ROOT", f"Board_{i}", loc, Euler((0, 0, rot)), 4.5)

    # Paddock
    place("bar_counter_ROOT", "PaddockBar", Vector((-48, 40, 0)), Euler((0, 0, math.pi / 2)), 3.5)
    place("tire_rack_ROOT", "PitRack_0", Vector((-28, 70, 0)), Euler((0, 0, 0)), 2.2)
    place("tire_rack_ROOT", "PitRack_1", Vector((-28, 150, 0)), Euler((0, 0, 0)), 2.2)
    place("steering_wheel_ROOT", "PaddockWheel", Vector((-45, 48, 1.1)), Euler((math.pi / 2, 0, 0)), 0.35)

    # Racing line JSON (Blender XYZ, Z-up). Godot converts.
    line = []
    acc = 0.0
    for i, (p, tan, right, up) in enumerate(frm):
        if i > 0:
            acc += (p - frm[i - 1][0]).length
        # racing line slightly inside of geometric center toward apex (offset 0)
        line.append({
            "x": p.x, "y": p.y, "z": p.z + 0.04,
            "tx": tan.x, "ty": tan.y, "tz": tan.z,
            "s": acc,
        })
    with open(os.path.join(TRACK_DIR, "racing_line.json"), "w", encoding="utf-8") as f:
        json.dump({"length": length, "width": ROAD_WIDTH, "points": line}, f)
    print("WROTE racing_line", len(line), "length", length)

    # Export track (visual + collision + props on circuit collection)
    objs = list(track_col.objects)
    export_glb(objs, os.path.join(TRACK_DIR, "apex_circuit.glb"))

    blend_path = os.path.join(ROOT, "blender", "apex_circuit.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("SAVED", blend_path)


main()
