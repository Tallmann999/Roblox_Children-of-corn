"""Read-only exact save audit of five audio comparison Sources on accepted 630 map.

All 4160 original instances, their identities, parents, art, world, Lighting and
raw Terrain remain exact. No new instance or world-property exception exists.
Only declared Source contents and narrow existing editor metadata may differ.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "place/Children_of_corn.before-rustle-comparison-20261015.rbxl"
BASELINE_HASH = "489af64fb7f36bdfd7756f1e1d701324c6f202cf931422cf91c72be476a9965d"
BASELINE_BYTES = 996617
BASELINE_INSTANCES = 4160
DECLARED_SOURCES = frozenset({
    "ReplicatedStorage/GameShared/Game/AudioRules",
    "ReplicatedStorage/GameShared/Game/AudioAssets",
    "ServerScriptService/GameServer/Game/RoundAudio",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/AudioController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/MovementController",
})
FRAME_KEYS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
spec = importlib.util.spec_from_file_location("rustle_copy_helpers", ROOT / "scripts/verify-resize-yellow-copy.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
r, fog = helpers.r, helpers.fog
require, sha256 = r.require, r.sha256


def validate_camera_frame(value):
    require(value[0] == "CoordinateFrame" and len(value[2]) == 12, "Malformed editor camera frame")
    fields = set()
    for key, child in value[2]:
        require(key in FRAME_KEYS and key not in fields and child[0] == key and not child[2], "Malformed editor camera component")
        number = float(child[1])
        require(math.isfinite(number) and abs(number) <= 3.4028234663852886e38, "Nonfinite/overflow editor camera frame")
        fields.add(key)


def validate_dom(before, after, sources, classes, asset_sources):
    require(len(before) == len(after) == BASELINE_INSTANCES, "Expected unchanged 4160-instance scene")
    require(sum("Source" in node["properties"] for node in before.values()) == 78, "Expected immutable 78-Source baseline")
    after, reindexed = helpers.canonicalize(before, after, {})
    all_sources = sources | asset_sources
    require(len(sources) == 75 and len(asset_sources) == 3 and len(all_sources) == 78, "Expected 75 code and three fog Sources")
    require(DECLARED_SOURCES.issubset(sources), "Declared audio Source missing from configured mapping")
    require(set(all_sources) == {path for path, node in after.items() if "Source" in node["properties"]}, "Persistent Source set differs")
    require({path for path in after if r.p.owned(path)} == set(classes), "Configured code topology differs")
    for path, cls in classes.items():
        require(after[path]["class"] == cls, "Configured code class changed: " + path)
    for path, source in all_sources.items():
        value = after[path]["properties"]["Source"]
        require(after[path]["class"] in r.SCRIPT_CLASSES and value[0] == "string" and not value[2] and value[1].replace("\r\n", "\n") == source, "Source mismatch: " + path)
    changes, source_changes = [], []
    for path, node in before.items():
        actual = after[path]
        require(set(node["properties"]) == set(actual["properties"]), "Original property set changed: " + path)
        for prop, value in node["properties"].items():
            other = actual["properties"][prop]
            if prop == "Source":
                require(value[0] == other[0] == "string" and not value[2] and not other[2], "Original Source shape changed: " + path)
                if value[1].replace("\r\n", "\n") == other[1].replace("\r\n", "\n"):
                    continue
                require(path in DECLARED_SOURCES, "Source outside declared five changed: " + path)
                source_changes.append(path)
                changes.append({"path": path, "property": prop, "reason": "declared_audio_source"})
                continue
            if other == value or r.normalized(other) == r.normalized(value):
                continue
            camera = path == "Workspace/Camera" and prop in {"CFrame", "Focus"}
            selection = path in r.SELECTION_PATHS and node["class"] == "Instance" and prop == "UniqueId"
            require(camera or selection, "Original world/Lighting/art/property changed: " + path + "/" + prop)
            if camera:
                validate_camera_frame(other)
            changes.append({"path": path, "property": prop, "reason": "editor_metadata"})
    return {"matching_sources": 75, "matching_asset_sources": 3, "total_sources": 78,
        "new_instances": 0, "removed_instances": 0, "field_side": 630,
        "source_changes": sorted(source_changes), "source_change_count": len(source_changes),
        "declared_source_paths": sorted(DECLARED_SOURCES), "reindexed_exporter_paths": reindexed,
        "world_and_lighting_exact": True, "original_art_preserved": True,
        "retained_identities_names_classes_parents_exact": True, "allowed_changes": changes}


def check(original, candidate):
    original, candidate = original.resolve(), candidate.resolve()
    old_hash, new_hash = sha256(original), sha256(candidate)
    require(original == BASELINE.resolve() and old_hash == BASELINE_HASH and original.stat().st_size == BASELINE_BYTES, "Immutable before-rustle-comparison baseline changed")
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "Candidate must be an exact engine-saved RBXL")
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
    return result | {"passed": True, "original_sha256": old_hash, "candidate_sha256": new_hash,
        "original_instances": len(before), "candidate_instances": len(after), "bytes": candidate.stat().st_size,
        "raw_unknown_properties": unknown_after, "warnings": {"original": warning_before, "candidate": warning_after},
        "scope": "Read-only exact engine bytes. All 75 src and three fog Sources match declared files; only five approved Source contents may change. Zero instance/world/Lighting/art/raw Terrain deltas, exact retained identities/classes/names/parents; existing narrow camera/selection editor metadata only. No scene serialization."}


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
