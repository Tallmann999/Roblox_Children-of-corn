"""Strict read-only B audit: one default, explicitly pinned NightModeController.

The accepted engine Save is read from a fixed immutable ZIP. All 167 retained
Sources and every retained world/Lighting/Fog/physics/mesh property remain exact;
only existing finite editor Camera/FilteredSelection metadata may differ.
The sole addition is a childless default ModuleScript whose Source is read from
one fixed canonical file and must match an independently reviewed SHA256 pin.
No scene is serialized, rewritten, promoted or used to derive permissions.
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
spec = importlib.util.spec_from_file_location("night_toggle_save_helpers", ROOT / "scripts/verify-B-green-variants-copy.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
h, r, require = v.h, v.r, v.require
scalar, identity = v.scalar, v.identity
OUT = ROOT / ".artifacts/playtests/2026-10-23-B-night-toggle"
ARCHIVE = OUT / "before-night-toggle.zip"
ARCHIVE_ENTRY = "B-before-night-toggle.rbxl"
ARCHIVE_SHA256 = "b918a800c83baf29f063b72345c173d6abb411ea6106f0654b2c1eb22ef6f576"
BASELINE_SHA256 = "9cdcfd84e9f06a9763097f99bd14a5f6c65bf3650b11a694de349705c3495a19"
BASELINE_BYTES = 1758233
BASELINE_INSTANCES = 6053
BASELINE_SOURCES = 167
A_SCENE, A_SHA256 = v.A_SCENE, v.A_SHA256
C_SCENE, C_SHA256 = v.C_SCENE, v.C_SHA256
SOURCE = ROOT / "variants/B/client/Controllers/NightModeController.luau"
ADDED = "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/NightModeController"
MODULE_TEMPLATE = "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController"
GENERATED = {"UniqueId", "HistoryId", "ScriptGuid"}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def invariant_files():
    require(sha(A_SCENE) == A_SHA256, "A changed; preserve and independently review the author Save")
    require(sha(C_SCENE) == C_SHA256, "C changed; preserve and independently review the author Save")
    require(sha(ARCHIVE) == ARCHIVE_SHA256, "Immutable before-night-toggle ZIP changed")


@contextmanager
def baseline_file():
    invariant_files()
    with zipfile.ZipFile(ARCHIVE) as archive:
        require(archive.namelist() == [ARCHIVE_ENTRY], "Unexpected immutable ZIP entries")
        data = archive.read(ARCHIVE_ENTRY)
    require(len(data) == BASELINE_BYTES and hashlib.sha256(data).hexdigest() == BASELINE_SHA256,
            "Archived B differs from the accepted 9cdcfd84 engine Save")
    with tempfile.TemporaryDirectory(prefix="corn-night-toggle-read-only-") as directory:
        path = Path(directory) / ARCHIVE_ENTRY
        require(not path.resolve().is_relative_to(ROOT.resolve()), "Temporary baseline must be external")
        path.write_bytes(data)
        yield path
        require(sha(path) == BASELINE_SHA256, "Temporary baseline changed during audit")
    invariant_files()


def read_baseline():
    with baseline_file() as path:
        before, warning = r.p.known_dom(path)
        unknown = r.p.unknown_properties(path)
    return before, warning, unknown


def controller_source(source_sha256):
    require(v.valid_sha(source_sha256), "An explicit independently reviewed Source SHA256 pin is required")
    data = SOURCE.read_bytes()
    require(hashlib.sha256(data).hexdigest() == source_sha256, "Canonical NightModeController differs from reviewed Source pin")
    source = data.decode("utf-8")
    require(source.strip() and "\x00" not in source and "\r" not in source and not source.startswith("\ufeff")
            and len(data) <= 250_000, "Invalid or unexpectedly large NightModeController Source")
    return source


def expected_module(before, source):
    require(isinstance(source, str) and source.strip() and "\r" not in source and "\x00" not in source,
            "Exact LF Source text required")
    prototype = before[MODULE_TEMPLATE]
    require(prototype["class"] == "ModuleScript", "Immutable module prototype class differs")
    props = {key: value for key, value in prototype["properties"].items() if key not in GENERATED}
    require(props["AttributesSerialize"] == scalar("BinaryString", "")
            and props["Tags"] == scalar("BinaryString", "")
            and props["Capabilities"] == scalar("SecurityCapabilities", "0")
            and props["DefinesCapabilities"] == scalar("bool", "false")
            and props["SerializedOverrides"] == scalar("BinaryString", "")
            and props["SourceAssetId"] == scalar("int64", "-1"), "Prototype must have ordinary default Module metadata")
    return {"class": "ModuleScript", "properties": props | {
        "Name": scalar("string", "NightModeController"), "Source": scalar("string", source)}}


def validate_dom(before, after, source):
    require(len(before) == BASELINE_INSTANCES and len(after) == BASELINE_INSTANCES + 1,
            "Only the exact 6053 -> 6054 one-ModuleScript update is allowed")
    require(ADDED not in before, "NightModeController already exists in the immutable baseline")
    retained_sources = {path for path, node in before.items() if "Source" in node["properties"]}
    require(len(retained_sources) == BASELINE_SOURCES, "All 167 immutable Sources must be retained")
    expected = expected_module(before, source)
    after, reindexed = v.canonicalize(before, after, {ADDED: expected})
    require({path for path, node in after.items() if "Source" in node["properties"]} == retained_sources | {ADDED},
            "Persistent Source graph differs")
    recorded = []
    for path, original in before.items():
        actual = after[path]
        require(set(actual["properties"]) == set(original["properties"]), "Retained property schema differs: " + path)
        for prop, value in original["properties"].items():
            other = actual["properties"][prop]
            if v.same(value, other):
                continue
            if path == "Workspace/Camera" and prop in {"CFrame", "Focus"}:
                h.m.shadow.h.old.helpers.validate_camera_frame(other)
                reason = "finite_editor_camera"
            elif path in r.SELECTION_PATHS and original["class"] == "Instance" and prop == "UniqueId":
                reason = "existing_filtered_selection_identity"
            else:
                raise ValueError("Retained Source/world/art/Lighting/Fog/physics/mesh change: " + path + "/" + prop)
            recorded.append({"path": path, "property": prop, "reason": reason})
    props = after[ADDED]["properties"]
    require(set(props) == set(expected["properties"]) | GENERATED, "New Module complete property schema differs")
    uid = identity(after[ADDED])
    require(re.fullmatch(r"[0-9a-fA-F]{32}", uid) and int(uid, 16) != 0, "New UniqueId must be valid and nonzero")
    history = props["HistoryId"]
    require(history[0] == "UniqueId" and not history[2] and re.fullmatch(r"[0-9a-fA-F]{32}", history[1]),
            "Malformed generated HistoryId")
    guid = props["ScriptGuid"]
    old_guids = {node["properties"]["ScriptGuid"][1].lower() for node in before.values() if "ScriptGuid" in node["properties"]}
    require(guid[0] == "string" and not guid[2] and v.GUID.fullmatch(guid[1]) is not None
            and int(guid[1][1:-1].replace("-", ""), 16) != 0 and guid[1].lower() not in old_guids,
            "New ScriptGuid must be fresh, valid and nonzero")
    for prop, value in expected["properties"].items():
        require(v.same(props[prop], value), "New Module is not the exact default pinned controller: " + prop)
    return {"passed": True, "complete": True, "variant": "B", "original_instances": len(before),
            "candidate_instances": len(after), "new_instances": 1, "removed_instances": 0,
            "unchanged_sources": BASELINE_SOURCES, "total_sources": BASELINE_SOURCES + 1,
            "source_changes": [], "new_sources": [ADDED], "persistent_world_lighting_fog_changes": 0,
            "reindexed_exporter_paths": reindexed, "retained_identities_classes_names_parents_exact": True,
            "all_retained_world_art_lighting_fog_physics_mesh_metadata_exact": True,
            "new_engine_generated_metadata": ["fresh nonzero UniqueId", "HistoryId", "fresh nonzero ScriptGuid"],
            "changes": recorded}


def check(candidate, source_sha256):
    candidate = Path(candidate).resolve()
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "Engine-saved binary RBXL required")
    candidate_hash, source = sha(candidate), controller_source(source_sha256)
    with baseline_file() as original:
        before, before_warning = r.p.known_dom(original)
        after, after_warning = r.p.known_dom(candidate)
        ub, ua = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
        r.validate_unknown(ub, ua)
        report = validate_dom(before, after, source)
    require(sha(candidate) == candidate_hash and controller_source(source_sha256) == source,
            "Candidate or fixed canonical Source changed during audit")
    return report | {"baseline_sha256": BASELINE_SHA256, "baseline_bytes": BASELINE_BYTES,
                     "candidate_sha256": candidate_hash, "candidate_bytes": candidate.stat().st_size,
                     "new_module_source_sha256": source_sha256, "fixed_source_file": str(SOURCE.relative_to(ROOT)),
                     "untouched_A_sha256": A_SHA256, "untouched_C_sha256": C_SHA256, "raw_terrain_exact": True,
                     "raw_unknown_properties": ua, "warnings": {"baseline": before_warning, "candidate": after_warning},
                     "scope": "One childless default NightModeController with fixed-file explicitly pinned Source. All 167 retained Sources and retained identity/parent/world/art/Lighting/Fog/physics/mesh/raw Terrain exact. Existing finite editor Camera/FilteredSelection metadata only. No scene rewriting or promotion."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--source-sha256", required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    output = args.report.resolve()
    require(output.is_relative_to(OUT.resolve()) and output.suffix.lower() == ".json", "Report must remain in night-toggle evidence")
    require(output not in {args.candidate.resolve(), SOURCE.resolve(), ARCHIVE.resolve(),
                           (OUT / "baseline.json").resolve(), (OUT / "expected-before-sources.json").resolve()},
            "Report would overwrite an audit input")
    result = check(args.candidate, args.source_sha256)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key not in {"changes", "warnings", "raw_unknown_properties"}}))
