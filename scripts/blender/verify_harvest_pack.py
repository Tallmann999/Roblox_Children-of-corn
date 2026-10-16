"""Read-only binary audit of the offline Harvest Warden delivery.

This reads actual FBX arrays and GLB buffer bytes, not generator success flags.
It writes only assets/harvest-warden/validation.json. It never connects to Studio.
Run with ordinary Python: python scripts/blender/verify_harvest_pack.py
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "assets/harvest-warden"
OUT = PACK / "validation.json"
CLIPS = {"Idle": 72 / 24, "Walk": 32 / 24, "Chase": 22 / 24,
         "Trapped": 30 / 24, "Capture": 18 / 24}
FBX_SECOND = 46186158000
ERRORS: list[str] = []


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def relative(path):
    return path.relative_to(ROOT).as_posix()


def png_info(data):
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), "PNG signature")
    pos, chunks, compressed = 8, [], bytearray()
    dimensions = None
    while pos < len(data):
        size = struct.unpack_from(">I", data, pos)[0]
        kind, payload = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + size]
        require(len(payload) == size, "PNG truncated chunk")
        crc = struct.unpack_from(">I", data, pos + 8 + size)[0]
        require(zlib.crc32(kind + payload) == crc, "PNG chunk CRC")
        chunks.append(kind.decode("ascii"))
        if kind == b"IHDR":
            dimensions = struct.unpack(">IIBBBBB", payload)
        if kind == b"IDAT":
            compressed.extend(payload)
        pos += 12 + size
        if kind == b"IEND":
            break
    require(pos == len(data) and chunks[-1] == "IEND", "PNG end marker")
    require(dimensions is not None, "PNG dimensions")
    width, height, depth, color, compression, filtering, interlace = dimensions
    decoded = zlib.decompress(compressed)
    require(width > 0 and height > 0 and decoded, "PNG has no decoded pixels")
    if depth == 8 and interlace == 0 and color in (0, 2, 4, 6):
        channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
        stride = 1 + width * channels
        require(len(decoded) == height * stride, "PNG scanline length")
        require(all(decoded[y * stride] <= 4 for y in range(height)), "PNG scanline filter")
    return {"width": width, "height": height, "bit_depth": depth,
            "color_type": color, "decoded_bytes": len(decoded), "sha256": sha(data)}


TEXTURES = {}


def audit_texture(path):
    info = png_info(path.read_bytes())
    TEXTURES[path.stem] = info
    return {"path": relative(path), **info}


COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
              5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4,
         "MAT2": 4, "MAT3": 9, "MAT4": 16}


class GLB:
    def __init__(self, path):
        self.path = path
        self.raw = path.read_bytes()
        magic, version, length = struct.unpack_from("<4sII", self.raw)
        require(magic == b"glTF" and version == 2 and length == len(self.raw), "GLB header")
        chunks, pos = {}, 12
        while pos < length:
            size, kind = struct.unpack_from("<II", self.raw, pos)
            require(pos + 8 + size <= length, "GLB truncated chunk")
            require(kind not in chunks, "GLB duplicate chunk")
            chunks[kind] = self.raw[pos + 8:pos + 8 + size]
            pos += 8 + size
        require(pos == length, "GLB chunk end")
        self.doc = json.loads(chunks[0x4E4F534A])
        self.binary = chunks.get(0x004E4942, b"")
        require(self.doc["asset"]["version"] == "2.0", "glTF version")
        require(len(self.doc["buffers"]) == 1, "GLB must contain one embedded buffer")
        require("uri" not in self.doc["buffers"][0], "External GLB buffer")
        require(self.doc["buffers"][0]["byteLength"] <= len(self.binary), "GLB buffer size")
        self.cache = {}

    def view(self, index):
        view = self.doc["bufferViews"][index]
        require(view["buffer"] == 0, "External buffer view")
        offset = view.get("byteOffset", 0)
        end = offset + view["byteLength"]
        require(0 <= offset <= end <= len(self.binary), "Buffer view bounds")
        return self.binary[offset:end], view

    def accessor(self, index, normalized=False):
        key = (index, normalized)
        if key in self.cache:
            return self.cache[key]
        item = self.doc["accessors"][index]
        require("sparse" not in item, "Sparse accessors require separate audit")
        data, view = self.view(item["bufferView"])
        code, byte_size = COMPONENTS[item["componentType"]]
        width = WIDTH[item["type"]]
        stride = view.get("byteStride", byte_size * width)
        offset = item.get("byteOffset", 0)
        require(stride >= byte_size * width, "Accessor stride")
        require(item["count"] > 0, "Empty accessor")
        require(offset + (item["count"] - 1) * stride + byte_size * width <= len(data), "Accessor bounds")
        result = [struct.unpack_from("<" + code * width, data, offset + n * stride)
                  for n in range(item["count"])]
        require(all(math.isfinite(x) for row in result for x in row), "Nonfinite accessor")
        if normalized and item.get("normalized") and item["componentType"] != 5126:
            scale = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535,
                     5125: 4294967295}[item["componentType"]]
            result = [tuple(max(-1, x / scale) for x in row) for row in result]
        self.cache[key] = result
        return result


def area_squared(a, b, c):
    u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
    cross = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2],
             u[0] * v[1] - u[1] * v[0])
    return sum(x * x for x in cross)


def bounds(points):
    return {"min": [min(p[i] for p in points) for i in range(3)],
            "max": [max(p[i] for p in points) for i in range(3)]}


def position_fingerprint(points):
    # JSON distinguishes -0.0 and 0.0 although the coordinates are equal.
    rounded = {tuple(0.0 if round(x, 5) == 0 else round(x, 5) for x in p) for p in points}
    return sha(json.dumps(sorted(rounded)).encode())


def audit_glb(path):
    glb = GLB(path)
    doc = glb.doc
    for i in range(len(doc.get("accessors", []))):
        glb.accessor(i)
    images = []
    for image in doc.get("images", []):
        require("uri" not in image and image.get("mimeType") == "image/png", "Unembedded image")
        payload, _ = glb.view(image["bufferView"])
        info = png_info(payload)
        require(image["name"] in TEXTURES, "Unknown embedded texture: " + image["name"])
        require(info["sha256"] == TEXTURES[image["name"]]["sha256"], "Embedded texture differs")
        images.append({"name": image["name"], **info})
    for texture in doc.get("textures", []):
        require(0 <= texture["source"] < len(images), "Texture image reference")
    for material in doc.get("materials", []):
        tex = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if tex:
            require(0 <= tex["index"] < len(doc.get("textures", [])), "Material texture reference")
    meshes, all_positions = [], []
    for mesh in doc.get("meshes", []):
        count, vertices, degenerates = 0, 0, 0
        mesh_positions = []
        for primitive in mesh["primitives"]:
            require(primitive.get("mode", 4) == 4, "Nontriangle primitive")
            attrs = primitive["attributes"]
            positions = glb.accessor(attrs["POSITION"])
            normals = glb.accessor(attrs["NORMAL"])
            uv = glb.accessor(attrs["TEXCOORD_0"])
            require(len(positions) == len(normals) == len(uv), "Position/normal/UV count")
            require(all(abs(sum(x * x for x in row) - 1) < 0.002 for row in normals), "Nonunit normals")
            indexes = [row[0] for row in glb.accessor(primitive["indices"])]
            require(len(indexes) % 3 == 0, "Triangle index remainder")
            require(min(indexes) >= 0 and max(indexes) < len(positions), "Triangle vertex reference")
            for i in range(0, len(indexes), 3):
                degenerates += area_squared(*(positions[indexes[i + n]] for n in range(3))) < 1e-18
            if "JOINTS_0" in attrs:
                joints = glb.accessor(attrs["JOINTS_0"])
                weights = glb.accessor(attrs["WEIGHTS_0"], normalized=True)
                require(len(joints) == len(weights) == len(positions), "Skin vertex count")
                require(len(doc.get("skins", [])) == 1, "Expected one warden skin")
                joint_count = len(doc["skins"][0]["joints"])
                require(all(all(0 <= j < joint_count for j in row) for row in joints), "Joint reference")
                require(all(all(w >= 0 for w in row) and abs(sum(row) - 1) < 1e-5 for row in weights),
                        "Non-normalized bone weights")
            elif "warden" in path.parts:
                raise ValueError("Unskinned warden primitive")
            count += len(indexes) // 3
            vertices += len(positions)
            mesh_positions.extend(positions)
        require(degenerates == 0, f"Degenerate triangles in {mesh['name']}: {degenerates}")
        all_positions.extend(mesh_positions)
        meshes.append({"name": mesh["name"], "vertices_after_uv_splits": vertices,
                       "triangles": count, "bounds_y_up": bounds(mesh_positions), "degenerate_triangles": degenerates})
    require(meshes, "GLB has no meshes")
    animations = []
    for animation in doc.get("animations", []):
        times, varied, digest_parts = [], False, []
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            inputs = [row[0] for row in glb.accessor(sampler["input"])]
            outputs = glb.accessor(sampler["output"])
            require(all(inputs[i] < inputs[i + 1] for i in range(len(inputs) - 1)), "Nonmonotonic animation time")
            require(0 <= channel["target"]["node"] < len(doc["nodes"]), "Animation node reference")
            times.extend(inputs)
            varied |= any(any(abs(a - b) > 1e-5 for a, b in zip(row, outputs[0])) for row in outputs[1:])
            digest_parts.append({"target": doc["nodes"][channel["target"]["node"]]["name"],
                                 "path": channel["target"]["path"],
                                 "values": [[round(x, 6) for x in row] for row in outputs]})
        animations.append({"name": animation.get("name"), "channels": len(animation["channels"]),
                           "time_start": min(times), "time_end": max(times),
                           "duration_seconds": max(times) - min(times), "has_motion": varied,
                           "motion_sha256": sha(json.dumps(digest_parts, sort_keys=True).encode())})
    report = {"path": relative(path), "bytes": len(glb.raw), "sha256": sha(glb.raw),
              "mesh_count": len(meshes), "triangles": sum(m["triangles"] for m in meshes),
              "meshes": meshes, "embedded_textures": images, "animations": animations,
              "all_accessors_finite": True, "all_uvs_finite": True,
              "bounds_y_up_local_mesh_space": bounds(all_positions)}
    if "corn" in path.parts:
        require(abs(report["bounds_y_up_local_mesh_space"]["min"][1]) < 1e-5, "Corn root above/below ground")
        require(abs(report["bounds_y_up_local_mesh_space"]["max"][1] - 8) < 1e-5, "Corn height differs from 8 studs")
        require(len(images) == 1 and images[0]["name"] == "corn_leaf_dry", "Corn shared texture")
        report["geometry_sha256"] = sha(json.dumps(all_positions).encode())
        report["unique_positions_rounded_5_sha256"] = position_fingerprint(all_positions)
    if "warden" in path.parts:
        require({item["name"] for item in images} == {"corn_leaf_dry", "coat_canvas", "burlap"},
                "Warden requires three embedded source textures")
        eyes = [mat for mat in doc["materials"] if mat.get("name") == "LanternEye_Red"]
        require(len(eyes) == 1 and eyes[0].get("emissiveFactor", [0])[0] > .9, "Missing red emissive eye material")
        require(len(doc.get("skins", [])) == 1 and len(doc["skins"][0]["joints"]) == 10, "Warden bone count")
        require(len(animations) == 5, "Expected exactly five warden clips; got " + str(len(animations)))
        variant = path.parent.name.capitalize()
        expected = {variant + "_" + name for name in CLIPS}
        actual = {a["name"] for a in animations}
        require(actual == expected or actual == set(CLIPS), "Foreign/missing animation names: " + str(actual))
        for item in animations:
            name = item["name"].rsplit("_", 1)[-1]
            require(abs(item["duration_seconds"] - CLIPS[name]) < 1e-5, "Animation duration: " + item["name"])
            require(item["has_motion"], "Static animation: " + item["name"])
        require(len({a["motion_sha256"] for a in animations}) == 5, "Duplicate motion in distinct clips")
        report["bone_count"] = 10
        report["normalized_weights_all_vertices"] = True
    return report


spec = importlib.util.spec_from_file_location("harvest_readonly_fbx", ROOT / "scripts/prepare-farm-assets.py")
fbx_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fbx_module)


def fbx_props(node):
    props = node.child("Properties70")
    return {c.props[0]: c.props[4:] for c in props.children} if props else {}


def audit_fbx(path):
    raw = path.read_bytes()
    doc = fbx_module.read_fbx(path)
    objects = next(n for n in doc["nodes"] if n.name == "Objects").children
    by_id = {obj.props[0]: obj for obj in objects}
    connections = next(n for n in doc["nodes"] if n.name == "Connections").children
    links = [(n.props[1], n.props[2]) for n in connections if n.props[0] == "OO"]
    meshes, videos, all_positions = [], [], []
    for obj in objects:
        if obj.name == "Video":
            content = obj.child("Content")
            require(content and content.props and isinstance(content.props[0], bytes), "FBX missing embedded image")
            info = png_info(content.props[0])
            require(info["sha256"] in {v["sha256"] for v in TEXTURES.values()}, "FBX unknown embedded image")
            videos.append({"name": obj.props[1].split("\x00")[0], **info})
        if obj.name != "Geometry" or obj.props[2] != "Mesh":
            continue
        verts = obj.child("Vertices").props[0]
        require(len(verts) % 3 == 0 and all(math.isfinite(x) for x in verts), "FBX nonfinite positions")
        positions = [tuple(verts[i:i + 3]) for i in range(0, len(verts), 3)]
        all_positions.extend(positions)
        indexes = obj.child("PolygonVertexIndex").props[0]
        uv_layers = [n for n in obj.children if n.name == "LayerElementUV"]
        require(uv_layers, "FBX missing UV layer")
        for layer in uv_layers:
            coords = layer.child("UV").props[0]
            require(len(coords) % 2 == 0 and all(math.isfinite(x) for x in coords), "FBX nonfinite UV")
            uv_indexes = layer.child("UVIndex")
            if uv_indexes:
                require(all(0 <= n < len(coords) // 2 for n in uv_indexes.props[0]), "FBX UV index")
        triangles, polygon_size, polygon, degenerates = 0, 0, [], 0
        for index in indexes:
            require(0 <= (index if index >= 0 else -index - 1) < len(verts) // 3, "FBX vertex reference")
            polygon.append(index if index >= 0 else -index - 1)
            polygon_size += 1
            if index < 0:
                require(polygon_size >= 3, "FBX polygon too small")
                if polygon_size == 3:
                    degenerates += area_squared(*(positions[i] for i in polygon)) < 1e-18
                triangles += polygon_size - 2
                polygon_size, polygon = 0, []
        require(polygon_size == 0, "FBX unterminated polygon")
        require(degenerates == 0, f"FBX degenerate triangles: {degenerates}")
        mesh = {"name": obj.props[1].split("\x00")[0], "vertices": len(verts) // 3,
                "triangles": triangles, "uv_layers": len(uv_layers)}
        if "warden" in path.parts:
            skins = [by_id[src] for src, dst in links if dst == obj.props[0] and
                     src in by_id and by_id[src].name == "Deformer" and by_id[src].props[2] == "Skin"]
            require(len(skins) == 1, "FBX mesh requires one skin")
            clusters = [by_id[src] for src, dst in links if dst == skins[0].props[0] and
                        src in by_id and by_id[src].name == "Deformer" and by_id[src].props[2] == "Cluster"]
            sums = [0.] * mesh["vertices"]
            influences = [0] * mesh["vertices"]
            for cluster in clusters:
                indices, weights = cluster.child("Indexes"), cluster.child("Weights")
                if indices is None:
                    continue
                require(weights and len(weights.props[0]) == len(indices.props[0]), "FBX skin array count")
                for index, weight in zip(indices.props[0], weights.props[0]):
                    require(0 <= index < len(sums) and math.isfinite(weight) and weight >= 0, "FBX skin weight")
                    sums[index] += weight
                    influences[index] += weight > 0
            require(all(abs(s - 1) < 1e-5 for s in sums), "FBX uncovered/non-normalized skin vertex")
            require(max(influences) <= 4, "FBX exceeds four bone influences")
            mesh["all_vertices_weighted"] = True
            mesh["max_influences"] = max(influences)
        meshes.append(mesh)
    for obj in objects:
        if obj.name == "Texture":
            require(any(src in by_id and by_id[src].name == "Video" for src, dst in links if dst == obj.props[0]),
                    "FBX texture missing embedded video connection")
    bones = [obj for obj in objects if obj.name == "Model" and obj.props[2] == "LimbNode"]
    curves = [obj for obj in objects if obj.name == "AnimationCurve"]
    stacks = [obj for obj in objects if obj.name == "AnimationStack"]
    animation = None
    if "animations" in path.parts:
        require(len(bones) == 10 and len(stacks) == 1 and not meshes, "Animation FBX structure")
        require(curves, "Animation FBX missing curves")
        times, varied = [], False
        digest = hashlib.sha256()
        for curve in curves:
            keys, values = curve.child("KeyTime").props[0], curve.child("KeyValueFloat").props[0]
            require(len(keys) == len(values) and len(keys) >= 2, "FBX curve sample count")
            require(all(keys[i] < keys[i + 1] for i in range(len(keys) - 1)), "FBX curve time order")
            require(all(math.isfinite(v) for v in values), "FBX nonfinite animation")
            varied |= max(values) - min(values) > 1e-5
            times.extend(keys)
            digest.update(struct.pack("<" + "f" * len(values), *values))
        duration = (max(times) - min(times)) / FBX_SECOND
        require(path.stem in CLIPS, "Unexpected animation FBX")
        require(abs(duration - CLIPS[path.stem]) < 1e-5,
                f"FBX {path.stem} duration {duration:.6f}; expected {CLIPS[path.stem]:.6f}")
        require(varied, "Static animation FBX")
        animation = {"name": path.stem, "duration_seconds": duration, "curves": len(curves),
                     "has_motion": varied, "motion_sha256": digest.hexdigest()}
    else:
        require(meshes, "FBX has no meshes")
        require(not curves and not stacks, "Rest/static FBX contains animation")
        if "warden" in path.parts:
            require(len(bones) == 10 and len(meshes) == 9, "Warden FBX section/bone count")
        require(videos, "Textured FBX missing embedded PNGs")
    report = {"path": relative(path), "bytes": len(raw), "sha256": sha(raw),
            "version": doc["version"], "mesh_count": len(meshes), "meshes": meshes,
            "triangles": sum(m["triangles"] for m in meshes), "bone_count": len(bones),
            "embedded_textures": videos, "animation": animation}
    if "corn" in path.parts:
        report["bounds_y_up"] = bounds(all_positions)
        require(abs(report["bounds_y_up"]["min"][1]) < 1e-5 and
                abs(report["bounds_y_up"]["max"][1] - 8) < 1e-5, "FBX corn height/root")
        report["unique_positions_rounded_5_sha256"] = position_fingerprint(all_positions)
    return report


def protected_files():
    names = subprocess.check_output(["git", "ls-files", "-z", "--", "assets/corn", "assets/farm", "place"], cwd=ROOT)
    report = []
    for name in names.decode().split("\x00"):
        if not name:
            continue
        # Raw equality is meaningful for these binary originals. Text files have
        # existing checkout EOL rules and are checked through Git below.
        if Path(name).suffix.lower() not in {".fbx", ".png", ".rbxl"}:
            continue
        original = subprocess.check_output(["git", "show", "HEAD:" + name], cwd=ROOT)
        current = (ROOT / name).read_bytes()
        require(current == original, "Protected original differs from HEAD: " + name)
        report.append({"path": name, "bytes": len(current), "sha256": sha(current), "head_bytes_equal": True})
    return report


def attempt(label, function, *args):
    try:
        return function(*args)
    except Exception as exc:
        message = label + ": " + str(exc)
        ERRORS.append(message)
        return {"path": label, "error": str(exc)}


def reopen_blend(blender, path):
    before = path.read_bytes()
    expression = r'''
import bpy,json,math,os
meshes=[o for o in bpy.data.objects if o.type=='MESH']
for obj in meshes:
    assert all(math.isfinite(x) for v in obj.data.vertices for x in v.co),obj.name
    for layer in obj.data.uv_layers:
        assert all(math.isfinite(x) for item in layer.data for x in item.uv),obj.name
images=[]
for image in bpy.data.images:
    if image.source=='FILE':
        packed=bool(image.packed_file) or bool(image.packed_files)
        exists=os.path.isfile(bpy.path.abspath(image.filepath))
        assert packed or exists,'Missing texture '+image.name
        images.append({'name':image.name,'packed':packed,'external_file_exists':exists,
                       'dimensions':list(image.size)})
report={'blender_version':bpy.app.version_string,'mesh_objects':len(meshes),
        'armatures':[{'name':o.name,'bones':len(o.data.bones)} for o in bpy.data.objects if o.type=='ARMATURE'],
        'actions':[{'name':a.name,'frame_range':list(a.frame_range)} for a in bpy.data.actions],
        'fps':bpy.context.scene.render.fps,'textures':images,'all_mesh_positions_uvs_finite':True}
print('HARVEST_BLEND_READBACK='+json.dumps(report))
'''
    result = subprocess.run([str(blender), "--background", "--disable-autoexec", str(path),
                             "-t", "2", "--python-expr", expression],
                            cwd=ROOT, capture_output=True, text=True, timeout=90)
    require(result.returncode == 0, "Blender readback process failed: " + result.stderr[-1000:])
    lines = [line for line in result.stdout.splitlines() if line.startswith("HARVEST_BLEND_READBACK=")]
    require(len(lines) == 1, "Blender readback did not return structured result: " + result.stdout[-1000:])
    require(path.read_bytes() == before, "Blender readback modified source file")
    return {"path": relative(path), "bytes": len(before), "sha256": sha(before),
            "source_bytes_unchanged": True, **json.loads(lines[0].split("=", 1)[1])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", type=Path, help="Optional executable for actual read-only .blend reopen")
    args = parser.parse_args()
    textures = [attempt(relative(p), audit_texture, p) for p in sorted((PACK / "textures").glob("*.png"))]
    require(len(textures) == 5, "Expected five authored textures")
    glbs = [attempt(relative(p), audit_glb, p) for p in sorted((PACK / "exports").rglob("*.glb"))]
    fbxs = [attempt(relative(p), audit_fbx, p) for p in sorted((PACK / "exports").rglob("*.fbx"))]
    require(len(glbs) == 26 and len(fbxs) == 36, "Expected 26 model pairs plus ten animation FBXs")
    for glb in glbs:
        if "error" in glb:
            continue
        fbx = next((item for item in fbxs if item["path"] == glb["path"][:-3] + "fbx"), None)
        if fbx and "error" not in fbx and fbx["triangles"] != glb["triangles"]:
            ERRORS.append(glb["path"] + ": FBX/glTF triangle count differs")
        if fbx and "error" not in fbx and "/corn/" in glb["path"] and \
                glb["unique_positions_rounded_5_sha256"] != fbx["unique_positions_rounded_5_sha256"]:
            ERRORS.append(glb["path"] + ": FBX/glTF corn positions differ")
    corn = [item for item in glbs if "/corn/" in item["path"] and "error" not in item]
    for lod in ("Near", "Mid", "Far"):
        variants = [item for item in corn if item["path"].endswith("_" + lod + ".glb")]
        if len(variants) != 4 or len({item["geometry_sha256"] for item in variants}) != 4:
            ERRORS.append("Corn " + lod + ": expected four distinct exported geometries")
    for variant in "ABCD":
        counts = [next((item["triangles"] for item in corn if
                        item["path"].endswith(f"Corn_{variant}_{lod}.glb")), 0) for lod in ("Near", "Mid", "Far")]
        if not counts[0] > counts[1] > counts[2] > 0:
            ERRORS.append("Corn " + variant + ": LOD triangle budgets do not decrease")
    for variant in ("classic", "detailed"):
        clips = [item["animation"] for item in fbxs if "/" + variant + "/animations/" in item["path"] and "error" not in item]
        if len(clips) != 5 or len({item["motion_sha256"] for item in clips}) != 5:
            ERRORS.append(variant + ": expected five distinct animation FBX curves")
    preservation = attempt("protected originals", protected_files)
    readbacks = [attempt(relative(path), reopen_blend, args.blender, path)
                 for path in (PACK / "corn.blend", PACK / "environment.blend", PACK / "warden.blend")] if args.blender else []
    game_diff = subprocess.run(["git", "diff", "--exit-code", "HEAD", "--", "src", "assets/corn", "assets/farm", "place"],
                               cwd=ROOT, capture_output=True, text=True)
    if game_diff.returncode:
        ERRORS.append("Existing game sources/original art/place differ from HEAD")
    report = {"schema": "harvest-pack-independent-binary-audit-v1", "date": "2026-10-16",
              "ok": not ERRORS, "scope": "Offline FBX/GLB arrays, embedded bitmap bytes, protected source bytes. No Studio connection.",
              "textures": textures, "glb_models": glbs, "fbx_exports": fbxs,
              "protected_originals": preservation,
              "blender_source_readbacks": readbacks,
              "existing_game_and_original_art_git_diff_clean": game_diff.returncode == 0,
              "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "limitations": ["Roblox import scale, orientation, material appearance and animation playback remain untested in Studio.",
                              "Red emissive meshes do not export Roblox PointLights; engine lights and range must be integrated and tested.",
                              "No world replacement, monster-controller integration, network playtest or FPS measurement was performed.",
                              "This binary audit does not prove art quality, seamless tiling, fear or resemblance to the concept image."],
              "errors": ERRORS}
    OUT.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "glb_models": len(glbs), "fbx_exports": len(fbxs),
                      "textures": len(textures), "report": relative(OUT), "errors": ERRORS}, ensure_ascii=False))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
