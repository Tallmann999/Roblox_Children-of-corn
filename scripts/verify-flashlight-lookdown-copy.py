"""Read-only strict audit of one A LightingStyle property; all Sources unchanged.

All 4527 identities/classes/names/parents/world/Lighting/art/mesh counters/raw
Terrain remain exact. Only LightingStyle.Soft to Realistic plus two independently captured preexisting author nodes.
"""
from __future__ import annotations
import argparse
import copy
import struct
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("flashlight_directional_builder", ROOT / "scripts/build-flashlight-lookdown-installer.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
spec = importlib.util.spec_from_file_location("flashlight_directional_save_helpers", ROOT / "scripts/verify-flashlight-copy.py")
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
r, fog = old.r, old.fog
require, sha256 = r.require, r.sha256
identity, remap_refs = old.identity, old.remap_refs
BASELINE, BASELINE_HASH, BASELINE_BYTES = builder.BASELINE, builder.BASELINE_SHA, builder.BASELINE_BYTES
DECLARED_SOURCES = builder.ALLOWED_CHANGED


AUTHOR_SNAPSHOT = builder.OUT / "author-part-before-save.json"
AUTHOR_SNAPSHOT_SHA = "e76c1b34bec0d307f4e0d80a93915a2edd1f8d7762ebcbca41b49bf2cedba385"
AUTHOR_PATHS = {"Workspace/Part": "Part", "Workspace/Part/SpotLight": "SpotLight"}


def author_nodes(before):
    require(builder.sha(AUTHOR_SNAPSHOT.read_bytes()) == AUTHOR_SNAPSHOT_SHA, "Pre-save independent author snapshot differs")
    seen = json.loads(AUTHOR_SNAPSHOT.read_bytes())
    result = {}
    for path, key, template in (("Workspace/Part", "part", "Workspace/Baseplate"), ("Workspace/Part/SpotLight", "spot", "ReplicatedStorage/CornFlashlightSettings/Wide")):
        node = copy.deepcopy(before[template]); props = node["properties"]; native = seen[key]
        require(native["className"] == AUTHOR_PATHS[path] and native["path"] == path.replace("/", "."), "Wrong author snapshot path/class")
        props["Name"] = ["string", native["name"], []]
        props["UniqueId"] = ["UniqueId", native["uniqueId"].replace("-", ""), []]
        if key == "part":
            for prop in ("Anchored", "Locked"):
                props[prop] = ["bool", str(native["properties"][prop]).lower(), []]
            rgb = [round(float(x)*255) for x in native["properties"]["Color"].split(",")]
            props["Color3uint8"] = ["Color3uint8", str((rgb[0]<<16)|(rgb[1]<<8)|rgb[2]), []]
            props["formFactorRaw"] = ["token", "1", []]  # Native FormFactor.Brick independently read.
            for prop, values in (("size", native["properties"]["Size"]), ("CFrame", native["properties"]["CFrame.Position"]+","+native["properties"]["CFrame.Rotation"])):
                numbers = [float(x) for x in values.split(",")]
                require(len(numbers) == len(props[prop][2]), "Malformed native vector/frame")
                for (_, value), number in zip(props[prop][2], numbers): value[1] = repr(number)
        else:
            for prop in ("Angle", "Brightness"):
                props[prop] = ["float", str(native["properties"][prop]), []]
        result[path] = node
    return result


def validate_author_nodes(before, after):
    for path, expected in author_nodes(before).items():
        actual = after[path]
        require(actual["class"] == expected["class"] and set(actual["properties"]) == set(expected["properties"]), "Author property set/class differs")
        for prop, value in expected["properties"].items():
            other = actual["properties"][prop]
            if path == "Workspace/Part" and prop in {"CFrame", "size"}:
                require(value[0] == other[0] and [k for k,v in value[2]] == [k for k,v in other[2]], "Author frame/vector structure differs")
                for (name, a), (_, b) in zip(value[2], other[2]):
                    require(a[0] == b[0] == name and not a[2] and not b[2] and struct.pack("<f", float(a[1])) == struct.pack("<f", float(b[1])), "Author native float32 frame/vector differs")
            else:
                require(r.normalized(value) == r.normalized(other), "Author property differs: " + path + "/" + prop)


def canonicalize(before, after):
    before_ids = {identity(node): path for path, node in before.items()}
    require(len(before_ids) == len(before), "Duplicate baseline identity")
    paths, identities, targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in identities, "Duplicate candidate identity")
        identities.add(uid)
        target = before_ids.get(uid)
        if target is None:
            require((path in AUTHOR_PATHS and node["class"] == AUTHOR_PATHS[path] and uid == identity(author_nodes(before)[path])) or path in r.SELECTION_PATHS and node["class"] == "Instance"
                    and node["properties"].get("Name") == ["string", "FilteredSelection", []], "Unexpected/replaced original identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical target")
        paths[path] = target
        targets.add(target)
    require(targets == set(before) | set(AUTHOR_PATHS), "Missing/extra original instances")
    reindexed = sum(path != target for path, target in paths.items())
    canonical = {}
    for path, target in paths.items():
        actual = after[path]
        if target in before:
            original = before[target]
            require(original["class"] == actual["class"] and original["properties"]["Name"] == actual["properties"].get("Name"), "Original class/Name changed: " + target)
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or (actual_parent in paths and paths[actual_parent] == parent), "Original parent identity changed: " + target)
        canonical[target] = actual if not reindexed else actual | {"properties": {prop: remap_refs(value, paths) for prop, value in actual["properties"].items()}}
    return canonical, reindexed


