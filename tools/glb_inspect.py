"""Inspect a GLB: node tree, world-space mesh bounds, materials, textures.

Usage: python tools/glb_inspect.py <file.glb> [--nodes]

Prints the bounding box of the whole model and of every mesh node in the
model's own root space, so a Godot scene can place the artwork exactly where
it belongs even when the exporter left the object metres off centre.
"""

import json
import struct
import sys
from pathlib import Path

import numpy as np


def load_glb(path: Path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    offset = 12
    gltf = None
    bin_chunk = b""
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:
            gltf = json.loads(payload.decode("utf-8"))
        elif chunk_type == 0x004E4942:
            bin_chunk = payload
        offset += 8 + chunk_len + ((4 - chunk_len % 4) % 4 if chunk_len % 4 else 0)
    return gltf, bin_chunk, version


COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
        5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_accessor(gltf, bin_chunk, index):
    acc = gltf["accessors"][index]
    fmt, size = COMP[acc["componentType"]]
    n = NC[acc["type"]]
    count = acc["count"]
    bv = gltf["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or size * n
    out = np.zeros((count, n), dtype=np.float64)
    for i in range(count):
        vals = struct.unpack_from("<" + fmt * n, bin_chunk, base + i * stride)
        out[i] = vals
    return out


def node_matrix(node):
    if "matrix" in node:
        m = np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
        return m
    t = np.eye(4)
    if "translation" in node:
        t[:3, 3] = node["translation"]
    r = np.eye(4)
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        r[:3, :3] = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ])
    s = np.eye(4)
    if "scale" in node:
        s[0, 0], s[1, 1], s[2, 2] = node["scale"]
    return t @ r @ s


def mesh_bounds(gltf, bin_chunk, mesh_index):
    lo = np.array([np.inf] * 3)
    hi = np.array([-np.inf] * 3)
    for prim in gltf["meshes"][mesh_index]["primitives"]:
        pos = read_accessor(gltf, bin_chunk, prim["attributes"]["POSITION"])[:, :3]
        lo = np.minimum(lo, pos.min(axis=0))
        hi = np.maximum(hi, pos.max(axis=0))
    return lo, hi


def main():
    path = Path(sys.argv[1])
    gltf, bin_chunk, version = load_glb(path)
    show_nodes = "--nodes" in sys.argv
    print(f"=== {path.name}  (glTF {version}, generator={gltf.get('asset', {}).get('generator')})")
    print(f"nodes={len(gltf.get('nodes', []))} meshes={len(gltf.get('meshes', []))} "
          f"materials={len(gltf.get('materials', []))} images={len(gltf.get('images', []))} "
          f"animations={len(gltf.get('animations', []))}")

    lo = np.array([np.inf] * 3)
    hi = np.array([-np.inf] * 3)
    rows = []

    def walk(index, parent):
        nonlocal lo, hi
        node = gltf["nodes"][index]
        xf = parent @ node_matrix(node)
        if "mesh" in node:
            mlo, mhi = mesh_bounds(gltf, bin_chunk, node["mesh"])
            corners = np.array([[x, y, z, 1.0] for x in (mlo[0], mhi[0])
                                for y in (mlo[1], mhi[1]) for z in (mlo[2], mhi[2])])
            world = (xf @ corners.T).T[:, :3]
            wlo, whi = world.min(axis=0), world.max(axis=0)
            lo = np.minimum(lo, wlo)
            hi = np.maximum(hi, whi)
            mats = [p.get("material") for p in gltf["meshes"][node["mesh"]]["primitives"]]
            mat_names = [gltf["materials"][m].get("name", m) if m is not None else None for m in mats]
            rows.append((node.get("name", f"node{index}"), wlo, whi, mat_names))
        for child in node.get("children", []):
            walk(child, xf)

    for scene in gltf.get("scenes", []):
        for root in scene.get("nodes", []):
            walk(root, np.eye(4))

    print(f"MODEL BOUNDS min={np.round(lo, 4).tolist()} max={np.round(hi, 4).tolist()}")
    print(f"MODEL SIZE  {np.round(hi - lo, 4).tolist()}  centre={np.round((hi + lo) / 2, 4).tolist()}")
    if show_nodes:
        print("\n-- mesh nodes (world bounds in root space) --")
        for name, wlo, whi, mat_names in rows:
            print(f"  {name:32s} min={np.round(wlo, 3).tolist()} "
                  f"max={np.round(whi, 3).tolist()} size={np.round(whi - wlo, 3).tolist()} "
                  f"mats={mat_names}")
    print("\n-- materials --")
    for i, mat in enumerate(gltf.get("materials", [])):
        pbr = mat.get("pbrMetallicRoughness", {})
        print(f"  [{i}] {mat.get('name')}: base={pbr.get('baseColorFactor')} "
              f"metal={pbr.get('metallicFactor')} rough={pbr.get('roughnessFactor')} "
              f"tex={'baseColorTexture' in pbr} mr={'metallicRoughnessTexture' in pbr} "
              f"norm={'normalTexture' in mat} emissive={mat.get('emissiveFactor')}")
    print("\n-- images --")
    for i, img in enumerate(gltf.get("images", [])):
        print(f"  [{i}] {img.get('name')} mime={img.get('mimeType')} uri={img.get('uri')}")


if __name__ == "__main__":
    main()
