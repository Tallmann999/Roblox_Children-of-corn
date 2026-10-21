"""Read-only strict B save audit for two light shadow flags and one controller.

The immutable pre-shadow B is read from its hash-checked ZIP into an external
temporary directory. No place is serialized, promoted or left in the project.
All 156 retained Sources, world/art/physics/mesh metadata and raw Terrain remain
exact. Only a default CornShadowController ModuleScript and the two bank
Shadows false -> true changes are allowed, plus existing finite editor metadata.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "corn_shadows_save_helpers", ROOT / "scripts/verify-flashlight-copy.py"
)
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
r, require, identity, remap_refs = h.r, h.require, h.identity, h.remap_refs

OUT = ROOT / ".artifacts/playtests/2026-10-21-corn-shadows"
ARCHIVE = OUT / "before-shadows.zip"
ARCHIVE_SHA = "86ba89f751d03a7a1b332a614b13bc2febdde88647b7a2db9db0ba8b068c2c29"
INFO = OUT / "baseline.json"
ARCHIVE_ENTRY = "checkpoint/B-before-shadows.rbxl"
BASELINE_SHA = "f33571e819fb605130b05489789c93f11c0ef92a3e9762c77691130a60c3d9c0"
BASELINE_BYTES = 1494878
A_SHA = "c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7"
A_SCENE = ROOT / "place/Children_of_corn.rbxl"
ADDED = "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornShadowController"
SOURCE = ROOT / "src/client/Controllers/CornShadowController.luau"
MODULE_TEMPLATE = "ServerScriptService/GameServer/Game/RoundAudio"
BANK = "ReplicatedStorage/CornFlashlightSettings"
SHADOW_PATHS = {BANK + "/Wide", BANK + "/Core"}
GUID = re.compile(r"\{[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def controller_source():
    source = SOURCE.read_text(encoding="utf-8").replace("\r\n", "\n")
    require(source.strip() and "\x00" not in source, "Missing/invalid controller Source")
    return source


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate baseline metadata key: " + key)
        result[key] = value
    return result


def baseline_info():
    info = json.loads(INFO.read_bytes(), object_pairs_hook=unique_object)
    require(set(info) == {
        "archive_sha256", "baseline_sha256", "baseline_bytes", "untouched_A_sha256"
    }, "Unexpected immutable baseline metadata schema")
    require(info["baseline_sha256"] == BASELINE_SHA
            and type(info["baseline_bytes"]) is int
            and info["baseline_bytes"] == BASELINE_BYTES
            and info["untouched_A_sha256"] == A_SHA,
            "Immutable B/A checkpoint metadata differs")
    require(info["archive_sha256"] == ARCHIVE_SHA
            and sha(ARCHIVE) == ARCHIVE_SHA, "Archived immutable bytes changed")
    require(sha(A_SCENE) == A_SHA, "Untouched A changed")
    return info


@contextmanager
def baseline_file():
    """Expose the exact archived baseline only outside this repository."""
    metadata_sha = sha(INFO)
    info = baseline_info()
    with zipfile.ZipFile(ARCHIVE) as archive:
        entries = [row for row in archive.infolist() if row.filename == ARCHIVE_ENTRY]
        require(len(entries) == 1 and entries[0].file_size == BASELINE_BYTES,
                "Missing/duplicate/invalid archived B checkpoint")
        original = archive.read(ARCHIVE_ENTRY)
    require(len(original) == BASELINE_BYTES
            and hashlib.sha256(original).hexdigest() == BASELINE_SHA,
            "Archived B baseline differs from accepted f335 checkpoint")
    with tempfile.TemporaryDirectory(prefix="corn-shadows-read-only-") as directory:
        path = Path(directory) / "B-before-shadows.rbxl"
        require(not path.resolve().is_relative_to(ROOT.resolve()), "Baseline temp must be external")
        path.write_bytes(original)
        yield path
        require(sha(path) == BASELINE_SHA, "Temporary immutable baseline changed")
    require(sha(INFO) == metadata_sha and baseline_info() == info,
            "Baseline metadata/archive/A changed during read-only audit")


def read_baseline():
    with baseline_file() as path:
        before, warning = r.p.known_dom(path)
        unknown = r.p.unknown_properties(path)
    return before, warning, unknown


def canonicalize(before, after):
    """Prove identity, real Name and parent before resolving exporter suffixes."""
    old_ids = {identity(node): path for path, node in before.items()}
    require(len(old_ids) == len(before), "Duplicate baseline identity")
    paths, ids, targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in ids, "Duplicate candidate identity")
        ids.add(uid)
        target = old_ids.get(uid)
        if target is None:
            added = path == ADDED and node["class"] == "ModuleScript"
            selection = (path in r.SELECTION_PATHS and node["class"] == "Instance"
                         and node["properties"].get("Name") == ["string", "FilteredSelection", []])
            require(added or selection, "Unexpected/replaced instance identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical identity target")
        paths[path] = target
        targets.add(target)
    require(targets == set(before) | {ADDED}, "Missing/extra original or added instances")
    result = {}
    reindexed = sum(path != target for path, target in paths.items())
    for path, target in paths.items():
        actual = after[path]
        if target in before:
            original = before[target]
            require(original["class"] == actual["class"]
                    and original["properties"]["Name"] == actual["properties"].get("Name"),
                    "Retained class/real Name changed: " + target)
        else:
            require(actual["properties"].get("Name") == ["string", "CornShadowController", []],
                    "Added controller Name changed")
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent)
                or (actual_parent in paths and paths[actual_parent] == parent),
                "Retained/added parent identity changed: " + target)
        result[target] = actual if not reindexed else actual | {
            "properties": {key: remap_refs(value, paths)
                           for key, value in actual["properties"].items()}
        }
    return result, reindexed


def validate_added_module(before, after, source):
    template = before[MODULE_TEMPLATE]["properties"]
    node, props = after[ADDED], after[ADDED]["properties"]
    require(node["class"] == "ModuleScript" and set(props) == set(template),
            "Added ModuleScript class/property schema differs")
    require(not any(path.startswith(ADDED + "/") for path in after),
            "New controller must be childless")
    guids = {node["properties"]["ScriptGuid"][1].lower()
             for node in before.values() if "ScriptGuid" in node["properties"]}
    for prop, value in props.items():
        if prop in {"Name", "UniqueId"}:
            continue
        if prop == "Source":
            require(value[0] == "string" and not value[2]
                    and value[1].replace("\r\n", "\n") == source,
                    "Added controller Source differs from src")
        elif prop == "ScriptGuid":
            require(value[0] == "string" and not value[2] and GUID.fullmatch(value[1])
                    and int(value[1].replace("-", "")[1:-1], 16) != 0
                    and value[1].lower() not in guids, "Malformed/duplicate new ScriptGuid")
        else:
            require(r.normalized(value) == r.normalized(template[prop]),
                    "Nondefault added ModuleScript metadata: " + prop)


def validate_dom(before, after, source=None):
    source = controller_source() if source is None else source
    require(len(before) == 4532 and len(after) == 4533,
            "Expected exact 4532 -> 4533 one-ModuleScript B update")
    require(ADDED not in before, "Controller already exists in immutable baseline")
    baseline_sources = {path for path, node in before.items() if "Source" in node["properties"]}
    require(len(baseline_sources) == 156, "Expected all 156 accepted B Sources")
    after, reindexed = canonicalize(before, after)
    require({path for path, node in after.items() if "Source" in node["properties"]}
            == baseline_sources | {ADDED}, "Persistent Source set changed")
    require(all(before[path]["class"] in r.SCRIPT_CLASSES for path in baseline_sources),
            "Malformed baseline Source class")
    validate_added_module(before, after, source)
    changes, changed_shadows = [], set()
    for path, original in before.items():
        actual = after[path]
        require(set(original["properties"]) == set(actual["properties"]),
                "Retained property set changed: " + path)
        if path in SHADOW_PATHS:
            require(original["class"] == actual["class"] == "SpotLight"
                    and original["properties"]["Shadows"] == ["bool", "false", []]
                    and actual["properties"]["Shadows"] == ["bool", "true", []],
                    "Only required bank Shadows false -> true allowed: " + path)
        for prop, value in original["properties"].items():
            other = actual["properties"][prop]
            if value == other or r.normalized(value) == r.normalized(other):
                continue
            if path in SHADOW_PATHS and prop == "Shadows":
                changed_shadows.add(path)
                reason = "requested_flashlight_shadows"
            elif path == "Workspace/Camera" and prop in {"CFrame", "Focus"}:
                h.old.helpers.validate_camera_frame(other)
                reason = "finite_editor_camera"
            elif path in r.SELECTION_PATHS and original["class"] == "Instance" and prop == "UniqueId":
                reason = "editor_filtered_selection_identity"
            else:
                raise ValueError("Retained Source/world/art/Lighting/mesh metadata changed: "
                                 + path + "/" + prop)
            changes.append({"path": path, "property": prop, "reason": reason})
    require(changed_shadows == SHADOW_PATHS, "Exactly two light Shadows changes required")
    return {
        "passed": True, "complete": True, "variant": "B",
        "original_instances": 4532, "candidate_instances": 4533,
        "unchanged_sources": 156, "total_sources": 157, "source_changes": [],
        "new_instances": 1, "removed_instances": 0, "added_module_paths": [ADDED],
        "shadow_changes": 2, "reindexed_exporter_paths": reindexed,
        "retained_identities_classes_names_parents_exact": True,
        "world_art_physics_other_lighting_mesh_metadata_exact": True,
        "changes": changes,
    }


def check(candidate):
    candidate = Path(candidate).resolve()
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl",
            "Candidate must be an engine-saved binary RBXL")
    candidate_sha, source = sha(candidate), controller_source()
    with baseline_file() as original:
        before, bwarn = r.p.known_dom(original)
        after, awarn = r.p.known_dom(candidate)
        unknown_before = r.p.unknown_properties(original)
        unknown_after = r.p.unknown_properties(candidate)
        r.validate_unknown(unknown_before, unknown_after)
        report = validate_dom(before, after, source)
    require(sha(candidate) == candidate_sha and controller_source() == source,
            "Candidate/controller Source changed during read-only audit")
    return report | {
        "baseline_sha256": BASELINE_SHA, "baseline_bytes": BASELINE_BYTES,
        "candidate_sha256": candidate_sha, "candidate_bytes": candidate.stat().st_size,
        "new_module_source_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "untouched_A_sha256": A_SHA, "raw_terrain_exact": True,
        "raw_unknown_properties": unknown_after,
        "warnings": {"baseline": bwarn, "candidate": awarn},
        "scope": "B only: one default controller plus two bank Shadows flags. All 156 retained Sources and all retained world/art/physics/Lighting/mesh metadata/identities/parents/raw Terrain exact; finite editor Camera and existing FilteredSelection IDs only. No scene serialization or promotion.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    output = args.report.resolve()
    require(output.is_relative_to(OUT.resolve()) and output.suffix.lower() == ".json",
            "Report must remain in the corn-shadows evidence directory")
    require(output not in {args.candidate.resolve(), INFO.resolve()}, "Report would overwrite input")
    result = check(args.candidate)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes((json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({key: value for key, value in result.items()
                      if key not in {"changes", "warnings", "raw_unknown_properties"}}))
