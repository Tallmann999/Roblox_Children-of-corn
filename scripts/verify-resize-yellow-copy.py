"""Read-only exact engine-save audit of the fixed 630-stud/yellow-corn update.

Retained instances are compared by their immutable UniqueId, parent identity,
class and real Name. Exporter sibling suffixes may change after approved plant
deletions; they are never accepted as authority for world movement or identity.
No Roblox scene is reconstructed or written.
"""
import argparse
import collections
import importlib.util
import json
import math
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-resize-yellow-20261015.rbxl"
BASELINE_HASH = "c7015e55a7cf4a020fe0ae1e3d40d4c69c17faf10a8f01d8ce4379066c955fed"
BASELINE_BYTES = 1028519
BASELINE_INSTANCES = 6844
MANIFEST = ROOT / "scripts/resize-layout.json"
MANIFEST_HASH = "aca4b7d116db835eaa638820d4c340b4cfdb3426826b7035fe0b4fae2a0b9f05"
PLANT_ROOTS = ("Workspace/CornMap/EditorPreview/", "Workspace/CornMap/EditorFieldOverview/")
spec = importlib.util.spec_from_file_location("resize_source_helpers", ROOT / "scripts/verify-readability-copy.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
spec = importlib.util.spec_from_file_location("resize_fog_helpers", ROOT / "scripts/build-haze-installer.py")
fog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fog)
require, sha256 = r.require, r.sha256
FLOAT32_TYPES = {"float", "X", "Y", "Z", "R", "G", "B"} | {"R" + str(i) + str(j) for i in range(3) for j in range(3)}
FRAME_KEYS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")


def validate_camera_frame(value):
    require(value[0] == "CoordinateFrame" and len(value[2]) == 12, "Malformed editor camera frame")
    fields = set()
    for key, child in value[2]:
        require(key in FRAME_KEYS and key not in fields and child[0] == key and not child[2], "Malformed editor camera component")
        number = float(child[1])
        require(math.isfinite(number) and abs(number) <= 3.4028234663852886e38, "Nonfinite/overflow editor camera frame")
        fields.add(key)


def numeric(value):
    """Canonical f32 round-trips only for declared numeric XML leaves."""
    value = r.normalized(value)
    if value[0] in FLOAT32_TYPES and not value[2]:
        number = float(value[1])
        require(math.isfinite(number) and abs(number) <= 3.4028234663852886e38, "Nonfinite/overflow world value")
        return [value[0], struct.pack("<f", number).hex(), []]
    return [value[0], value[1], [[tag, numeric(child)] for tag, child in value[2]]]


def identity(node):
    value = node["properties"].get("UniqueId")
    require(value is not None and value[0] == "UniqueId" and value[2] == [] and re.fullmatch(r"[0-9a-fA-F]{32}", value[1]) and int(value[1], 16) != 0, "Missing/malformed original instance identity")
    return value[1].lower()


def layout():
    require(sha256(MANIFEST) == MANIFEST_HASH, "Fixed resize manifest changed")
    data = r.load_json(MANIFEST)
    require(data["version"] == 1 and data["baseline"] == {
        "path": "place/Children_of_corn.before-resize-yellow-20261015.rbxl",
        "bytes": BASELINE_BYTES, "sha256": BASELINE_HASH,
    }, "Unrecognized immutable resize baseline")
    require(data["field_side_before"] == 840 and data["field_side_after"] == 630, "Unrecognized resize dimensions")
    return data


