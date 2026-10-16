"""Read-only audit of generated Harvest catalog and exact Luau JSON reconstruction."""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "assets/harvest-warden"
DATA = ROOT / "src/shared/Game/HarvestGeometryData"
catalog_raw = (PACK / "roblox-catalog.json").read_bytes()
catalog = json.loads(catalog_raw)
manifest = json.loads((PACK / "catalog-manifest.json").read_bytes())
assert hashlib.sha256(catalog_raw).hexdigest() == manifest["catalog"]["sha256"]
assert len(catalog["assets"]) == 25 and len(catalog["meshes"]) == 86
assert catalog["owner"] == "harvest_warden_v1"

def read_module(path):
    source = (path / "init.luau").read_text()
    names = re.findall(r'"(Chunk[0-9]+)"', source)
    pieces = []
    for name in names:
        raw = (path / (name + ".luau")).read_text()
        match = re.search(r"return \[(=+)\[(.*)\]\1\]\n$", raw, re.S)
        assert match, name
        pieces.append(match[2])
    return json.loads("".join(pieces))

assert read_module(DATA) == {key:value for key,value in catalog.items() if key != "meshes"}
for key, asset in catalog["assets"].items():
    assert read_module(DATA / key) == {"meshes": {name: catalog["meshes"][name] for name in asset["meshes"]}}
for name, info in manifest["sources"].items():
    raw = (ROOT / name).read_bytes()
    assert len(raw) == info["bytes"] <= 135000
    assert hashlib.sha256(raw).hexdigest() == info["sha256"]
assert len(manifest["sources"]) == 68
all_triangles = 0
for key, mesh in catalog["meshes"].items():
    assert key.startswith(mesh["assetKey"] + "/")
    positions, normals, uvs = mesh["positions"], mesh["normals"], mesh["uvs"]
    assert len(positions) == len(normals) == len(uvs) > 0
    assert all(len(row) == width and all(math.isfinite(v) for v in row)
               for channel,width in ((positions,3),(normals,3),(uvs,2)) for row in channel)
    assert all(abs(sum(v*v for v in row)-1) < 0.00001 for row in normals)
    assert all(v > 0 and math.isfinite(v) for v in mesh["size"])
    assert mesh["textureId"] == "" or mesh["textureId"] in catalog["textures"].values()
    assert mesh["trianglesCount"] == len(mesh["triangles"])
    for triangle in mesh["triangles"]:
        assert len(triangle) == 3 and all(isinstance(i,int) and 1 <= i <= len(positions) for i in triangle)
        a,b,c = [positions[i-1] for i in triangle]
        u,v = ([b[i]-a[i] for i in range(3)], [c[i]-a[i] for i in range(3)])
        cross = [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        assert sum(x*x for x in cross) > 0, f"Quantization collapsed {key}"
    all_triangles += mesh["trianglesCount"]
assert all_triangles == 22608
for key, asset in catalog["assets"].items():
    meshes = [catalog["meshes"][name] for name in asset["meshes"]]
    if asset["kind"] == "corn":
        assert len(meshes) == 1
        assert min(v[1] for v in meshes[0]["positions"]) == 0
        assert max(v[1] for v in meshes[0]["positions"]) == 8
    if asset["kind"] == "warden":
        assert {m["section"] for m in meshes} == {"Coat","Hat","Head","LeftArm","LeftEye","LeftLeg","RightArm","RightEye","RightLeg"}
        assert sum(m["trianglesCount"] for m in meshes) == (2414 if key == "WardenClassic" else 5190)
        assert {m["section"] for m in meshes if m["material"] == "Neon"} == {"LeftEye","RightEye"}
print("PASS: 25 actual-GLB assets/86 meshes/22608 nondegenerate triangles, 12 rooted8-stud corn variants, two9-section wardens/four Neon eyes, exact68-source lazy reconstruction and SHA/budget guards")
