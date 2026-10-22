"""Read-only strict engine-save audit for B's frozen double-density Sources.

The immutable B baseline is decoded outside the repository. No scene is
serialized, rewritten or promoted. No world or asset changes are permitted.
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
spec = importlib.util.spec_from_file_location("double_density_dom_helpers", ROOT / "scripts/verify-corn-edge-shadows-copy.py")
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
m, r, require = h.m, h.r, h.require
scalar, equivalent, identity, remap_refs = h.scalar, h.equivalent, h.identity, h.remap_refs
decode_attributes, encode_attributes = h.decode_attributes, h.encode_attributes
source_sha, sha, canonicalize = h.source_sha, h.sha, h.canonicalize
OUT = ROOT / ".artifacts/playtests/2026-10-22-B-double-density"
ARCHIVE = OUT / "before-double-density.zip"
ARCHIVE_ENTRY = "checkpoint/B-before-double-density.rbxl"
ARCHIVE_SHA256 = "7c169aa2e045c36ba4d2b0bd6876be899a36fd682a62a202270e4928783741fd"
BASELINE_SHA256 = "94c55e17bed0dc2f4b2e7c6020f60c031d80bc636be16166fe0effb6df146d5f"
BASELINE_BYTES = 1499095
# Actual A file read before this task; no assumptions about native unsaved A work.
A_SHA256 = "c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7"
A_SCENE = ROOT / "place/Children_of_corn.rbxl"
INFO = OUT / "baseline.json"
PAYLOAD = OUT / "payload.json"
MANIFEST = OUT / "pipeline-manifest.json"
# Frozen after independent final Source review and check.ps1 PASS.
MANIFEST_SHA256 = "35d615863c28da95e9c51ceabdd89a9ce41609b79637418e88df42059ef9322d"
PAYLOAD_SHA256 = "a1955446f4d7b7b7093bd9ce575c08251cc0ee1fe3896cbc0d2b342da8732f90"
OWNER = "corn_double_density_v1"
BASELINE_INSTANCES = 4634
BASELINE_SOURCES = 157
ALLOWED_SOURCE_PATHS = {
    "ReplicatedStorage/GameShared/Game/CornLayout",
    "ReplicatedStorage/GameShared/Game/CornAppearance",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornBackdropController",
    "StarterPlayer/StarterPlayerScripts/GameClient/Controllers/CornWindController",
}


def baseline_info():
    info = json.loads(INFO.read_bytes(), object_pairs_hook=m.shadow.unique_object)
    expected = {"archive_sha256": ARCHIVE_SHA256, "baseline_sha256": BASELINE_SHA256,
                "baseline_bytes": BASELINE_BYTES, "untouched_A_sha256": A_SHA256}
    require(info == expected and type(info["baseline_bytes"]) is int, "Immutable double-density metadata differs")
    require(sha(ARCHIVE) == ARCHIVE_SHA256, "Immutable double-density ZIP changed")
    require(sha(A_SCENE) == A_SHA256, "A file changed; preserve author Save and review guard independently")
    return info


@contextmanager
def baseline_file():
    info_hash, info = sha(INFO), baseline_info()
    with zipfile.ZipFile(ARCHIVE) as archive:
        require(archive.namelist() == [ARCHIVE_ENTRY], "Unexpected immutable ZIP entries")
        require(archive.getinfo(ARCHIVE_ENTRY).file_size == BASELINE_BYTES, "Archived B length differs")
        data = archive.read(ARCHIVE_ENTRY)
    require(len(data) == BASELINE_BYTES and hashlib.sha256(data).hexdigest() == BASELINE_SHA256,
            "Archived B is not the accepted saved baseline")
    with tempfile.TemporaryDirectory(prefix="corn-double-density-read-only-") as directory:
        path = Path(directory) / "B-before-double-density.rbxl"
        require(not path.resolve().is_relative_to(ROOT.resolve()), "Temporary baseline must be external")
        path.write_bytes(data)
        yield path
        require(sha(path) == BASELINE_SHA256, "Temporary baseline changed")
    require(sha(INFO) == info_hash and baseline_info() == info, "Baseline inputs changed during audit")


def read_baseline():
    with baseline_file() as path:
        before, warning = r.p.known_dom(path)
        unknown = r.p.unknown_properties(path)
    return before, warning, unknown


def valid_sha(value):
    return isinstance(value, str) and re.fullmatch("[0-9a-f]{64}", value)


def read_manifest():
    require(valid_sha(MANIFEST_SHA256), "Final reviewed manifest SHA256 must be pinned before save audit")
    require(sha(MANIFEST) == MANIFEST_SHA256, "Frozen manifest bytes changed")
    manifest = json.loads(MANIFEST.read_bytes(), object_pairs_hook=m.shadow.unique_object)
    require(isinstance(manifest, dict) and set(manifest) == {"version", "owner", "payload_sha256", "sourceChanges"}
            and type(manifest["version"]) is int and manifest["version"] == 1
            and manifest["owner"] == OWNER, "Unrecognized double-density manifest")
    require(valid_sha(PAYLOAD_SHA256) and manifest["payload_sha256"] == PAYLOAD_SHA256,
            "Final reviewed payload SHA256 differs or is unpinned")
    changes = manifest["sourceChanges"]
    require(isinstance(changes, dict) and set(changes) == ALLOWED_SOURCE_PATHS,
            "Manifest must review exactly the intended B Source replacements")
    for path, row in changes.items():
        require(isinstance(row, dict) and set(row) == {"before_sha256", "after_sha256"}
                and all(valid_sha(value) for value in row.values())
                and row["before_sha256"] != row["after_sha256"], "Invalid frozen Source hash pair: " + path)
    return manifest


def read_payload(expected_sha256=None):
    manifest = read_manifest()
    require(expected_sha256 is None or expected_sha256 == PAYLOAD_SHA256,
            "Requested payload SHA256 differs from final reviewed pin")
    require(sha(PAYLOAD) == PAYLOAD_SHA256, "Frozen double-density payload bytes changed")
    return json.loads(PAYLOAD.read_bytes(), object_pairs_hook=m.shadow.unique_object)


def prepare_plan(before, payload):
    require(isinstance(payload, dict) and payload.get("owner") == OWNER, "Unrecognized double-density payload")
    require(payload.get("nodes") == [] and payload.get("changes") == [],
            "Double density permits no world nodes, properties or attributes to change")
    reviewed = read_manifest()
    require(len(before) == BASELINE_INSTANCES, "Accepted B node count differs")
    retained = {path: node for path, node in before.items() if "Source" in node["properties"]}
    sources, replacements = payload.get("sources"), payload.get("sourceChanges")
    require(len(retained) == BASELINE_SOURCES and isinstance(sources, dict)
            and set(sources) == set(retained), "All 157 accepted B Sources must be pinned")
    require(isinstance(replacements, dict) and set(replacements) == ALLOWED_SOURCE_PATHS,
            "Only the intended B Source changes are allowed")
    for path, node in retained.items():
        require(sources[path] == {"class": node["class"], "sha256": source_sha(node["properties"]["Source"][1])},
                "Immutable Source manifest differs: " + path)
    changes = {}
    for path, row in replacements.items():
        require(path in retained and isinstance(row, dict)
                and set(row) == {"before_sha256", "after_sha256", "source"}, "Malformed existing Source replacement")
        require(row["before_sha256"] == sources[path]["sha256"], "Replacement before Source hash differs")
        require({key: row[key] for key in ("before_sha256", "after_sha256")} == reviewed["sourceChanges"][path],
                "Source replacement differs from independent frozen manifest: " + path)
        text = row["source"]
        require(isinstance(text, str) and text.strip() and "\x00" not in text and "\r" not in text
                and len(text.encode()) <= 2_000_000, "Invalid replacement LF Source")
        require(source_sha(text) == row["after_sha256"] and row["after_sha256"] != row["before_sha256"],
                "Replacement Source hash differs or is a no-op")
        changes[path] = scalar("string", text)
    return {}, {}, changes


def validate_dom(before, after, payload):
    _, _, sources = prepare_plan(before, payload)
    after, reindexed = canonicalize(before, after)
    require(len(after) == len(before), "Retained node count differs")
    require({path for path, node in before.items() if "Source" in node["properties"]}
            == {path for path, node in after.items() if "Source" in node["properties"]}, "Source set differs")
    recorded, seen_sources = [], set()
    for path, original in before.items():
        actual = after[path]
        require(set(actual["properties"]) == set(original["properties"]), "Retained property schema differs: " + path)
        for prop, value in original["properties"].items():
            other = actual["properties"][prop]
            if prop == "Source" and path in sources:
                require(other[0] == "string" and not other[2] and other[1].replace("\r\n", "\n") == sources[path][1],
                        "Declared replacement Source differs: " + path)
                seen_sources.add(path)
                reason = "exact_payload_Source"
            elif value == other or r.normalized(value) == r.normalized(other):
                continue
            elif path == "Workspace/Camera" and prop in {"CFrame", "Focus"}:
                m.shadow.h.old.helpers.validate_camera_frame(other)
                reason = "finite_editor_camera"
            elif path in r.SELECTION_PATHS and original["class"] == "Instance" and prop == "UniqueId":
                reason = "editor_filtered_selection_identity"
            else:
                raise ValueError("Undeclared Source/world/art/Lighting/mesh change: " + path + "/" + prop)
            recorded.append({"path": path, "property": prop, "reason": reason})
    require(seen_sources == set(sources), "Frozen Source replacements not fully applied")
    return {"passed": True, "complete": True, "variant": "B", "original_instances": len(before),
            "candidate_instances": len(after), "new_instances": 0, "removed_instances": 0,
            "unchanged_sources": BASELINE_SOURCES - len(sources), "total_sources": BASELINE_SOURCES,
            "source_changes": sorted(sources), "declared_property_changes": 0,
            "declared_attribute_changes": 0, "added_world_nodes": 0,
            "reindexed_exporter_paths": reindexed, "retained_identities_classes_names_parents_exact": True,
            "all_world_art_lighting_physics_mesh_metadata_exact": True, "changes": recorded}


def check(candidate, expected_payload_sha256=None):
    candidate = Path(candidate).resolve()
    require(candidate.is_file() and candidate.suffix.lower() == ".rbxl", "An engine-saved binary RBXL is required")
    candidate_hash, payload_hash, manifest_hash = sha(candidate), sha(PAYLOAD), sha(MANIFEST)
    payload = read_payload(expected_payload_sha256)
    with baseline_file() as original:
        before, bwarn = r.p.known_dom(original)
        after, awarn = r.p.known_dom(candidate)
        ub, ua = r.p.unknown_properties(original), r.p.unknown_properties(candidate)
        r.validate_unknown(ub, ua)
        report = validate_dom(before, after, payload)
    require(sha(candidate) == candidate_hash and sha(PAYLOAD) == payload_hash and sha(MANIFEST) == manifest_hash,
            "Candidate/payload/manifest changed during audit")
    return report | {"baseline_sha256": BASELINE_SHA256, "candidate_sha256": candidate_hash,
                     "candidate_bytes": candidate.stat().st_size, "payload_sha256": payload_hash,
                     "manifest_sha256": manifest_hash, "untouched_A_sha256": A_SHA256,
                     "raw_terrain_exact": True, "raw_unknown_properties": ua,
                     "warnings": {"baseline": bwarn, "candidate": awarn},
                     "scope": "Only frozen B density Source replacements. All retained identities, classes, names, parents, world, art, physics, Lighting, mesh metadata and raw Terrain exact. Finite editor Camera and existing FilteredSelection identities only. No scene serialization or promotion."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--payload-sha256")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    output = args.report.resolve()
    require(output.is_relative_to(OUT.resolve()) and output.suffix.lower() == ".json", "Report must remain in double-density evidence")
    require(output not in {args.candidate.resolve(), PAYLOAD.resolve(), INFO.resolve(), MANIFEST.resolve(),
                           (OUT / "native-before.json").resolve()}, "Report would overwrite an audit input")
    report = check(args.candidate, args.payload_sha256)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({key: value for key, value in report.items() if key not in {"changes", "warnings", "raw_unknown_properties"}}))
