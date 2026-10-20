"""Read-only strict flashlight engine-save audit; no world/Lighting exceptions.

Retains all 4521 original identities/classes/names/parents/properties/raw Terrain.
Only explicitly declared existing Sources, two default ModuleScripts at existing
code parents, and twelve-component finite editor Camera frames may differ.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("flashlight_builder", ROOT / "scripts/build-flashlight-installer.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
spec = importlib.util.spec_from_file_location("flashlight_save_helpers", ROOT / "scripts/verify-multiplayer-copy.py")
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
r, fog = old.r, old.fog
require, sha256 = r.require, r.sha256
identity, remap_refs = old.helpers.helpers.identity, old.helpers.helpers.remap_refs
BASELINE, BASELINE_HASH, BASELINE_BYTES = builder.BASELINE, builder.BASELINE_SHA, builder.BASELINE_BYTES
ADDITIONS = builder.ADDITIONS
GUID = re.compile(r"\{[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}")


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
            addition = path in ADDITIONS and node["class"] == "ModuleScript"
            selection = path in r.SELECTION_PATHS and node["class"] == "Instance" and node["properties"].get("Name") == ["string", "FilteredSelection", []]
            require(addition or selection, "Unexpected/replaced instance identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical target")
        paths[path] = target
        targets.add(target)
    require(targets == set(before) | ADDITIONS, "Missing/extra retained or added objects")
    reindexed = sum(path != target for path, target in paths.items())
    canonical = {}
    for path, target in paths.items():
        actual = after[path]
        if target in before:
            require(before[target]["class"] == actual["class"] and before[target]["properties"]["Name"] == actual["properties"]["Name"], "Original class/Name changed: " + target)
        else:
            require(actual["properties"].get("Name") == ["string", target.rsplit("/", 1)[-1], []], "Added ModuleScript Name changed: " + target)
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or (actual_parent in paths and paths[actual_parent] == parent), "Original/added parent identity changed: " + target)
        canonical[target] = actual if not reindexed else actual | {"properties": {prop: remap_refs(value, paths) for prop, value in actual["properties"].items()}}
    return canonical, reindexed


def validate_added_modules(before, after):
    template = before["ServerScriptService/GameServer/Game/RoundAudio"]["properties"]
    guids = {node["properties"]["ScriptGuid"][1].lower() for node in before.values() if "ScriptGuid" in node["properties"]}
    for path in ADDITIONS:
        node, props = after[path], after[path]["properties"]
        require(node["class"] == "ModuleScript" and set(props) == set(template), "Added ModuleScript property/class differs: " + path)
        require(not any(other.startswith(path + "/") for other in after), "New ModuleScript contains children")
        for prop, value in props.items():
            if prop in {"Name", "Source", "UniqueId"}:
                continue
            if prop == "ScriptGuid":
                require(value[0] == "string" and not value[2] and GUID.fullmatch(value[1])
                        and int(value[1].replace("-", "")[1:-1], 16) != 0 and value[1].lower() not in guids, "Malformed/duplicate added ScriptGuid")
                guids.add(value[1].lower())
            else:
                require(r.normalized(value) == r.normalized(template[prop]), "Nondefault added ModuleScript property: " + path + "/" + prop)


def validate_dom(before, after, sources, classes, asset_sources, declared):
    require(len(before) == 4521 and len(after) == 4523, "Expected exact 4521 -> 4523 two-ModuleScript update")
    after, reindexed = canonicalize(before, after)
    require(builder.REQUIRED_CHANGED.issubset(declared) and set(declared).issubset(builder.ALLOWED_CHANGED), "Unexpected declared existing Source changes")
    all_sources = sources | asset_sources
    require(len(sources) == 152 and len(asset_sources) == 3 and len(all_sources) == 155, "Expected 152 project + three unchanged Fog Sources")
    require(set(all_sources) == {path for path, node in after.items() if "Source" in node["properties"]}, "Persistent Source set differs")
    require({path for path in after if r.p.owned(path)} == set(classes) and set(classes) - set(before) == ADDITIONS, "Code topology differs beyond two Modules")
    accepted = {row["path"]: row for row in builder.accepted_payload()["entries"]}
    for path, cls in classes.items():
        require(after[path]["class"] == cls, "Configured class differs: " + path)
    for path, source in all_sources.items():
        value = after[path]["properties"]["Source"]
        require(after[path]["class"] in r.SCRIPT_CLASSES and value[0] == "string" and not value[2]
                and value[1].replace("\r\n", "\n") == source, "Source mismatch: " + path)
        if path in before:
            original = before[path]["properties"]["Source"]
            require(builder.sha(original[1].replace("\r\n", "\n").encode()) == accepted[path]["after"], "Accepted Source baseline differs")
    validate_added_modules(before, after)
    changes, changed_sources = [], []
    for path, node in before.items():
        actual = after[path]
        require(set(node["properties"]) == set(actual["properties"]), "Retained property set changed: " + path)
        for prop, value in node["properties"].items():
            other = actual["properties"][prop]
            if prop == "Source":
                require(value[0] == other[0] == "string" and not value[2] and not other[2], "Malformed retained Source")
                if value[1].replace("\r\n", "\n") == other[1].replace("\r\n", "\n"):
                    continue
                require(path in declared, "Source outside declared flashlight update: " + path)
                changed_sources.append(path)
                changes.append({"path": path, "property": prop, "reason": "declared_flashlight_source"})
                continue
            if value == other or r.normalized(value) == r.normalized(other):
                continue
            camera = path == "Workspace/Camera" and prop in {"CFrame", "Focus"}
            selection = path in r.SELECTION_PATHS and node["class"] == "Instance" and prop == "UniqueId"
            require(camera or selection, "Retained world/art/Lighting/metadata changed: " + path + "/" + prop)
            if camera:
                old.helpers.validate_camera_frame(other)
            changes.append({"path": path, "property": prop, "reason": "editor_metadata"})
    require(set(changed_sources) == set(declared), "Declared existing Source update set differs")
    return {"passed": True, "complete": True, "variant": "A", "matching_sources": 152, "matching_asset_sources": 3,
        "total_sources": 155, "new_instances": 2, "removed_instances": 0, "added_module_paths": sorted(ADDITIONS),
        "source_changes": sorted(changed_sources), "source_change_count": len(changed_sources), "allowed_changes": changes,
        "reindexed_exporter_paths": reindexed, "retained_identities_classes_names_parents_exact": True,
        "world_art_lighting_and_mesh_metadata_exact": True}


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = sha256(original), sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Immutable before-flashlight baseline differs")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl" and candidate != original, "Candidate must be a separate engine-saved RBXL")
    _, sources, classes, declared = builder.mapping()
    assets = fog.current_sources()
    before, bwarn = r.p.known_dom(original)
    after, awarn = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    report = validate_dom(before, after, sources, classes, assets, declared)
    meta = r.p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "Corn ownership/corners differ")
    require(sha256(original) == old_hash and sha256(candidate) == new_hash, "Input scene changed during read-only audit")
    require(builder.mapping()[1:] == (sources, classes, declared) and fog.current_sources() == assets, "Code/build/assets changed during audit")
    return report | {"original_sha256": old_hash, "candidate_sha256": new_hash, "original_instances": len(before),
        "candidate_instances": len(after), "bytes": candidate.stat().st_size, "raw_terrain_exact": True,
        "raw_unknown_properties": unknown_after, "warnings": {"original": bwarn, "candidate": awarn},
        "scope": "Exact engine bytes: declared RoundController/RoundText Sources and two default ModuleScript additions only. All 4521 retained world/art/Lighting/mesh metadata/identities/classes/names/parents/raw Terrain exact; narrow finite editor Camera/selection only. No scene serialization or publishing."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    output = args.report.resolve()
    require(output.suffix.lower() == ".json" and any(output.is_relative_to((ROOT / folder).resolve()) for folder in ("build", ".artifacts")), "Report must remain in owned artifact/build folder")
    require(output not in {args.original.resolve(), args.candidate.resolve()}, "Report would overwrite input")
    report = check(args.original, args.candidate)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({key: value for key, value in report.items() if key not in {"allowed_changes", "raw_unknown_properties", "warnings"}}))
