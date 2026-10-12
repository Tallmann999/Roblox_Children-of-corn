"""Strict read-only verification of an engine-saved inventory update.

World deltas are calculated from the immutable 60-Source engine baseline and
the narrow torch installer contract. No candidate-derived allowlist is used.
Lune only reads/exports the in-memory DOM; no RBXL is reconstructed or written.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("preservation", ROOT / "scripts/verify-scene-preservation.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
BASELINE = ROOT / "place/Children_of_corn.before-inventory-20261012.rbxl"
BASELINE_HASH = "6f9a95e624a96ab6c318a4a1912db0c5aae7b6d6e1dfa0d92f70dcc97638e03a"
BASELINE_BYTES = 981060
BASELINE_SOURCES = 60
EXPECTED_SOURCES = 65
TORCH_ROOT = "Workspace/CornMap/TorchMarkers"
ARCHIVE = "ServerStorage/CornInventoryTorchArchive"
ARCHIVED_ROWS = (2, 4, 6, 8)
RETAINED_ROWS = (1, 3, 5, 7)
ADDITIONS = {
    "ReplicatedStorage/GameShared/Game/Inventory",
    "ServerScriptService/GameServer/Game/ItemModels",
    "ServerScriptService/GameServer/Game/InventoryWorld",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/InventoryController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Game/InventoryHud",
}
SELECTION_PATHS = {"FilteredSelection", "FilteredSelection#2", "FilteredSelection#3", "FilteredSelection#4"}
SCRIPT_CLASSES = {"ModuleScript", "Script", "LocalScript"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON key: " + key)
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def mapping_from_sourcemap(path):
    sources, classes = {}, {}
    def walk(node, prefix=None):
        current = "" if prefix is None else (prefix + "/" + node["name"] if prefix else node["name"])
        if p.owned(current):
            require(current not in classes, "Duplicate Rojo path: " + current)
            classes[current] = node["className"]
        files = [f for f in node.get("filePaths", []) if f.startswith("src/") and f.endswith(".luau")]
        require(len(files) <= 1, "Ambiguous source mapping: " + current)
        if files:
            file_path = (ROOT / files[0]).resolve()
            require(p.owned(current) and file_path.is_relative_to((ROOT / "src").resolve()), "Source mapping outside owned code/src: " + current)
            sources[current] = file_path.read_text(encoding="utf-8").replace("\r\n", "\n")
        for child in node.get("children", []):
            walk(child, current)
    walk(load_json(path))
    require(len(sources) == EXPECTED_SOURCES and ADDITIONS.issubset(sources), "Stale build/sourcemap: expected 65 inventory Sources")
    require(set(sources).issubset(classes), "Sources outside configured code roots")
    return sources, classes


def normalized(value):
    text = value[1]
    # Container indentation and an empty optional/content/null value carry no
    # data. Whitespace inside strings or Source remains significant.
    if not text.strip() and (value[2] or value[0] in {"OptionalCoordinateFrame", "ContentId", "Content", "null"}):
        text = ""
    children = [[tag, normalized(child)] for tag, child in value[2]]
    if text == value[1] and all(mapped[1] is original[1] for mapped, original in zip(children, value[2])):
        return value
    return [value[0], text, children]


def moved_path(path):
    for row in ARCHIVED_ROWS:
        prefix = TORCH_ROOT + "/road_exit_row_%02d" % row
        if path == prefix or path.startswith(prefix + "/"):
            return ARCHIVE + path[len(TORCH_ROOT):]
    return path


def remap_refs(value):
    text = moved_path(value[1]) if value[0] == "Ref" else value[1]
    children = [[tag, remap_refs(child)] for tag, child in value[2]]
    if text == value[1] and all(mapped[1] is original[1] for mapped, original in zip(children, value[2])):
        return value
    return [value[0], text, children]


def translated_frame(value, dx, dz):
    require(value[0] == "CoordinateFrame", "Expected canonical torch CFrame")
    result = copy.deepcopy(value)
    tags = {tag: child for tag, child in result[2]}
    require(set(tags) == {"X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"}, "Missing CFrame components")
    # All installer translations and the baseline X/Z are integral studs.
    # Preserve Y and all rotation components exactly rather than rounding them.
    for axis, delta in (("X", dx), ("Z", dz)):
        number = float(tags[axis][1])
        require(math.isfinite(number) and number.is_integer(), "Unexpected nonintegral baseline torch placement")
        tags[axis][1] = str(int(number + delta))
    return result


def world_changes(before):
    models = {path for path, node in before.items() if path.startswith(TORCH_ROOT + "/") and path.count("/") == TORCH_ROOT.count("/") + 1 and node["class"] == "Model"}
    require(len(models) == 31, "Expected 31 baseline torch models")
    changes = {}
    for model in models:
        light = model + "/Flame/TorchLight"
        require(light in before and before[light]["class"] == "PointLight", "Torch light missing: " + light)
        require(before[light]["properties"]["Brightness"] == ["float", "2", []], "Unknown baseline torch brightness")
        if moved_path(model) == model:
            changes[(light, "Brightness")] = ["float", "1", []]
    for row in RETAINED_ROWS:
        model = TORCH_ROOT + "/road_exit_row_%02d" % row
        dx, dz = (-4 if row <= 4 else 4), (-4 if row in (1, 5) else -12)
        for name in ("Pole", "Flame"):
            path = model + "/" + name
            require(path in before and before[path]["class"] == "Part", "Baseline exit torch structure missing")
            changes[(path, "CFrame")] = translated_frame(before[path]["properties"]["CFrame"], dx, dz)
    require(len(changes) == 35, "Expected 27 brightness and 8 translation deltas")
    require(sum(moved_path(path) != path for path in before) == 20, "Expected four complete five-instance archive moves")
    return changes


def valid_unique_id(value):
    return (value[0] == "UniqueId" and value[2] == [] and
            re.fullmatch(r"[0-9a-fA-F]{32}", value[1]) is not None and int(value[1], 16) != 0)


def valid_script_guid(value):
    return (value[0] == "string" and value[2] == [] and
            re.fullmatch(r"\{[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}", value[1]) is not None and
            value[1].replace("-", "").strip("{}").strip("0") != "")


def addition_template(before, path):
    if path == ARCHIVE:
        template = copy.deepcopy(before["Workspace/CornMap/KeySlots"])
    else:
        require(path in ADDITIONS, "Unknown new instance: " + path)
        reference = ("ReplicatedStorage/GameShared/Game/Stamina" if path.startswith("ReplicatedStorage/") else
                     "ServerScriptService/GameServer/Game/MonsterHunt" if path.startswith("ServerScriptService/") else
                     "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/GateHintController")
        template = copy.deepcopy(before[reference])
    template["properties"]["Name"] = ["string", path.rsplit("/", 1)[1], []]
    return template


def validate_new_instance(before, after, path, sources):
    actual, expected = after[path], addition_template(before, path)
    require(actual["class"] == expected["class"], "New instance class changed: " + path)
    require(set(actual["properties"]) == set(expected["properties"]), "New instance property set changed: " + path)
    old_ids = {node["properties"].get("UniqueId", [None, "", []])[1].lower() for node in before.values()}
    old_guids = {node["properties"].get("ScriptGuid", [None, "", []])[1].lower() for node in before.values()}
    for prop, value in actual["properties"].items():
        if prop == "UniqueId":
            require(valid_unique_id(value) and value[1].lower() not in old_ids, "New instance lacks fresh UniqueId: " + path)
        elif prop == "ScriptGuid":
            require(valid_script_guid(value) and value[1].lower() not in old_guids, "New script lacks fresh ScriptGuid: " + path)
        elif prop == "Source":
            require(path in sources and value[0] == expected["properties"]["Source"][0] and value[2] == [], "Unexpected new Source shape")
            require(value[1].replace("\r\n", "\n") == sources[path], "New Source differs from src: " + path)
        else:
            require(normalized(value) == normalized(expected["properties"][prop]), "New instance differs from independent defaults: " + path + "/" + prop)


def validate_dom(before, after, sources, code_classes):
    require(sum("Source" in n["properties"] for n in before.values()) == BASELINE_SOURCES, "Expected immutable 60-Source baseline")
    require(len(sources) == EXPECTED_SOURCES and ADDITIONS.issubset(sources), "Expected 65 source mappings")
    require(set(sources) == {path for path, node in after.items() if "Source" in node["properties"]}, "Candidate Source paths differ from sourcemap")
    require({path for path in after if p.owned(path)} == set(code_classes), "Unexpected/missing code instance")
    for path, cls in code_classes.items():
        require(after[path]["class"] == cls, "Code class changed: " + path)
    for path, text in sources.items():
        require(after[path]["class"] in SCRIPT_CLASSES and after[path]["properties"]["Source"][0] == "string" and after[path]["properties"]["Source"][2] == [], "Source class/type mismatch")
        require(after[path]["properties"]["Source"][1].replace("\r\n", "\n") == text, "Source mismatch: " + path)
    targets = {moved_path(path) for path in before}
    require(len(targets) == len(before), "Archive target collision")
    require(targets.issubset(after), "Original/archived instance missing: " + str(sorted(targets - set(after))[:8]))
    additions = set(after) - targets
    require(additions == ADDITIONS | {ARCHIVE}, "Unexpected/missing new world/code instance: " + str(sorted(additions ^ (ADDITIONS | {ARCHIVE}))[:8]))
    require(set(code_classes) - set(before) == ADDITIONS, "Unexpected new code topology")
    for path in additions:
        validate_new_instance(before, after, path, sources)
    for prop in ("UniqueId", "ScriptGuid"):
        identifiers = [after[path]["properties"][prop][1].lower() for path in additions if prop in after[path]["properties"]]
        require(len(identifiers) == len(set(identifiers)), "Duplicate new " + prop)
    world = world_changes(before)
    changes = []
    for path, node in before.items():
        target = moved_path(path)
        actual = after[target]
        require(node["class"] == actual["class"], "Original class changed: " + path)
        require(set(node["properties"]) == set(actual["properties"]), "Original property set changed: " + path)
        for prop, original in node["properties"].items():
            value = actual["properties"][prop]
            expected = remap_refs(world.get((path, prop), original))
            if normalized(value) == normalized(expected):
                if normalized(value) != normalized(original):
                    changes.append({"path": path, "target": target, "property": prop,
                                    "reason": "approved_torch_delta" if (path, prop) in world else "archive_ref_remap"})
                continue
            allowed = ((path in sources and prop == "Source") or
                       (path == "Workspace/Camera" and prop in {"CFrame", "Focus"}) or
                       (path in SELECTION_PATHS and node["class"] == "Instance" and prop == "UniqueId"))
            require(allowed and (path, prop) not in world, "Original property changed: " + path + "/" + prop)
            changes.append({"path": path, "target": target, "property": prop,
                            "reason": "source" if prop == "Source" else "editor_metadata"})
    return {"allowed_changes": changes, "new_instances": len(additions), "archived_original_instances": 20,
            "matching_sources": len(sources), "torch_models": 27, "exit_poles": 4, "wall_torches": 2,
            "approved_torch_properties": len(world)}


def validate_unknown(before, after):
    require(before.get("supported") and after.get("supported"), "Raw binary property check unavailable")
    require(before == after, "Unknown binary property / raw Terrain changed")


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    original_hash, candidate_hash = sha256(original), sha256(candidate)
    require(original_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Not the immutable before-inventory engine baseline")
    sources, classes = mapping_from_sourcemap(ROOT / "build/sourcemap.json")
    before, warning_before = p.known_dom(original)
    after, warning_after = p.known_dom(candidate)
    unknown_before, unknown_after = p.unknown_properties(original), p.unknown_properties(candidate)
    validate_unknown(unknown_before, unknown_after)
    result = validate_dom(before, after, sources, classes)
    meta = p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "CornMap ownership/corners invalid")
    require(sha256(original) == original_hash and sha256(candidate) == candidate_hash, "Input scene changed during verification")
    # Source files and the build mapping are checked again to reject races with
    # concurrent code changes while the engine copy was being inspected.
    require(mapping_from_sourcemap(ROOT / "build/sourcemap.json") == (sources, classes), "Source/build changed during verification")
    return result | {"passed": True, "original_sha256": original_hash, "candidate_sha256": candidate_hash,
        "original_instances": len(before), "candidate_instances": len(after),
        "original_world_preserved_except_explicit_torches": True, "raw_unknown_properties": unknown_after,
        "warnings": {"original": warning_before, "candidate": warning_after},
        "scope": "Read-only exact engine copy verification; baseline-derived torch deltas, exact world/art/raw Terrain and all 65 Sources. No scene write or candidate-derived allowlist."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    original, candidate, report_path = (x.resolve() for x in (args.original, args.candidate, args.report))
    require(report_path not in {original, candidate, BASELINE.resolve(), (ROOT / "place/Children_of_corn.rbxl").resolve()}, "Report must not overwrite scene")
    require(report_path.suffix.lower() == ".json" and any(report_path.is_relative_to((ROOT / folder).resolve()) for folder in ("build", ".artifacts")), "Report must be an owned build/artifact JSON file")
    report = check(original, candidate)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in {"allowed_changes", "warnings", "raw_unknown_properties"}}))
