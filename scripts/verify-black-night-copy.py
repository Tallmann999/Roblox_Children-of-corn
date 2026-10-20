"""Strict read-only engine-save audit of variant A black-night/white-eye Sources.

The five exact childless Lighting deletions and Brightness 1->0 predate this code
update in the author's open scene. They are explicit pre-existing author edits,
not changes installed by the Source-only installer. All retained identities,
classes, names, parents, world/art, other properties and raw Terrain stay exact.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("black_night_builder", ROOT / "scripts/build-black-night-installer.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
spec = importlib.util.spec_from_file_location("black_night_save_helpers", ROOT / "scripts/verify-rustle-comparison-copy.py")
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
r, fog = old.r, old.fog
require, sha256 = r.require, r.sha256
BASELINE = builder.BASELINE
BASELINE_HASH, BASELINE_BYTES = builder.BASELINE_SHA, builder.BASELINE_BYTES
AUTHOR_REMOVALS = {"Lighting/Sky": "Sky", "Lighting/SunRays": "SunRaysEffect",
    "Lighting/Atmosphere": "Atmosphere", "Lighting/Bloom": "BloomEffect",
    "Lighting/DepthOfField": "DepthOfFieldEffect"}
DECLARED_SOURCES = builder.ALLOWED_CHANGED
MESH_CACHE_REVIEW = builder.OUT / "mesh-vertex-cache-review.json"
MESH_CACHE_REVIEW_HASH = "a03d0322f509bc9a693456b07e45f4e107656931dceb2c1b5b78a4aa2d0040fb"
CATALOG = ROOT / "assets/harvest-warden/roblox-catalog.json"
CATALOG_HASH = "b9448ca01dd10b4579d44ba4efad427edd7e4f7ced466fb68144d5f22651dbd0"


def vertex_cache_contract(before):
    """Exact read-only counter contract independently reviewed against live meshes.

    The accepted file saved Content.Object as null and VertexCount=0. Rebuilding
    fixed EditableMesh objects before this engine Save populated only this hidden
    counter. Its 242 approved values are independently derived from unchanged
    immutable mesh-key attributes and pinned catalog vertex/triangle arrays.
    """
    require(sha256(MESH_CACHE_REVIEW) == MESH_CACHE_REVIEW_HASH, "Independent mesh counter review changed")
    require(sha256(CATALOG) == CATALOG_HASH, "Pinned geometry catalog changed")
    review, catalog = r.load_json(MESH_CACHE_REVIEW), r.load_json(CATALOG)
    require(review["passed"] is True and review["catalog_sha256"] == CATALOG_HASH
            and review["count"] == len(review["rows"]) == 242, "Unrecognized mesh counter review")
    marker = struct.pack("<I", len(b"HarvestMeshKey")) + b"HarvestMeshKey" + b"\x02"
    contract = {}
    for row in review["rows"]:
        require(set(row) == {"path", "meshKey", "before", "after", "nativeFaces"}, "Mesh counter review row schema differs")
        path = row["path"]
        require(path not in contract and path in before and before[path]["class"] == "MeshPart"
                and (path.startswith("Workspace/CornMap/HarvestDecor/") or path.startswith("Workspace/CornMap/Props/ScarecrowMarker/HarvestWardenHome/")),
                "Mesh counter outside exact owned paths")
        props = before[path]["properties"]
        require(props["VertexCount"] == ["int", "0", []] and row["before"] == 0, "Mesh counter immutable baseline differs")
        data = bytes.fromhex(props["AttributesSerialize"][1])
        require(data.count(marker) == 1, "Immutable mesh-key attribute absent/ambiguous")
        offset = data.index(marker) + len(marker)
        length = struct.unpack_from("<I", data, offset)[0]
        require(0 < length <= 512 and offset + 4 + length <= len(data), "Malformed immutable mesh-key string")
        key = data[offset + 4:offset + 4 + length].decode("utf-8")
        require(key == row["meshKey"] and key in catalog["meshes"], "Immutable mesh key differs from reviewed catalog binding")
        mesh = catalog["meshes"][key]
        require(type(row["after"]) is int and row["after"] == len(mesh["positions"]) > 0
                and type(row["nativeFaces"]) is int and row["nativeFaces"] == len(mesh["triangles"]), "Reviewed counter does not match catalog arrays")
        contract[path] = row
    return contract


def validate_vertex_cache(path, before, after, contract):
    require(path in contract and before == ["int", "0", []]
            and after == ["int", str(contract[path]["after"]), []], "Mesh VertexCount differs from exact independently reviewed 0 -> catalog count: " + path)


def validate_dom(before, after, sources, classes, asset_sources):
    require(len(before) == 4526 and len(after) == 4521, "Expected exact 4526 -> 4521 author Lighting deletion set")
    require(set(AUTHOR_REMOVALS).issubset(before), "Author pre-existing Lighting nodes missing from immutable baseline")
    for path, cls in AUTHOR_REMOVALS.items():
        require(before[path]["class"] == cls and not any(other.startswith(path + "/") for other in before),
                "Author deletion must refer to exact known childless Lighting object: " + path)
    after, reindexed = old.helpers.canonicalize(before, after, AUTHOR_REMOVALS)
    all_sources = sources | asset_sources
    require(len(sources) == 150 and len(asset_sources) == 3 and len(all_sources) == 153, "Expected 150 project + three unchanged Fog Sources")
    require(set(all_sources) == {path for path, node in after.items() if "Source" in node["properties"]}, "Persistent Source set differs")
    require({path for path in after if r.p.owned(path)} == set(classes), "Configured code topology differs")
    accepted = {row["path"]: row for row in builder.accepted_payload()["entries"]}
    for path, cls in classes.items():
        require(after[path]["class"] == cls, "Configured class differs: " + path)
    for path, source in all_sources.items():
        value = after[path]["properties"]["Source"]
        require(after[path]["class"] == accepted[path]["class"] and value[0] == "string" and not value[2]
                and value[1].replace("\r\n", "\n") == source, "Source mismatch: " + path)
        original = before[path]["properties"]["Source"]
        require(original[0] == "string" and not original[2] and hashlib.sha256(original[1].replace("\r\n", "\n").encode()).hexdigest() == accepted[path]["after"],
                "Accepted Source baseline differs: " + path)
    counter_contract = vertex_cache_contract(before)
    changes, changed_sources, counters = [], [], []
    for path, node in before.items():
        if path in AUTHOR_REMOVALS:
            continue
        actual = after[path]
        require(set(node["properties"]) == set(actual["properties"]), "Retained property set changed: " + path)
        for prop, value in node["properties"].items():
            other = actual["properties"][prop]
            if prop == "Source":
                require(value[0] == other[0] == "string" and not value[2] and not other[2], "Malformed Source")
                if value[1].replace("\r\n", "\n") == other[1].replace("\r\n", "\n"):
                    continue
                require(path in DECLARED_SOURCES, "Source outside two declared updates: " + path)
                changed_sources.append(path)
                changes.append({"path": path, "property": prop, "reason": "black_night_white_eye_source"})
                continue
            if other == value or r.normalized(other) == r.normalized(value):
                continue
            camera = path == "Workspace/Camera" and prop in {"CFrame", "Focus"}
            selection = path in r.SELECTION_PATHS and node["class"] == "Instance" and prop == "UniqueId"
            author_brightness = path == "Lighting" and prop == "Brightness"
            mesh_counter = path in counter_contract and prop == "VertexCount"
            require(camera or selection or author_brightness or mesh_counter, "Retained world/art/Lighting changed: " + path + "/" + prop)
            if mesh_counter:
                validate_vertex_cache(path, value, other, counter_contract)
                counters.append(path)
            if camera:
                old.validate_camera_frame(other)
            if author_brightness:
                require(value == ["float", "1", []] and other == ["float", "0", []], "Author Brightness edit must be exactly 1 -> 0")
            changes.append({"path": path, "property": prop, "reason": "exact_rebuilt_mesh_vertex_counter" if mesh_counter else "author_preexisting_brightness" if author_brightness else "editor_metadata"})
    require(set(changed_sources) == DECLARED_SOURCES, "Expected both and only two declared Source changes")
    require(after["Lighting"]["properties"]["Brightness"] == ["float", "0", []], "Pre-existing author Brightness=0 was not preserved")
    return {"passed": True, "complete": True, "variant": "A", "matching_sources": 150,
        "matching_asset_sources": 3, "total_sources": 153, "source_changes": sorted(changed_sources),
        "new_instances": 0, "removed_instances": 5, "author_preexisting_removed_lighting": sorted(AUTHOR_REMOVALS),
        "author_preexisting_brightness": {"before": 1, "after": 0}, "allowed_changes": changes,
        "rebuilt_mesh_vertex_counters": len(counters), "mesh_vertex_cache_review_sha256": MESH_CACHE_REVIEW_HASH,
        "geometry_catalog_sha256": CATALOG_HASH,
        "reindexed_exporter_paths": reindexed, "retained_identities_classes_names_parents_exact": True,
        "world_art_exact": True, "lighting_exact_except_explicit_author_preexisting_edits": True}


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    original_hash, candidate_hash = sha256(original), sha256(candidate)
    require(original == BASELINE.resolve() and original.stat().st_size == BASELINE_BYTES and original_hash == BASELINE_HASH,
            "Immutable accepted pre-night A baseline differs")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl" and candidate != original, "Candidate must be a separate engine-saved RBXL")
    _, sources, classes, _ = builder.mapping()
    require(sha256(MESH_CACHE_REVIEW) == MESH_CACHE_REVIEW_HASH and sha256(CATALOG) == CATALOG_HASH, "Independent geometry inputs changed")
    assets = fog.current_sources()
    before, warning_before = r.p.known_dom(original)
    after, warning_after = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    report = validate_dom(before, after, sources, classes, assets)
    meta = r.p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "Corn ownership/corners differ")
    require(sha256(original) == original_hash and sha256(candidate) == candidate_hash, "Scene changed during read-only audit")
    require(builder.mapping()[1:3] == (sources, classes) and fog.current_sources() == assets, "Code/build/assets changed during audit")
    require(sha256(MESH_CACHE_REVIEW) == MESH_CACHE_REVIEW_HASH and sha256(CATALOG) == CATALOG_HASH, "Independent geometry inputs changed during audit")
    return report | {"original_sha256": original_hash, "candidate_sha256": candidate_hash,
        "original_instances": len(before), "candidate_instances": len(after), "bytes": candidate.stat().st_size,
        "raw_terrain_exact": True, "raw_unknown_properties": unknown_after,
        "warnings": {"original": warning_before, "candidate": warning_after},
        "scope": "Exact engine bytes: two existing Sources; five childless Lighting deletions and Brightness 1->0 already authored before installation; only independently reviewed owned MeshPart VertexCount 0->exact pinned catalog vertex count after rebuilding fixed geometry. All other retained world/art/Lighting properties, identities/classes/names/parents/raw Terrain exact. No scene serialization or publishing."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report_path = args.report.resolve()
    require(report_path.suffix.lower() == ".json" and any(report_path.is_relative_to((ROOT / folder).resolve()) for folder in ("build", ".artifacts")), "Report must remain in owned artifact/build directory")
    require(report_path not in {args.original.resolve(), args.candidate.resolve()}, "Report would overwrite scene")
    report = check(args.original, args.candidate)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({key: value for key, value in report.items() if key not in {"allowed_changes", "warnings", "raw_unknown_properties"}}))
