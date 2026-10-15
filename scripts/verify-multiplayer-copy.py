"""Read-only exact engine-save audit of the shared-key multiplayer code update.

All 4160 baseline identities, parents, classes, names, world/art/Lighting and
raw Terrain are retained. Only declared Source contents, two ModuleScripts in
the existing server Game folder and narrow editor camera/selection metadata
are accepted. This module never reconstructs or writes a Roblox scene.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-multiplayer-resume-20261015.rbxl"
BASELINE_HASH = "b5ef0471325bbe5c9ab7178575753453cbf59afb15ed905eb12dfc70a4bbf6c8"
BASELINE_BYTES = 997184
BASELINE_INSTANCES = 4160
EXPECTED_SOURCES = 77
ADDITIONS = frozenset({
    "ServerScriptService/GameServer/Game/TeamRound",
    "ServerScriptService/GameServer/Game/RoundParticipant",
})
DECLARED_SOURCES = frozenset({
    "ReplicatedStorage/GameShared/Config/GameConfig",
    "ReplicatedStorage/GameShared/Game/RoundText",
    "ServerScriptService/GameServer/Services/RoundService",
    "ServerScriptService/GameServer/Game/MonsterHunt",
    "ServerScriptService/GameServer/Game/RoundAudio",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/RoundController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Game/RoundHud",
    "StarterPlayer/StarterPlayerScripts/GameClient/Bootstrap",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/MonsterAnimationController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/FarmGeometryController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornAppearanceController",
    "ServerScriptService/GameServer/Services/FarmGeometryService",
    "ServerScriptService/GameServer/Game/CornField",
})
spec = importlib.util.spec_from_file_location("multiplayer_copy_helpers", ROOT / "scripts/verify-rustle-comparison-copy.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
r, fog = helpers.r, helpers.fog
require, sha256 = r.require, r.sha256
GUID = re.compile(r"\{[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}")


def mapping_from_sourcemap(path):
    sources, classes = {}, {}
    def walk(node, prefix=None):
        current = "" if prefix is None else (prefix + "/" + node["name"] if prefix else node["name"])
        if r.p.owned(current):
            require(current not in classes, "Duplicate configured code path: " + current)
            classes[current] = node["className"]
        files = [f for f in node.get("filePaths", []) if f.startswith("src/") and f.endswith(".luau")]
        require(len(files) <= 1, "Ambiguous Source mapping: " + current)
        if files:
            target = (ROOT / files[0]).resolve()
            require(r.p.owned(current) and target.is_relative_to((ROOT / "src").resolve()), "Source outside configured roots: " + current)
            sources[current] = target.read_text(encoding="utf-8").replace("\r\n", "\n")
        for child in node.get("children", []):
            walk(child, current)
    walk(r.load_json(path))
    require(len(sources) == EXPECTED_SOURCES and ADDITIONS.issubset(sources) and DECLARED_SOURCES.issubset(sources), "Run check.ps1: expected 77 multiplayer Sources")
    require(set(sources).issubset(classes), "Source outside configured code classes")
    return sources, classes


def canonicalize(before, after):
    identity, remap_refs = helpers.helpers.identity, helpers.helpers.remap_refs
    before_ids = {identity(node): path for path, node in before.items()}
    require(len(before_ids) == len(before), "Duplicate immutable identity")
    paths, seen_ids, targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in seen_ids, "Duplicate candidate identity")
        seen_ids.add(uid)
        target = before_ids.get(uid)
        if target is None:
            if path in ADDITIONS:
                require(node["class"] == "ModuleScript" and node["properties"].get("Name") == ["string", path.rsplit("/", 1)[1], []], "Invalid added ModuleScript: " + path)
            else:
                require(path in r.SELECTION_PATHS and node["class"] == "Instance" and node["properties"].get("Name") == ["string", "FilteredSelection", []], "Unexpected/replaced instance identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical original target")
        targets.add(target)
        paths[path] = target
    require(targets == set(before) | ADDITIONS, "Missing/extra original or added instances")
    reindexed = sum(path != target for path, target in paths.items())
    result = {}
    for path, target in paths.items():
        actual = after[path]
        if target in before:
            old = before[target]
            require(old["class"] == actual["class"] and old["properties"]["Name"] == actual["properties"].get("Name"), "Original class/Name changed: " + target)
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or (actual_parent in paths and paths[actual_parent] == parent), "Original/added parent identity changed: " + target)
        # The normal unique-name code addition does not reindex any exported
        # path. Preserve the exact same values without recursively copying the
        # complete 4160-instance world unless a real suffix reindex occurred.
        result[target] = actual if not reindexed else actual | {"properties": {prop: remap_refs(value, paths) for prop, value in actual["properties"].items()}}
    return result, reindexed


def validate_added_modules(before, after):
    template = before["ServerScriptService/GameServer/Game/RoundAudio"]["properties"]
    guids = {node["properties"]["ScriptGuid"][1].lower() for node in before.values() if "ScriptGuid" in node["properties"]}
    for path in ADDITIONS:
        node = after[path]
        props = node["properties"]
        require(node["class"] == "ModuleScript" and set(props) == set(template), "Unexpected new ModuleScript property set: " + path)
        require(not any(other.startswith(path + "/") for other in after), "New ModuleScript has children: " + path)
        for prop, value in props.items():
            if prop in {"Name", "Source", "UniqueId"}:
                continue
            if prop == "ScriptGuid":
                require(value[0] == "string" and not value[2] and GUID.fullmatch(value[1]) and int(value[1].replace("-", "")[1:-1], 16) != 0, "Malformed new ScriptGuid: " + path)
                require(value[1].lower() not in guids, "Duplicate new ScriptGuid: " + path)
                guids.add(value[1].lower())
            else:
                require(r.normalized(value) == r.normalized(template[prop]), "Nondefault new ModuleScript property: " + path + "/" + prop)


def validate_dom(before, after, sources, classes, asset_sources):
    require(len(before) == BASELINE_INSTANCES and len(after) == BASELINE_INSTANCES + len(ADDITIONS), "Expected exact 4160-to-4162-instance code update")
    require(sum("Source" in node["properties"] for node in before.values()) == 78, "Expected immutable 78-Source baseline")
    after, reindexed = canonicalize(before, after)
    all_sources = sources | asset_sources
    require(len(sources) == EXPECTED_SOURCES and len(asset_sources) == 3 and len(all_sources) == EXPECTED_SOURCES + 3, "Expected 77 project and three Fog Sources")
    require(ADDITIONS.issubset(sources) and DECLARED_SOURCES.issubset(sources), "Declared Sources missing")
    require(set(all_sources) == {path for path, node in after.items() if "Source" in node["properties"]}, "Persistent Source set differs")
    require({path for path in after if r.p.owned(path)} == set(classes), "Configured code topology differs")
    require(set(classes) - set(before) == ADDITIONS, "Unexpected new code containers")
    for path, cls in classes.items():
        require(after[path]["class"] == cls, "Configured code class changed: " + path)
    for path, source in all_sources.items():
        value = after[path]["properties"]["Source"]
        require(after[path]["class"] in r.SCRIPT_CLASSES and value[0] == "string" and not value[2] and value[1].replace("\r\n", "\n") == source, "Source mismatch: " + path)
    validate_added_modules(before, after)
    changes, source_changes = [], []
    for path, old in before.items():
        actual = after[path]
        require(set(old["properties"]) == set(actual["properties"]), "Original property set changed: " + path)
        for prop, value in old["properties"].items():
            other = actual["properties"][prop]
            if prop == "Source":
                require(value[0] == other[0] == "string" and not value[2] and not other[2], "Original Source shape changed: " + path)
                if value[1].replace("\r\n", "\n") == other[1].replace("\r\n", "\n"):
                    continue
                require(path in DECLARED_SOURCES, "Source outside declared multiplayer changes: " + path)
                source_changes.append(path)
                changes.append({"path": path, "property": prop, "reason": "declared_multiplayer_source"})
                continue
            if other == value or r.normalized(other) == r.normalized(value):
                continue
            camera = path == "Workspace/Camera" and prop in {"CFrame", "Focus"}
            selection = path in r.SELECTION_PATHS and old["class"] == "Instance" and prop == "UniqueId"
            require(camera or selection, "Original world/art/Lighting/property changed: " + path + "/" + prop)
            if camera:
                helpers.validate_camera_frame(other)
            changes.append({"path": path, "property": prop, "reason": "editor_metadata"})
    return {"matching_sources": EXPECTED_SOURCES, "matching_asset_sources": 3, "total_sources": EXPECTED_SOURCES + 3,
        "new_instances": len(ADDITIONS), "removed_instances": 0, "field_side": 630,
        "added_module_paths": sorted(ADDITIONS), "source_changes": sorted(source_changes), "source_change_count": len(source_changes),
        "declared_source_paths": sorted(DECLARED_SOURCES), "reindexed_exporter_paths": reindexed,
        "world_and_lighting_exact": True, "original_art_preserved": True,
        "retained_identities_names_classes_parents_exact": True, "allowed_changes": changes}


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = sha256(original), sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Immutable before-multiplayer-resume baseline changed")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "Candidate must be an exact engine-saved RBXL")
    sources, classes = mapping_from_sourcemap(ROOT / "build/sourcemap.json")
    asset_sources = fog.current_sources()
    before, warning_before = r.p.known_dom(original)
    after, warning_after = r.p.known_dom(candidate)
    unknown_before, unknown_after = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
    r.validate_unknown(unknown_before, unknown_after)
    result = validate_dom(before, after, sources, classes, asset_sources)
    meta = r.p.corn_metadata(candidate)
    require(meta["corners_valid"] and meta["overview_owned"] and meta["preview_owned"], "CornMap ownership/corners invalid")
    require(sha256(original) == old_hash and sha256(candidate) == new_hash, "Input scene changed during read-only audit")
    require(mapping_from_sourcemap(ROOT / "build/sourcemap.json") == (sources, classes) and fog.current_sources() == asset_sources, "Sources/build/assets changed during audit")
    return result | {"passed": True, "original_sha256": old_hash, "candidate_sha256": new_hash,
        "original_instances": len(before), "candidate_instances": len(after), "bytes": candidate.stat().st_size,
        "raw_unknown_properties": unknown_after, "warnings": {"original": warning_before, "candidate": warning_after},
        "scope": "Read-only exact engine bytes. All 77 project and three Fog Sources match files; only sixteen declared existing Source contents and two default ModuleScript additions in the existing server Game folder. All 4160 retained identities/classes/names/parents, world/art/Lighting/raw Terrain are exact; narrow existing editor camera/selection metadata only. No scene serialization."}


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
    print(json.dumps({key: value for key, value in report.items() if key not in {"allowed_changes", "warnings", "raw_unknown_properties"}}))
