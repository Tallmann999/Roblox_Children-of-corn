"""Build lazy Roblox EditableMesh data from the actual verified Harvest GLB bytes.

Writes only HarvestGeometryData and the new pack catalog/manifest. No Studio,
network, place serialization, asset upload or imported-source modification.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "assets/harvest-warden"
OUT = ROOT / "src/shared/Game/HarvestGeometryData"
MAX_SOURCE_BYTES = 135000
OWNER = "harvest_warden_v1"
HEADER = "-- Generated verified Harvest GLB geometry; peer-local art only.\n"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def check(condition, message):
    if not condition:
        raise ValueError(message)


def compact(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("utf-8")


def clean(value):
    check(math.isfinite(value), "Nonfinite geometry channel")
    result = round(float(value), 6)
    return 0 if result == 0 else result


def multiply(a, b):
    return [[sum(a[row][k] * b[k][col] for k in range(4)) for col in range(4)] for row in range(4)]


def identity():
    return [[1.0 if row == col else 0.0 for col in range(4)] for row in range(4)]


def local_matrix(node):
    if "matrix" in node:
        data = node["matrix"]
        check(len(data) == 16, "Invalid glTF matrix")
        return [[data[col * 4 + row] for col in range(4)] for row in range(4)]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    length = math.sqrt(x*x + y*y + z*z + w*w)
    check(length > 0, "Zero glTF quaternion")
    x, y, z, w = [v / length for v in (x, y, z, w)]
    rotation = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
    scale = node.get("scale", [1, 1, 1])
    translation = node.get("translation", [0, 0, 0])
    matrix = identity()
    for row in range(3):
        for col in range(3):
            matrix[row][col] = rotation[row][col] * scale[col]
        matrix[row][3] = translation[row]
    return matrix


def normal_matrix(matrix):
    a,b,c = matrix[0][:3]
    d,e,f = matrix[1][:3]
    g,h,i = matrix[2][:3]
    determinant = a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
    check(abs(determinant) > 1e-12, "Singular glTF node transform")
    # Cofactor matrix is inverse-transpose multiplied by determinant.
    cofactors = [[e*i-f*h, f*g-d*i, d*h-e*g],
                 [c*h-b*i, a*i-c*g, b*g-a*h],
                 [b*f-c*e, c*d-a*f, a*e-b*d]]
    return [[v / determinant for v in row] for row in cofactors], determinant


def position(matrix, value):
    return [clean(sum(matrix[row][col] * value[col] for col in range(3)) + matrix[row][3]) for row in range(3)]


def normal(matrix, value):
    vector = [sum(matrix[row][col] * value[col] for col in range(3)) for row in range(3)]
    length = math.sqrt(sum(v*v for v in vector))
    check(length > 0.001, "Zero transformed vertex normal")
    return [clean(v / length) for v in vector]


def sources():
    result = {}
    for variety in "ABCD":
        for lod in ("Near", "Mid", "Far"):
            key = f"Corn_{variety}_{lod}"
            result[key] = ("corn", PACK / "exports/corn" / key / f"{key}.glb")
    for variant in ("Classic", "Detailed"):
        result[f"Warden{variant}"] = ("warden", PACK / "exports/warden" / variant.lower() / "HarvestWarden.glb")
    for key in ("BarnDark_Open", "Fence_01", "Fence_02", "Fence_03", "Rock_01", "Rock_02", "Rock_03", "Rock_04", "Rock_05", "Ground_Tile_8", "Path_Tile_8"):
        result[key] = ("environment", PACK / "exports/environment" / key / f"{key}.glb")
    return dict(sorted(result.items()))


def material_info(glb, primitive, registry, png_hashes):
    index = primitive.get("material")
    material = glb.doc.get("materials", [])[index] if index is not None else {}
    pbr = material.get("pbrMetallicRoughness", {})
    texture_id = ""
    if "baseColorTexture" in pbr:
        texture = glb.doc["textures"][pbr["baseColorTexture"]["index"]]
        image = glb.doc["images"][texture["source"]]
        check("bufferView" in image and image.get("mimeType") == "image/png", "Only embedded verified PNG textures are accepted")
        png = glb.view(image["bufferView"])[0]
        texture_name = png_hashes.get(sha(png))
        check(texture_name in registry, "GLB embedded texture does not match the exact uploaded PNG bytes")
        texture_id = registry[texture_name]
    color = [clean(v) for v in pbr.get("baseColorFactor", [1,1,1,1])[:3]]
    emissive = material.get("emissiveFactor", [0,0,0])
    name = material.get("name", "")
    if max(emissive) > 0:
        roblox_material = "Neon"
    elif texture_id in (registry.get("corn_leaf_dry"), registry.get("burlap"), registry.get("coat_canvas")):
        roblox_material = "Fabric"
    elif texture_id == registry.get("barn_wood_dark"):
        roblox_material = "Wood"
    elif texture_id == registry.get("soil_gravel"):
        roblox_material = "Ground"
    else:
        roblox_material = "SmoothPlastic"
    return texture_id, color, roblox_material, name


def extract(key, kind, path, GLB, registry, png_hashes):
    glb = GLB(path)
    doc = glb.doc
    parents = {}
    for parent_index, node in enumerate(doc.get("nodes", [])):
        for child in node.get("children", []):
            check(child not in parents, "glTF node has two parents")
            parents[child] = parent_index
    matrices = {}
    def world(index, ancestors=None):
        if index in matrices:
            return matrices[index]
        ancestors = set() if ancestors is None else ancestors
        check(index not in ancestors, "glTF node hierarchy cycle")
        matrix = local_matrix(doc["nodes"][index])
        if index in parents:
            matrix = multiply(world(parents[index], ancestors | {index}), matrix)
        matrices[index] = matrix
        return matrix
    meshes = {}
    for node_index, node in enumerate(doc.get("nodes", [])):
        if "mesh" not in node:
            continue
        matrix = world(node_index)
        normals_matrix, determinant = normal_matrix(matrix)
        for primitive_index, primitive in enumerate(doc["meshes"][node["mesh"]]["primitives"], 1):
            check(primitive.get("mode", 4) == 4, "Only triangle primitives supported")
            attributes = primitive["attributes"]
            raw_positions = glb.accessor(attributes["POSITION"])
            raw_normals = glb.accessor(attributes["NORMAL"], normalized=True)
            raw_uvs = glb.accessor(attributes["TEXCOORD_0"])
            check(len(raw_positions) == len(raw_normals) == len(raw_uvs), "Vertex channel lengths differ")
            flat = [row[0] for row in glb.accessor(primitive["indices"])] if "indices" in primitive else list(range(len(raw_positions)))
            check(len(flat) % 3 == 0 and flat, "Triangle indices required")
            check(all(isinstance(v, int) and 0 <= v < len(raw_positions) for v in flat), "Invalid glTF vertex index")
            used = sorted(set(flat))
            remap = {value: index+1 for index, value in enumerate(used)}
            positions = [position(matrix, raw_positions[index]) for index in used]
            normals = [normal(normals_matrix, raw_normals[index]) for index in used]
            uvs = [[clean(raw_uvs[index][0]), clean(1-raw_uvs[index][1])] for index in used]
            triangles = [[remap[v] for v in flat[index:index+3]] for index in range(0,len(flat),3)]
            if determinant < 0:
                triangles = [[a,c,b] for a,b,c in triangles]
            low = [min(p[axis] for p in positions) for axis in range(3)]
            high = [max(p[axis] for p in positions) for axis in range(3)]
            center = [clean((low[axis]+high[axis])/2) for axis in range(3)]
            size = [clean(max(high[axis]-low[axis],0.001)) for axis in range(3)]
            mesh_key = f"{key}/{node['name']}/{primitive_index}"
            check(mesh_key not in meshes, "Duplicate stable mesh key")
            texture, color, material, material_name = material_info(glb, primitive, registry, png_hashes)
            entry = {"name": node["name"], "assetKey": key, "sourceName": node["name"],
                     "positions": positions, "normals": normals, "uvs": uvs,
                     "triangles": triangles, "center": center, "size": size,
                     "textureId": texture, "color": color, "material": material,
                     "materialName": material_name, "doubleSided": True,
                     "trianglesCount": len(triangles)}
            if kind == "warden":
                entry["section"] = re.sub(r"\.\d{3}$", "", node.get("extras", {}).get("section_name", node["name"]))
            meshes[mesh_key] = entry
    check(meshes, f"Empty asset {key}")
    return meshes, {"source": path.relative_to(ROOT).as_posix(), "source_sha256": sha(glb.raw),
                    "mesh_count": len(meshes), "triangles": sum(m["trianglesCount"] for m in meshes.values())}


def source_modules(directory, data):
    raw = compact(data)
    text = raw.decode("utf-8")
    equals = "=="
    while f"]{equals}]" in text:
        equals += "="
    prefix = (HEADER + f"return [{equals}[").encode()
    suffix = f"]{equals}]\n".encode()
    budget = MAX_SOURCE_BYTES-len(prefix)-len(suffix)
    outputs, names, pieces = {}, [], []
    for offset in range(0,len(raw),budget):
        piece = raw[offset:offset+budget]
        name = f"Chunk{len(names)+1:02}"
        outputs[directory / f"{name}.luau"] = prefix+piece+suffix
        names.append(name)
        pieces.append(piece)
    check(b"".join(pieces) == raw, "Chunk reconstruction changed catalog JSON")
    quoted = ", ".join(json.dumps(name) for name in names)
    loop = f"for _, name in {{ {quoted} }} do\n"
    if len(loop.rstrip()) > 100:
        loop = "for _, name in\n\t{\n" + "".join(f'\t\t"{name}",\n' for name in names) + "\t}\ndo\n"
    init = (HEADER + "local chunks = {}\n" + loop
            + "\ttable.insert(chunks, require(script:WaitForChild(name)))\nend\n"
            + 'return game:GetService("HttpService"):JSONDecode(table.concat(chunks))\n').encode()
    outputs[directory / "init.luau"] = init
    return outputs, {"raw_bytes": len(raw), "raw_sha256": sha(raw), "chunks": len(names)}


def main():
    spec = importlib.util.spec_from_file_location("harvest_binary_auditor", ROOT / "scripts/blender/verify_harvest_pack.py")
    auditor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(auditor)
    registry_raw = (PACK / "roblox-textures.json").read_bytes()
    registry = json.loads(registry_raw)["textures"]
    check(len(registry) == 5 and all(re.fullmatch(r"rbxassetid://[1-9][0-9]*", uri) for uri in registry.values()), "Exact uploaded texture registry required")
    png_hashes = {sha((PACK / "textures" / f"{name}.png").read_bytes()): name for name in registry}
    catalog = {"version": 1, "owner": OWNER, "textures": registry, "assets": {}, "meshes": {}}
    manifest = {"version": 1, "owner": OWNER, "registry_sha256": sha(registry_raw), "assets": {}, "sources": {}}
    outputs = {}
    for key, (kind, path) in sources().items():
        meshes, audit = extract(key,kind,path,auditor.GLB,registry,png_hashes)
        catalog["assets"][key] = {"kind": kind, "meshes": list(meshes)}
        catalog["meshes"].update(meshes)
        generated, chunks = source_modules(OUT / key, {"meshes": meshes})
        outputs.update(generated)
        manifest["assets"][key] = {**audit, **chunks}
    metadata = {key:value for key,value in catalog.items() if key != "meshes"}
    generated, _ = source_modules(OUT,metadata)
    outputs.update(generated)
    check(len(catalog["assets"]) == 25, "Expected twelve corn, two warden, eleven environment assets")
    for path, raw in outputs.items():
        check(path.resolve().is_relative_to(OUT.resolve()), "Generated data escaped its owned root")
        check(len(raw) <= MAX_SOURCE_BYTES, "ModuleScript exceeded source limit")
    expected = set(outputs)
    existing = set(OUT.rglob("*.luau")) if OUT.exists() else set()
    # Never delete unknown files or replace authored source without exact previous hash.
    old_manifest_path = PACK / "catalog-manifest.json"
    old_sources = json.loads(old_manifest_path.read_bytes()).get("sources", {}) if old_manifest_path.exists() else {}
    check(not (existing-expected), "Unknown or stale generated files preserved; inspect before rebuilding")
    for path in existing:
        relative = path.relative_to(ROOT).as_posix()
        before = path.read_bytes().replace(b"\r\n",b"\n")
        check(before == outputs[path] or sha(path.read_bytes()) == old_sources.get(relative,{}).get("sha256"), f"Unknown manual data edits preserved: {relative}")
    for path, raw in outputs.items():
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(raw)
        manifest["sources"][path.relative_to(ROOT).as_posix()] = {"bytes":len(raw),"sha256":sha(raw)}
    catalog_raw = compact(catalog)+b"\n"
    (PACK / "roblox-catalog.json").write_bytes(catalog_raw)
    manifest["catalog"] = {"bytes":len(catalog_raw),"sha256":sha(catalog_raw),"assets":len(catalog["assets"]),"meshes":len(catalog["meshes"]),"triangles":sum(m["trianglesCount"] for m in catalog["meshes"].values())}
    (PACK / "catalog-manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    print(json.dumps({"ok":True,**manifest["catalog"],"source_modules":len(outputs),"largest_source":max(map(len,outputs.values()))}))


if __name__ == "__main__":
    main()