def validate_dom(before, after, sources, classes, asset_sources):
    require(len(before) == 4527 and len(after) == 4529, "Expected4527 originals plus two exact author nodes")
    after, reindexed = canonicalize(before, after)
    validate_author_nodes(before, after)
    all_sources = sources | asset_sources
    require(len(sources) == 153 and len(asset_sources) == 3 and len(all_sources) == 156, "Expected 153 project + three unchanged Fog Sources")
    require(set(all_sources) == {path for path, node in after.items() if "Source" in node["properties"]}, "Persistent Source set differs")
    require({path for path in after if r.p.owned(path)} == set(classes), "Configured code topology differs")
    accepted = {row["path"]: row for row in builder.accepted_payload()["entries"]}
    for path, cls in classes.items():
        require(after[path]["class"] == cls, "Configured class differs: " + path)
    for path, source in all_sources.items():
        value, original = after[path]["properties"]["Source"], before[path]["properties"]["Source"]
        require(after[path]["class"] == accepted[path]["class"] and value[0] == "string" and not value[2]
                and value[1].replace("\r\n", "\n") == source, "Source mismatch: " + path)
        require(original[0] == "string" and not original[2]
                and builder.sha(original[1].replace("\r\n", "\n").encode()) == accepted[path]["after"], "Accepted baseline Source differs")
    changes, changed_sources, lighting_changes = [], [], []
    for path, node in before.items():
        actual = after[path]
        require(set(node["properties"]) == set(actual["properties"]), "Original property set changed: " + path)
        for prop, value in node["properties"].items():
            other = actual["properties"][prop]
            if prop == "Source":
                require(value[0] == other[0] == "string" and not value[2] and not other[2], "Malformed original Source")
                if value[1].replace("\r\n", "\n") == other[1].replace("\r\n", "\n"):
                    continue
                require(path in DECLARED_SOURCES, "Source outside declared look-down Source: " + path)
                changed_sources.append(path)
                changes.append({"path": path, "property": prop, "reason": "declared_flashlight_directional_source"})
                continue
            if value == other or r.normalized(value) == r.normalized(other):
                continue
            if path == "Lighting" and prop == "LightingStyle":
                require(value == ["token", "1", []] and other == ["token", "0", []], "Only Soft to Realistic permitted")
                lighting_changes.append(prop)
                changes.append({"path": path, "property": prop, "reason": "author_approved_realistic_lighting"})
                continue
            camera = path == "Workspace/Camera" and prop in {"CFrame", "Focus"}
            selection = path in r.SELECTION_PATHS and node["class"] == "Instance" and prop == "UniqueId"
            require(camera or selection, "Original world/art/Lighting/metadata changed: " + path + "/" + prop)
            if camera:
                old.old.helpers.validate_camera_frame(other)
            changes.append({"path": path, "property": prop, "reason": "editor_metadata"})
    require(set(changed_sources) == DECLARED_SOURCES, "Only the declared look-down Source change is permitted")
    require(lighting_changes == ["LightingStyle"], "Exactly one approved LightingStyle change required")
    return {"lighting_style": "Realistic", "passed": True, "complete": True, "variant": "A", "matching_sources": 153, "matching_asset_sources": 3,
        "total_sources": 156, "source_changes": sorted(changed_sources), "source_change_count": len(changed_sources),
        "new_instances": 2, "preexisting_author_additions": sorted(AUTHOR_PATHS), "removed_instances": 0, "reindexed_exporter_paths": reindexed,
        "retained_identities_classes_names_parents_exact": True, "world_art_mesh_metadata_exact": True, "lighting_exact_except_approved_style": True,
        "allowed_changes": changes}


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = sha256(original), sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Immutable before-flashlight-lookdown baseline differs")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl" and candidate != original, "Candidate must be a separate engine-saved RBXL")
    _, sources, classes, _ = builder.mapping()
    assets = fog.current_sources()
    before, bwarn = r.p.known_dom(original)
    after, awarn = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    report = validate_dom(before, after, sources, classes, assets)
    meta = r.p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "Corn ownership/corners differ")
    require(sha256(original) == old_hash and sha256(candidate) == new_hash, "Scene changed during read-only audit")
    require(builder.mapping()[1:3] == (sources, classes) and fog.current_sources() == assets, "Code/build/assets changed during audit")
    return report | {"original_sha256": old_hash, "candidate_sha256": new_hash, "original_instances": len(before),
        "candidate_instances": len(after), "bytes": candidate.stat().st_size, "raw_terrain_exact": True,
        "raw_unknown_properties": unknown_after, "warnings": {"original": bwarn, "candidate": awarn},
        "scope": "Exact engine bytes: LightingStyle Soft to Realistic only; all 156 Sources unchanged. All other 4527 original world/art/Lighting/mesh properties, identities/classes/names/parents/raw Terrain exact; narrow finite editor Camera/selection metadata only. Two preexisting author nodes preserved against independent pre-save snapshot/default templates. No scene serialization or publishing."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    output = args.report.resolve()
    require(output.suffix.lower() == ".json" and output.is_relative_to(builder.OUT.resolve()), "Cone report must stay inside its new evidence directory")
    require(output not in {args.original.resolve(), args.candidate.resolve()}, "Report would overwrite input")
    report = check(args.original, args.candidate)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({key: value for key, value in report.items() if key not in {"allowed_changes", "raw_unknown_properties", "warnings"}}))
