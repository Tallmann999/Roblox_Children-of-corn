"""Independently compare generated Luau mesh channels with the neutral FBX intake."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "scene-c/data"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    manifest = json.loads((DATA / "manifest.json").read_text(encoding="utf-8"))
    intake_path = ROOT / manifest["intake"]
    assert sha(intake_path) == manifest["intake_sha256"]
    assert sha(ROOT / manifest["geometry_module"]) == manifest["geometry_module_sha256"]
    intake = {a["name"]: a for a in json.loads(intake_path.read_text(encoding="utf-8"))["assets"]}
    checks = 2
    modules = []
    for entry in manifest["assets"]:
        original = intake[entry["name"]]
        assert sha(Path(entry["source"])) == entry["source_sha256"] == original["source_sha256"]
        checks += 1
        if entry["key"] == "Corn":
            assert entry["triangles"] == 510 and math.isclose(entry["size_studs"][1], 8, abs_tol=1e-12)
            checks += 2
            continue
        module = ROOT / entry["module"]
        body = module.read_bytes()
        assert len(body) == entry["module_bytes"] < 200_000
        assert sha(module) == entry["module_sha256"]
        payload = body.decode("utf-8").split("[==[", 1)[1].split("]==]", 1)[0]
        assert hashlib.sha256(payload.encode("utf-8")).hexdigest() == entry["json_sha256"]
        data = json.loads(payload)
        scale = manifest["uniform_studs_per_metre"]
        center = data["source_center_studs"]
        assert len(data["positions"]) == len(original["vertices"])
        assert len(data["triangles"]) == len(original["triangles"])
        checks += 5
        for baked, source in zip(data["positions"], original["vertices"]):
            inverse = [(baked[0] + center[0]) / scale, -(baked[2] + center[2]) / scale, (baked[1] + center[1]) / scale]
            assert all(math.isclose(a, b, rel_tol=0, abs_tol=1e-12) for a, b in zip(inverse, source))
            checks += 3
        for index, source in enumerate(original["triangles"]):
            assert data["triangles"][index] == [i + 1 for i in source["vertices"]]
            checks += 1
            for corner in range(3):
                uv = data["uvs"][data["triangle_uvs"][index][corner] - 1]
                normal = data["normals"][data["triangle_normals"][index][corner] - 1]
                expected_uv = source["uv"][corner]
                expected_normal = source["normals"][corner]
                assert uv == [expected_uv[0], 1 - expected_uv[1]]
                assert normal == [expected_normal[0], expected_normal[2], -expected_normal[1]]
                checks += 5
        assert len(data["uvs"]) == len(set(map(tuple, data["uvs"])))
        assert len(data["normals"]) == len(set(map(tuple, data["normals"])))
        checks += 2
        modules.append({"key": entry["key"], "bytes": len(body), "triangles": len(data["triangles"]), "sha256": sha(module)})
    print(json.dumps({"pass": True, "channel_checks": checks, "scope": "exact source hashes, preserved vertices, winding, original corner normals/palette UVs; centered right-handed uniform transform", "modules": modules}, separators=(",", ":")))


if __name__ == "__main__":
    main()