def fixed_changes(before, manifest):
    changes = {}
    parents = {path.rpartition("/")[0] for path in before}
    for entry in manifest["property_changes"]:
        path, prop = entry["path"], entry["property"]
        require(path == "Workspace/CornMap" or path.startswith("Workspace/CornMap/"), "Manifest target outside authorized CornMap")
        require(path in before and entry["uid"].lower() == identity(before[path]), "Manifest target identity differs: " + path)
        require(entry["class"] == before[path]["class"], "Manifest class differs: " + path)
        require(prop in before[path]["properties"] and prop not in {"Source", "UniqueId", "Name", "ScriptGuid", "HistoryId", "Capabilities", "DefinesCapabilities"}, "Forbidden manifest property: " + path + "/" + prop)
        require((path, prop) not in changes, "Duplicate manifest property target")
        if prop == "TextureContent":
            require(path.startswith(PLANT_ROOTS) and before[path]["class"] == "MeshPart", "Texture target outside owned editor corn")
        require(numeric(entry["before"]) == numeric(before[path]["properties"][prop]), "Immutable property differs from fixed manifest: " + path + "/" + prop)
        require(numeric(entry["before"]) != numeric(entry["after"]), "Manifest contains a no-op property")
        changes[(path, prop)] = entry
    deleted = {}
    changed_paths = {path for path, _ in changes}
    for entry in manifest["removed_plants"]:
        path = entry["path"]
        require(path in before and path.startswith(PLANT_ROOTS), "Removed plant outside fixed editor corn")
        require(entry["uid"].lower() == identity(before[path]) and entry["class"] == before[path]["class"] == "MeshPart", "Removed plant identity/class differs")
        require(set(entry) == {"path", "uid", "class"}, "Unexpected removed-plant schema")
        require(path not in parents, "Removed plant unexpectedly contains children")
        require(path not in deleted and path not in changed_paths, "Duplicate/modified removed plant")
        deleted[path] = entry
    require(bool(changes) and bool(deleted), "Expected fixed world changes and owned plant removals")
    return changes, deleted


def remap_refs(value, paths):
    text = paths.get(value[1], value[1]) if value[0] == "Ref" else value[1]
    children = [[tag, remap_refs(child, paths)] for tag, child in value[2]]
    if text == value[1] and all(mapped[1] is original[1] for mapped, original in zip(children, value[2])):
        return value
    return [value[0], text, children]


def canonicalize(before, after, deleted):
    before_ids = {identity(node): path for path, node in before.items()}
    require(len(before_ids) == len(before), "Duplicate immutable identity")
    expected = set(before) - set(deleted)
    paths, seen_ids, seen_targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in seen_ids, "Duplicate candidate identity")
        seen_ids.add(uid)
        target = before_ids.get(uid)
        # Studio may rewrite the four root FilteredSelection identity tokens.
        # This narrow pre-existing editor metadata exception never covers art.
        if target is None:
            require(path in r.SELECTION_PATHS and node["class"] == "Instance" and node["properties"].get("Name") == ["string", "FilteredSelection", []], "New/replaced instance identity: " + path)
            target = path
        require(target in expected, "Forbidden retained removed plant or unexpected identity: " + path)
        require(target not in seen_targets, "Duplicate canonical original target")
        seen_targets.add(target)
        paths[path] = target
    require(set(paths.values()) == expected, "Missing original retained instances: " + str(sorted(expected - set(paths.values()))[:8]))
    result = {}
    for path, target in paths.items():
        old, actual = before[target], after[path]
        require(old["class"] == actual["class"], "Original class changed: " + target)
        require(old["properties"]["Name"] == actual["properties"].get("Name"), "Original real Name changed: " + target)
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or (actual_parent in paths and paths[actual_parent] == parent), "Original parent identity changed: " + target)
        result[target] = actual | {"properties": {prop: remap_refs(value, paths) for prop, value in actual["properties"].items()}}
    return result, sum(path != target for path, target in paths.items())


