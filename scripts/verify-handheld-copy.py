"""Strict read-only validation of exact engine-saved held-item code.

All author world/art/Lighting/raw Terrain stay exact. Only two new ModuleScripts,
approved Source content and editor Camera/selection metadata may change.
No candidate-derived world allowlist and no scene reconstruction are used.
"""
import argparse
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("inventory_helpers", ROOT / "scripts/verify-inventory-copy.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
p = helpers.p
require, sha256, load_json = helpers.require, helpers.sha256, helpers.load_json
normalized, validate_unknown = helpers.normalized, helpers.validate_unknown
BASELINE = ROOT / "place/Children_of_corn.before-handheld-20261012.rbxl"
BASELINE_HASH = "66997087e67a05e0095448c8c1fb91b51d61f6acf1de865a78df3b376fb87d93"
BASELINE_BYTES = 995413
BASELINE_SOURCES = 69
EXPECTED_SOURCES = 71
ADDITIONS = {
    "ReplicatedStorage/GameShared/Game/HandheldPresentation",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/HandheldController",
}
SELECTION_PATHS = helpers.SELECTION_PATHS
SCRIPT_CLASSES = helpers.SCRIPT_CLASSES


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
            source_path = (ROOT / files[0]).resolve()
            require(p.owned(current) and source_path.is_relative_to((ROOT / "src").resolve()), "Source outside configured roots: " + current)
            sources[current] = source_path.read_text(encoding="utf-8").replace("\r\n", "\n")
        for child in node.get("children", []):
            walk(child, current)
    walk(load_json(path))
    require(len(sources) == EXPECTED_SOURCES and ADDITIONS.issubset(sources), "Stale build/sourcemap: expected 71 handheld Sources")
    require(set(sources).issubset(classes), "Sources outside configured code")
    return sources, classes


def addition_template(before, path):
    require(path in ADDITIONS, "Unknown addition: " + path)
    reference = ("ReplicatedStorage/GameShared/Game/Stamina" if path.startswith("ReplicatedStorage/") else
                 "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/GateHintController")
    node = copy.deepcopy(before[reference])
    require(node["class"] == "ModuleScript", "Baseline ModuleScript default template missing")
    node["properties"]["Name"] = ["string", path.rsplit("/", 1)[1], []]
    return node


def validate_new_instance(before, after, path, sources):
    actual, expected = after[path], addition_template(before, path)
    require(actual["class"] == "ModuleScript", "New Source class changed: " + path)
    require(set(actual["properties"]) == set(expected["properties"]), "New Source property set changed: " + path)
    old_ids = {n["properties"].get("UniqueId", [None, "", []])[1].lower() for n in before.values()}
    old_guids = {n["properties"].get("ScriptGuid", [None, "", []])[1].lower() for n in before.values()}
    for prop, value in actual["properties"].items():
        if prop == "UniqueId":
            require(helpers.valid_unique_id(value) and value[1].lower() not in old_ids, "New Source lacks fresh UniqueId: " + path)
        elif prop == "ScriptGuid":
            require(helpers.valid_script_guid(value) and value[1].lower() not in old_guids, "New Source lacks fresh ScriptGuid: " + path)
        elif prop == "Source":
            require(value[0] == expected["properties"][prop][0] and value[2] == [] and value[1].replace("\r\n", "\n") == sources[path], "New Source differs from src: " + path)
        else:
            require(normalized(value) == normalized(expected["properties"][prop]), "New Source differs from independent defaults: " + path + "/" + prop)


def validate_dom(before, after, sources, classes):
    require(sum("Source" in n["properties"] for n in before.values()) == BASELINE_SOURCES, "Expected immutable 69-Source baseline")
    require(set(before).issubset(after), "Original instance missing: " + str(sorted(set(before) - set(after))[:8]))
    require(set(after) - set(before) == ADDITIONS, "Unexpected/missing new world/code instance: " + str(sorted((set(after) - set(before)) ^ ADDITIONS)[:8]))
    require(len(sources) == EXPECTED_SOURCES and ADDITIONS.issubset(sources), "Expected 71 Source mappings")
    require(set(sources) == {path for path, node in after.items() if "Source" in node["properties"]}, "Source paths differ from sourcemap")
    require({path for path in after if p.owned(path)} == set(classes), "Unexpected/missing code instance")
    require(set(classes) - set(before) == ADDITIONS, "Unexpected new code topology")
    for path, cls in classes.items():
        require(after[path]["class"] == cls, "Code class changed: " + path)
    for path, source in sources.items():
        value = after[path]["properties"]["Source"]
        require(after[path]["class"] in SCRIPT_CLASSES and value[0] == "string" and value[2] == [], "Source class/type mismatch: " + path)
        require(value[1].replace("\r\n", "\n") == source, "Source mismatch: " + path)
    for path in ADDITIONS:
        validate_new_instance(before, after, path, sources)
    for prop in ("UniqueId", "ScriptGuid"):
        values = [after[path]["properties"][prop][1].lower() for path in ADDITIONS]
        require(len(values) == len(set(values)), "Duplicate new " + prop)
    changes = []
    for path, node in before.items():
        actual = after[path]
        require(node["class"] == actual["class"], "Original class changed: " + path)
        require(set(node["properties"]) == set(actual["properties"]), "Original property set changed: " + path)
        for prop, value in node["properties"].items():
            other = actual["properties"][prop]
            if other == value or normalized(other) == normalized(value):
                continue
            allowed = ((path in sources and prop == "Source") or
                       (path == "Workspace/Camera" and prop in {"CFrame", "Focus"}) or
                       (path in SELECTION_PATHS and node["class"] == "Instance" and prop == "UniqueId"))
            require(allowed, "Original property changed: " + path + "/" + prop)
            changes.append({"path": path, "property": prop, "reason": "source" if prop == "Source" else "editor_metadata"})
    return {"matching_sources": len(sources), "new_instances": len(ADDITIONS), "allowed_changes": changes,
            "world_and_lighting_exact": True, "original_art_preserved": True}


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    original_hash, candidate_hash = sha256(original), sha256(candidate)
    require(original_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Not the immutable before-handheld engine baseline")
    sources, classes = mapping_from_sourcemap(ROOT / "build/sourcemap.json")
    before, warning_before = p.known_dom(original)
    after, warning_after = p.known_dom(candidate)
    unknown_before, unknown_after = p.unknown_properties(original), p.unknown_properties(candidate)
    validate_unknown(unknown_before, unknown_after)
    result = validate_dom(before, after, sources, classes)
    meta = p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "CornMap ownership/corners invalid")
    require(sha256(original) == original_hash and sha256(candidate) == candidate_hash, "Input scene changed during verification")
    require(mapping_from_sourcemap(ROOT / "build/sourcemap.json") == (sources, classes), "Source/build changed during verification")
    return result | {"passed": True, "original_sha256": original_hash, "candidate_sha256": candidate_hash,
        "original_instances": len(before), "candidate_instances": len(after), "raw_unknown_properties": unknown_after,
        "warnings": {"original": warning_before, "candidate": warning_after},
        "scope": "Read-only exact engine copy validation; two new ModuleScripts and exact 71 Sources, all author world/art/Lighting/raw Terrain preserved. No scene write."}


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