def validate_dom(before, after, sources, classes, asset_sources):
    require(len(before) == BASELINE_INSTANCES, "Expected immutable 6844-instance baseline")
    manifest = layout()
    fixed, deleted = fixed_changes(before, manifest)
    require(len(after) == len(before) - len(deleted), "Unexpected candidate instance count")
    after, reindexed = canonicalize(before, after, deleted)
    all_sources = sources | asset_sources
    require(len(sources) == 75 and len(asset_sources) == 3 and len(all_sources) == 78, "Expected 75 code and three fog Sources")
    require(set(all_sources) == {path for path, node in after.items() if "Source" in node["properties"]}, "Persistent Source set differs")
    require({path for path in after if r.p.owned(path)} == set(classes), "Configured Rojo code topology differs")
    for path, cls in classes.items():
        require(after[path]["class"] == cls, "Configured code class differs: " + path)
    for path, source in all_sources.items():
        value = after[path]["properties"]["Source"]
        require(after[path]["class"] in r.SCRIPT_CLASSES and value[0] == "string" and not value[2] and value[1].replace("\r\n", "\n") == source, "Source mismatch: " + path)
    applied, changes = set(), []
    for path, old in before.items():
        if path in deleted:
            continue
        actual = after[path]
        require(set(old["properties"]) == set(actual["properties"]), "Original property set changed: " + path)
        for prop, value in old["properties"].items():
            other = actual["properties"][prop]
            entry = fixed.get((path, prop))
            if entry is not None:
                require(numeric(other) == numeric(entry["after"]), "Incomplete/unapproved resize property: " + path + "/" + prop)
                applied.add((path, prop))
                changes.append({"path": path, "uid": entry["uid"], "property": prop, "reason": "fixed_resize_yellow_manifest"})
                continue
            if other == value or r.normalized(other) == r.normalized(value):
                continue
            camera = path == "Workspace/Camera" and prop in {"CFrame", "Focus"}
            allowed = ((path in all_sources and prop == "Source") or camera or
                       (path in r.SELECTION_PATHS and old["class"] == "Instance" and prop == "UniqueId"))
            require(allowed, "Unapproved original property changed: " + path + "/" + prop)
            if camera:
                validate_camera_frame(other)
            changes.append({"path": path, "property": prop, "reason": "source" if prop == "Source" else "editor_metadata"})
    require(applied == set(fixed), "Incomplete fixed world update")
    return {"matching_sources": 75, "matching_asset_sources": 3, "total_sources": 78,
        "new_instances": 0, "deleted_owned_plants": len(deleted), "retained_instances": len(after),
        "fixed_property_changes": len(fixed), "reindexed_exporter_paths": reindexed,
        "field_side": 630, "world_and_lighting_exact": False,
        "unapproved_world_lighting_art_identities_exact": True, "original_source_art_preserved": True,
        "allowed_changes": changes, "approved_deleted_plants": [{"path": path, "uid": row["uid"]} for path, row in deleted.items()]}


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = sha256(original), sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Immutable before-resize-yellow baseline changed")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "Candidate must be exact engine-saved RBXL")
    sources, classes = r.mapping_from_sourcemap(ROOT / "build/sourcemap.json")
    asset_sources = fog.current_sources()
    before, warning_before = r.p.known_dom(original)
    after, warning_after = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    result = validate_dom(before, after, sources, classes, asset_sources)
    meta = r.p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "CornMap ownership/corner guards invalid")
    require(sha256(original) == old_hash and sha256(candidate) == new_hash, "Input scene changed during read-only audit")
    require(r.mapping_from_sourcemap(ROOT / "build/sourcemap.json") == (sources, classes) and fog.current_sources() == asset_sources, "Source/build/assets changed during audit")
    require(sha256(MANIFEST) == MANIFEST_HASH, "Fixed layout changed during audit")
    return result | {"passed": True, "original_sha256": old_hash, "candidate_sha256": new_hash,
        "original_instances": len(before), "candidate_instances": len(after), "bytes": candidate.stat().st_size,
        "layout_sha256": MANIFEST_HASH, "raw_unknown_properties": unknown_after,
        "warnings": {"original": warning_before, "candidate": warning_after},
        "scope": "Read-only exact engine bytes. Existing 78 Sources match declared src/assets. Only fixed manifest world properties and removed owned editor plants, Sources and narrow editor metadata differ. Retained identities/classes/names/parents, unapproved world/art/Lighting and raw Terrain are exact. No new instances/service metadata exceptions or scene reconstruction."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report_path = args.report.resolve()
    require(report_path.suffix.lower() == ".json" and any(report_path.is_relative_to((ROOT / folder).resolve()) for folder in ("build", ".artifacts")), "Report must remain in owned artifact/build directory")
    report = check(args.original, args.candidate)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key not in {"allowed_changes", "approved_deleted_plants", "warnings", "raw_unknown_properties"}}))
